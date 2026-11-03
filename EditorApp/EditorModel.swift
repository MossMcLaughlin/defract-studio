import SwiftUI
import AppKit
import AVKit
import EditorCore

@MainActor
final class EditorModel: ObservableObject {
    @Published var items: [EditHistory] = []
    @Published var draft: EditRecipe?
    @Published var image: NSImage?
    @Published var player: AVPlayer?
    @Published var error: String?
    @Published var autosaveFailed = false
    @Published var busy = false
    @Published var duration = 0.0
    @Published var seconds = 0.0
    @Published var showingOriginal = false
    @Published var selectedMaskID: UUID?
    @Published var overlayVisible = false
    @Published var maskPanelActive = false
    @Published var brushOperation: BrushOperation = .add
    @Published var brushSize = 0.08
    @Published var brushFeather = 0.5
    @Published var detectingSubject = false
    @Published var sourceSize = CGSize.zero
    @Published var cropEditing = false
    @Published var exportSheetRequested = false
    @Published var exportProgress = 0.0
    @Published var lastExportURL: URL?
    @Published var exportPreviewFrame: OutputFrame?
    var closeAfterExport = false
    var closeWindowAfterExport: (() -> Void)?

    private let store: ProjectStore
    private var renderingRevision = 0
    private var gestureStart: EditRecipe?
    private var previewTask: Task<Void, Never>?
    private var subjectTask: Task<Data, Error>?
    private var exportTask: Task<Void, Never>?
    private var photoExportTask: Task<Void, Error>?
    private var analysisTask: Task<NoiseAnalysis, Error>?
    private var analysisRevision = 0
    private var analysisRequestIdentity: NoiseAnalysisIdentity?
    private var previewSourcePath: String?

    init(store: ProjectStore? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.store = store ?? ProjectStore(directory: support.appendingPathComponent("PhotoVideoEditor/Projects"))
        do {
            let loaded = try self.store.loadRecovering()
            items = loaded.histories.sorted { $0.current.lastModified > $1.current.lastModified }
            if !loaded.failedFiles.isEmpty {
                error = "Some saved sessions could not be opened. Their files were kept for recovery: \(loaded.failedFiles.map(\.lastPathComponent).joined(separator: ", "))"
            }
            let remembered = UserDefaults.standard.string(forKey: "selectedMediaID")
            let selected = items.first { $0.current.id.uuidString == remembered } ?? items.first
            if let selected { select(selected.current.id) }
        } catch { self.error = "Saved edits could not be loaded: \(error.localizedDescription)" }
    }

    var selectedID: UUID? { draft?.id }
    var kind: MediaKind? { draft?.kind }
    var canUndo: Bool { items.first { $0.current.id == selectedID }?.undoStack.isEmpty == false }
    var canRedo: Bool { items.first { $0.current.id == selectedID }?.redoStack.isEmpty == false }
    var hasUnexportedEdits: Bool { autosaveFailed || items.contains { $0.current.hasUnexportedEdits } }

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    func importURLs(_ urls: [URL]) {
        for url in urls {
            if let existing = items.first(where: { $0.current.sourcePath == url.path }) {
                select(existing.current.id)
            } else {
                let kind: MediaKind = ["mp4", "mov"].contains(url.pathExtension.lowercased()) ? .video : .photo
                var recipe = EditRecipe(sourcePath: url.path, kind: kind)
                recipe.sourceFileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                if kind == .photo {
                    do { recipe.sourceColor = try MediaIO.photoSourceColorDescriptor(url: url) }
                    catch { self.error = "Source color metadata could not be read: \(error.localizedDescription)"; continue }
                }
                let history = EditHistory(recipe)
                do {
                    try store.save(history)
                    items.append(history)
                    select(history.current.id)
                    if kind == .video {
                        scheduleVideoColorProbe(id: history.current.id, url: url, expectedSize: recipe.sourceFileSize)
                    }
                } catch { self.error = "Could not save the new edit session: \(error.localizedDescription)" }
            }
        }
    }

