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
    @Published var busy = false
    @Published var duration = 0.0
    @Published var seconds = 0.0
    @Published var showingOriginal = false
    @Published var selectedMaskID: UUID?
    @Published var overlayVisible = true
    @Published var maskPanelActive = false
    @Published var brushOperation: BrushOperation = .add
    @Published var brushSize = 0.08
    @Published var brushFeather = 0.5
    @Published var detectingSubject = false
    @Published var sourceSize = CGSize.zero
    @Published var cropEditing = false

    private let store: ProjectStore
    private var renderingRevision = 0
    private var gestureStart: EditRecipe?
    private var previewTask: Task<Void, Never>?
    private var subjectTask: Task<Data, Error>?

    init(store: ProjectStore? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.store = store ?? ProjectStore(directory: support.appendingPathComponent("PhotoVideoEditor/Projects"))
        do {
            items = try self.store.loadAll().sorted { $0.current.lastModified > $1.current.lastModified }
            let remembered = UserDefaults.standard.string(forKey: "selectedMediaID")
            let selected = items.first { $0.current.id.uuidString == remembered } ?? items.first
            if let selected { select(selected.current.id) }
        } catch { self.error = "Saved edits could not be loaded: \(error.localizedDescription)" }
    }

    var selectedID: UUID? { draft?.id }
    var kind: MediaKind? { draft?.kind }
    var canUndo: Bool { items.first { $0.current.id == selectedID }?.undoStack.isEmpty == false }
    var canRedo: Bool { items.first { $0.current.id == selectedID }?.redoStack.isEmpty == false }

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
                let history = EditHistory(EditRecipe(sourcePath: url.path, kind: kind))
                do {
                    try store.save(history)
                    items.append(history)
                    select(history.current.id)
                } catch { self.error = "Could not save the new edit session: \(error.localizedDescription)" }
            }
        }
    }

    func select(_ id: UUID) {
        guard let history = items.first(where: { $0.current.id == id }) else { return }
        draft = history.current
        selectedMaskID = history.current.masks.first?.id
        cropEditing = false
        UserDefaults.standard.set(id.uuidString, forKey: "selectedMediaID")
        refresh()
    }

    func toggleCropEditing() { cropEditing.toggle(); refresh() }

    func beginGesture() { gestureStart = draft }
    func endGesture() {
        if gestureStart != nil { commit() }
        gestureStart = nil
    }

    func change(_ update: (inout EditRecipe) -> Void) {
        guard var recipe = draft else { return }
        update(&recipe)
        draft = recipe
        refresh()
        if gestureStart == nil { commit() }
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
        do { try store.save(items[index]) }
        catch { self.error = "Autosave failed; edits remain in memory. \(error.localizedDescription)" }
    }

    func undo() {
        guard let id = selectedID, let index = items.firstIndex(where: { $0.current.id == id }) else { return }
        items[index].undo()
        draft = items[index].current
        persist(index)
        refresh()
    }

    func redo() {
        guard let id = selectedID, let index = items.firstIndex(where: { $0.current.id == id }) else { return }
        items[index].redo()
        draft = items[index].current
        persist(index)
        refresh()
    }

    private func persist(_ index: Int) {
        do { try store.save(items[index]) }
        catch { self.error = "Autosave failed; edits remain in memory. \(error.localizedDescription)" }
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
        if showingOriginal { renderRecipe.color = ColorState(); renderRecipe.masks = [] }
        if cropEditing { renderRecipe.geometry = Geometry(); renderRecipe.outputFrame = nil }
        renderingRevision += 1
        let revision = renderingRevision
        if recipe.kind == .photo {
            player = nil
            sourceSize = (try? MediaIO.photoImage(url: url).extent.size) ?? .zero
            previewTask?.cancel()
            let overlayID = overlayVisible && maskPanelActive && !cropEditing && !showingOriginal ? selectedMaskID : nil
            previewTask = Task.detached(priority: .userInitiated) {
                do {
                    let cg = try MediaIO.photoPreviewCGImage(url: url, recipe: renderRecipe, selectedMaskID: overlayID)
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
            Task {
                do {
                    let item = try await MediaIO.videoItem(url: url, recipe: renderRecipe, selectedMaskID: overlayID)
                    let asset = AVURLAsset(url: url)
                    let assetDuration = try await asset.load(.duration)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let track = tracks.first
                    let naturalSize = try await track?.load(.naturalSize) ?? .zero
                    let preferredTransform = try await track?.load(.preferredTransform) ?? .identity
                    let displayedSize = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized.size
                    guard revision == renderingRevision else { return }
                    let next = AVPlayer(playerItem: item)
                    player = next
                    duration = assetDuration.seconds.isFinite ? assetDuration.seconds : 0
                    sourceSize = displayedSize
                    let start = recipe.videoTrim.startSeconds
                    let seek = position.seconds < start ? CMTime(seconds: start, preferredTimescale: 600) : position
                    await next.seek(to: seek)
                    if wasPlaying { next.play() }
                } catch { if revision == renderingRevision { self.error = error.localizedDescription } }
            }
        }
    }

    func export() {
        guard let recipe = draft else { return }
        let source = URL(fileURLWithPath: recipe.sourcePath)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-edited." + (recipe.kind == .video ? "mp4" : "jpg")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        Task {
            do {
                if recipe.kind == .video {
                    try await MediaIO.exportVideo(url: source, to: destination, recipe: recipe)
                } else {
                    try MediaIO.exportPhoto(url: source, to: destination, recipe: recipe)
                }
            } catch { self.error = "Export failed: \(error.localizedDescription)" }
            busy = false
        }
    }

    func relink() {
        guard let id = selectedID else { return }
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        change { $0.sourcePath = url.path }
        select(id)
    }
}