    private func scheduleVideoColorProbe(id: UUID, url: URL, expectedSize: Int64?) {
        Task {
            do {
                let descriptor = try await MediaIO.sourceColorDescriptor(url: url, kind: .video)
                guard let index = items.firstIndex(where: { $0.current.id == id }),
                      items[index].current.sourcePath == url.path,
                      items[index].current.sourceFileSize == expectedSize else { return }
                items[index].setSourceColor(descriptor)
                if draft?.id == id {
                    draft?.sourceColor = descriptor
                    draft?.noiseAnalysis = nil
                }
                persist(index)
                if selectedID == id { scheduleNoiseAnalysisIfNeeded() }
                if descriptor.dynamicRange == .hlg || descriptor.dynamicRange == .pq {
                    error = "This HDR source needs a verified SDR conversion before editing or export."
                }
            } catch { self.error = "Source color metadata could not be read: \(error.localizedDescription)" }
        }
    }

    func select(_ id: UUID) {
        guard let history = items.first(where: { $0.current.id == id }) else { return }
        let changedSource = selectedID != id
        if changedSource {
            analysisTask?.cancel()
            analysisTask = nil
            analysisRequestIdentity = nil
            analysisRevision += 1
        }
        draft = history.current
        selectedMaskID = history.current.masks.first?.id
        cropEditing = false
        if changedSource { lastExportURL = nil; exportProgress = 0; previewSourcePath = nil }
        UserDefaults.standard.set(id.uuidString, forKey: "selectedMediaID")
        scheduleNoiseAnalysisIfNeeded()
        refresh()
    }

    func toggleCropEditing() { cropEditing.toggle(); refresh() }

    func beginGesture() { gestureStart = draft }
    func endGesture() {
        if gestureStart != nil { commit() }
        gestureStart = nil
        scheduleNoiseAnalysisIfNeeded()
        refresh()
    }

    func change(_ update: (inout EditRecipe) -> Void) {
        guard var recipe = draft else { return }
        let previous = recipe
        update(&recipe)
        let sourceChanged = recipe.sourcePath != previous.sourcePath || recipe.videoTrim != previous.videoTrim
            || recipe.sourceColor != previous.sourceColor
        if sourceChanged { recipe.noiseAnalysis = nil }
        draft = recipe
        refresh()
        if gestureStart == nil {
            commit()
            if sourceChanged { scheduleNoiseAnalysisIfNeeded() }
        }
    }

    var selectedMask: EditMask? { draft?.masks.first { $0.id == selectedMaskID } }

    func selectMask(_ id: UUID) { selectedMaskID = id; refresh() }

    func addMask(_ kind: MaskKind) {
        guard kind != .subject, kind != .brush || self.kind == .photo else { return }
        let mask = EditMask(name: kind.rawValue.capitalized, kind: kind)
        change { $0.masks.append(mask) }
        selectMask(mask.id)
    }

    func updateMask(_ update: (inout EditMask) -> Void) {
        guard let selectedMaskID else { return }
        change { recipe in
            guard let index = recipe.masks.firstIndex(where: { $0.id == selectedMaskID }) else { return }
            update(&recipe.masks[index])
        }
    }

    func deleteSelectedMask() {
        guard let selectedMaskID else { return }
        change { $0.masks.removeAll { $0.id == selectedMaskID } }
        self.selectedMaskID = draft?.masks.first?.id
        refresh()
    }

    func duplicateSelectedMaskAsInverse() {
        guard let copy = selectedMask?.invertedCopy() else { return }
        change { recipe in
            guard let index = recipe.masks.firstIndex(where: { $0.id == selectedMaskID }) else { return }
            recipe.masks.insert(copy, at: index + 1)
        }
        selectMask(copy.id)
    }

    func detectSubject() {
        guard kind == .photo, let path = draft?.sourcePath, let id = selectedID else { return }
        detectingSubject = true
        let work = Task.detached(priority: .userInitiated) { try VisionMask.foregroundPNG(url: URL(fileURLWithPath: path)) }
        subjectTask = work
        Task {
            do {
                let matte = try await work.value
                guard subjectTask != nil, selectedID == id else { return }
                var mask = EditMask(name: "Subject", kind: .subject)
                mask.mattePNG = matte
                change { $0.masks.append(mask) }
                selectMask(mask.id)
            } catch {
                if subjectTask != nil { self.error = error.localizedDescription }
            }
            subjectTask = nil
            detectingSubject = false
        }
    }

    func cancelSubject() {
        subjectTask?.cancel()
        subjectTask = nil
        detectingSubject = false
    }

    func beginStroke(at point: NormalizedPoint) {
        guard kind == .photo, let mask = selectedMask, mask.kind == .brush || mask.kind == .subject else { return }
        beginGesture()
        updateMask { $0.strokes.append(BrushStroke(operation: brushOperation, points: [point], size: brushSize, feather: brushFeather)) }
    }

    func extendStroke(to point: NormalizedPoint) {
        updateMask { mask in
            guard let last = mask.strokes.indices.last else { return }
            if let previous = mask.strokes[last].points.last, hypot(previous.x - point.x, previous.y - point.y) < 0.003 { return }
            mask.strokes[last].points.append(point)
        }
    }

    func endStroke() { endGesture() }

    private func commit() {
        guard let draft, let index = items.firstIndex(where: { $0.current.id == draft.id }) else { return }
        items[index].apply { $0 = draft }
        self.draft = items[index].current
        do { try store.save(items[index]); autosaveFailed = false }
        catch { autosaveFailed = true; self.error = "Autosave failed; edits remain in memory. \(error.localizedDescription)" }
    }

    func undo() {
        guard let id = selectedID, let index = items.firstIndex(where: { $0.current.id == id }) else { return }
        items[index].undo()
        draft = items[index].current
        persist(index)
        scheduleNoiseAnalysisIfNeeded()
        refresh()
    }

    func redo() {
        guard let id = selectedID, let index = items.firstIndex(where: { $0.current.id == id }) else { return }
        items[index].redo()
        draft = items[index].current
        persist(index)
        scheduleNoiseAnalysisIfNeeded()
        refresh()
    }

    private func persist(_ index: Int) {
        do { try store.save(items[index]); autosaveFailed = false }
        catch { autosaveFailed = true; self.error = "Autosave failed; edits remain in memory. \(error.localizedDescription)" }
    }

    private func scheduleNoiseAnalysisIfNeeded() {
        guard let recipe = draft, (recipe.rendererVersion ?? 1) >= 4 else { return }
        if recipe.kind == .video && recipe.sourceColor == nil { return }
        let url = URL(fileURLWithPath: recipe.sourcePath)
        guard let identity = try? SourceNoiseAnalysis.identity(recipe: recipe, url: url) else { return }
        if recipe.noiseAnalysis?.identity == identity { return }
        if analysisRequestIdentity == identity { return }
        analysisTask?.cancel()
        analysisRevision += 1
        let revision = analysisRevision
        analysisRequestIdentity = identity
        if recipe.noiseAnalysis != nil, let index = items.firstIndex(where: { $0.current.id == recipe.id }) {
            items[index].setNoiseAnalysis(nil)
            draft?.noiseAnalysis = nil
            persist(index)
        }
        let work = Task.detached(priority: .utility) {
            try await SourceNoiseAnalysis.analyze(url: url, recipe: recipe, identity: identity)
        }
        analysisTask = work
        Task {
            defer {
                if analysisRevision == revision { analysisTask = nil; analysisRequestIdentity = nil }
            }
            do {
                let result = try await work.value
                guard analysisRevision == revision, selectedID == recipe.id,
                      let index = items.firstIndex(where: { $0.current.id == recipe.id }),
                      let activeDraft = draft,
                      let draftIdentity = try? SourceNoiseAnalysis.identity(recipe: activeDraft, url: url),
                      draftIdentity == identity,
                      let currentIdentity = try? SourceNoiseAnalysis.identity(recipe: items[index].current, url: url),
                      currentIdentity == identity else { return }
                items[index].setNoiseAnalysis(result)
                draft?.noiseAnalysis = result
                persist(index)
                refresh()
            } catch is CancellationError {
                return
            } catch {
                if analysisRevision == revision && selectedID == recipe.id {
                    self.error = "Source noise analysis is unavailable; manual Detail controls remain usable. \(error.localizedDescription)"
                }
            }
        }
    }

    func saveForClose() -> Bool {
        if gestureStart != nil { endGesture() }
        do {
            for history in items { try store.save(history) }
            autosaveFailed = false
            return true
        } catch {
            autosaveFailed = true
            self.error = "Could not save edits before closing: \(error.localizedDescription)"
            return false
        }
    }

    func refresh() {
        guard let recipe = draft else { return }
        let url = URL(fileURLWithPath: recipe.sourcePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            image = nil
            player = nil
            error = "Source is missing: \(url.lastPathComponent). Relink it to continue."
            return
        }
        var renderRecipe = recipe
        if showingOriginal { renderRecipe.color = ColorState(); renderRecipe.masks = []; renderRecipe.detail = TechnicalDetail() }
        if cropEditing { renderRecipe.geometry = Geometry(); renderRecipe.outputFrame = nil }
        else if let exportPreviewFrame { renderRecipe.outputFrame = exportPreviewFrame }
        renderingRevision += 1
        let revision = renderingRevision
        if recipe.kind == .photo {
            player = nil
            if previewSourcePath != url.path {
                sourceSize = (try? MediaIO.photoImage(url: url).extent.size) ?? .zero
                previewSourcePath = url.path
            }
            previewTask?.cancel()
            let overlayID = overlayVisible && maskPanelActive && !cropEditing && !showingOriginal ? selectedMaskID : nil
            let interactive = gestureStart != nil
            previewTask = Task.detached(priority: .userInitiated) {
                do {
                    if interactive { try await Task.sleep(for: .milliseconds(35)) }
                    try Task.checkCancellation()
                    let cg = try MediaIO.photoPreviewCGImage(url: url, recipe: renderRecipe, selectedMaskID: overlayID, maxPixelSize: interactive ? 900 : 1800)
                    await MainActor.run {
                        guard revision == self.renderingRevision else { return }
                        self.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    }
                } catch {
                    await MainActor.run { if revision == self.renderingRevision { self.error = error.localizedDescription } }
                }
            }
        } else {
            image = nil
            let overlayID = overlayVisible && maskPanelActive && !cropEditing && !showingOriginal ? selectedMaskID : nil
            let wasPlaying = player?.rate ?? 0 > 0
            let position = player?.currentTime() ?? .zero
            let existingItem = previewSourcePath == url.path ? player?.currentItem : nil
            Task {
                do {
                    let asset = AVURLAsset(url: url)
                    if let existingItem {
                        let composition = try await MediaIO.videoComposition(asset: asset, recipe: renderRecipe, selectedMaskID: overlayID)
                        guard revision == renderingRevision else { return }
                        existingItem.videoComposition = composition
                        if let end = recipe.videoTrim.endSeconds { existingItem.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }
                        return
                    }
                    let item = try await MediaIO.videoItem(url: url, recipe: renderRecipe, selectedMaskID: overlayID)
                    let assetDuration = try await asset.load(.duration)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let track = tracks.first
                    let naturalSize = try await track?.load(.naturalSize) ?? .zero
                    let preferredTransform = try await track?.load(.preferredTransform) ?? .identity
                    let displayedSize = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized.size
                    guard revision == renderingRevision else { return }
                    let next = AVPlayer(playerItem: item)
                    player = next
                    previewSourcePath = url.path
                    duration = assetDuration.seconds.isFinite ? assetDuration.seconds : 0
                    sourceSize = displayedSize
                    let start = recipe.videoTrim.startSeconds
                    let end = recipe.videoTrim.endSeconds ?? assetDuration.seconds
                    let seek = position.seconds < start || position.seconds >= end
                        ? CMTime(seconds: start, preferredTimescale: 600) : position
                    await next.seek(to: seek)
                    if wasPlaying { next.play() }
                } catch { if revision == renderingRevision { self.error = error.localizedDescription } }
            }
        }
    }

    func previewExport(_ frame: OutputFrame) {
        exportPreviewFrame = frame
        refresh()
    }

    func clearExportPreview() {
        exportPreviewFrame = nil
        refresh()
    }

    func startExport(_ options: ExportOptions, overwrite: Bool) throws {
        guard let current = draft, !busy else { return }
        let destination = try options.destination(kind: current.kind)
        let source = URL(fileURLWithPath: current.sourcePath)
        guard destination.standardizedFileURL != source.standardizedFileURL else {
            throw NSError(domain: "Editor", code: 9, userInfo: [NSLocalizedDescriptionKey: "The export destination is the original file."])
        }
        guard current.kind == .photo || (options.width % 2 == 0 && options.height % 2 == 0) else {
            throw NSError(domain: "Editor", code: 32, userInfo: [NSLocalizedDescriptionKey: "Video dimensions must be even pixel values."])
        }
        try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)
        change { $0.outputFrame = options.outputFrame; $0.videoCodec = options.videoCodec }
        guard let snapshot = draft else { return }
        busy = true
        exportProgress = 0
        lastExportURL = nil
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                if snapshot.kind == .video {
                    try await MediaIO.exportVideo(url: source, to: destination, recipe: snapshot, overwrite: overwrite) { [weak self] value in
                        Task { @MainActor in self?.exportProgress = value }
                    }
                } else {
                    self.exportProgress = 0.1
                    let quality = options.preset == .instagram ? 0.88 : options.preset == .general ? 0.90 : 0.95
                    let work = Task.detached(priority: .userInitiated) {
                        try MediaIO.exportPhoto(url: source, to: destination, recipe: snapshot,
                                                format: options.photoFormat, quality: quality, overwrite: overwrite)
                    }
                    self.photoExportTask = work
                    try await work.value
                }
                if Task.isCancelled { throw CancellationError() }
                if let index = self.items.firstIndex(where: { $0.current.id == snapshot.id }), self.items[index].current == snapshot {
                    self.items[index].markExported()
                    self.persist(index)
                    if self.selectedID == snapshot.id { self.draft = self.items[index].current }
                }
                self.exportProgress = 1
                self.lastExportURL = destination
                if self.closeAfterExport && !self.autosaveFailed {
                    self.closeAfterExport = false
                    self.closeWindowAfterExport?()
                }
            } catch is CancellationError {
                self.exportProgress = 0
            } catch {
                self.error = "Export failed: \(error.localizedDescription)"
            }
            self.busy = false
            self.photoExportTask = nil
            self.exportTask = nil
        }
    }

    func cancelExport() {
        photoExportTask?.cancel()
        exportTask?.cancel()
    }

    func relink() {
        guard let id = selectedID else { return }
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let expected = draft?.sourceFileSize,
           let actual = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
           actual != expected {
            error = "The selected file has a different size from the missing source. Choose the original file."
            return
        }
        let kind = draft?.kind
        let photoColor: SourceColorDescriptor?
        if kind == .photo {
            do { photoColor = try MediaIO.photoSourceColorDescriptor(url: url) }
            catch { self.error = "Source color metadata could not be read: \(error.localizedDescription)"; return }
        } else { photoColor = nil }
        change { $0.sourcePath = url.path; $0.sourceColor = photoColor }
        if kind == .video { scheduleVideoColorProbe(id: id, url: url, expectedSize: draft?.sourceFileSize) }
        select(id)
    }
}
