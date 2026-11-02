import SwiftUI
import AppKit
import AVKit
import CoreImage
import EditorCore

@main
struct EditorApp: App {
    var body: some Scene {
        WindowGroup("Photo & Video Editor") {
            EditorView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

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

    private let store: ProjectStore
    private var renderingRevision = 0
    private var gestureStart: EditRecipe?
    private var previewTask: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = ProjectStore(directory: support.appendingPathComponent("PhotoVideoEditor/Projects"))
        do {
            items = try store.loadAll().sorted { $0.current.lastModified > $1.current.lastModified }
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
        for url in panel.urls {
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
        UserDefaults.standard.set(id.uuidString, forKey: "selectedMediaID")
        refresh()
    }

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
        let adjustment = showingOriginal ? AdjustmentVector() : recipe.color.effective
        renderingRevision += 1
        let revision = renderingRevision
        if recipe.kind == .photo {
            player = nil
            previewTask?.cancel()
            let geometry = recipe.geometry
            previewTask = Task.detached(priority: .userInitiated) {
                do {
                    let cg = try MediaIO.photoPreviewCGImage(url: url, adjustment: adjustment, geometry: geometry)
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
            let wasPlaying = player?.rate ?? 0 > 0
            let position = player?.currentTime() ?? .zero
            Task {
                do {
                    let item = try await MediaIO.videoItem(url: url, adjustment: adjustment)
                    let assetDuration = try await AVURLAsset(url: url).load(.duration)
                    guard revision == renderingRevision else { return }
                    let next = AVPlayer(playerItem: item)
                    player = next
                    duration = assetDuration.seconds.isFinite ? assetDuration.seconds : 0
                    await next.seek(to: position)
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
                    try await MediaIO.exportVideo(url: source, to: destination, adjustment: recipe.color.effective)
                } else {
                    try MediaIO.exportPhoto(url: source, to: destination, adjustment: recipe.color.effective, geometry: recipe.geometry)
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

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("inspectorMode") private var inspectorMode = "Advanced"
    @AppStorage("shownManualHelp") private var shownManualHelp = false
    @State private var selectedBand = 0
    @State private var zoom = 1.0
    @State private var confirmReset = false
    private let bands = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if sidebarVisible { sidebar }
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: 340)
            }
        }
        .preferredColorScheme(.dark)
        .background(Color(red: 0.08, green: 0.09, blue: 0.09))
        .alert("Editor notice", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            if model.draft != nil { Button("Relink…") { model.error = nil; model.relink() } }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Reset all global color edits?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) { model.change { $0.color = ColorState() } }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button("Import", action: model.importFiles).keyboardShortcut("o", modifiers: .command)
            Button(sidebarVisible ? "Hide Files" : "Show Files") { sidebarVisible.toggle() }
            Button("Undo", action: model.undo).disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
            Button("Redo", action: model.redo).disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            Button(model.showingOriginal ? "Show Edited" : "Before/After") { model.showingOriginal.toggle(); model.refresh() }
                .disabled(model.draft == nil)
            Spacer()
            Text("Photo & Video Editor").font(.headline).foregroundStyle(.secondary)
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button("Export…", action: model.export).disabled(model.draft == nil || model.busy)
                .keyboardShortcut("e", modifiers: .command)
                .tint(Color(red: 0.82, green: 0.63, blue: 0.22))
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color(red: 0.13, green: 0.15, blue: 0.15))
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.items, id: \.current.id) { history in
                    let recipe = history.current
                    Button {
                        model.select(recipe.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Image(systemName: recipe.kind == .video ? "film" : "photo")
                            Text(URL(fileURLWithPath: recipe.sourcePath).lastPathComponent)
                                .lineLimit(2).font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(model.selectedID == recipe.id ? Color.blue.opacity(0.3) : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(URL(fileURLWithPath: recipe.sourcePath).lastPathComponent)")
                }
            }.padding(6)
        }
        .frame(width: 120)
        .background(Color(red: 0.13, green: 0.15, blue: 0.15))
    }

    private var preview: some View {
        VStack(spacing: 8) {
            if let recipe = model.draft {
                Text(URL(fileURLWithPath: recipe.sourcePath).lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let player = model.player {
                PlayerView(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = model.image {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoom)
                        .clipped()
                }
            } else if model.draft == nil {
                Button("Open Photos or Videos", action: model.importFiles)
                    .font(.title2)
            } else { ProgressView() }
            Spacer(minLength: 0)
            if model.kind == .video { videoControls }
            else if model.kind == .photo {
                HStack {
                    Button("Fit") { zoom = 1 }
                    Slider(value: $zoom, in: 1...3).frame(width: 120)
                    Text("\(Int(zoom * 100))%")
                }.font(.caption)
            }
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.09, blue: 0.09))
    }

    private var videoControls: some View {
        HStack {
            Button("Play") { model.player?.play() }
            Button("Pause") { model.player?.pause() }
            Slider(value: Binding(get: { model.seconds }, set: { model.seconds = $0; model.player?.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }), in: 0...max(model.duration, 0.01))
            Text(String(format: "%.1f / %.1f", model.seconds, model.duration)).font(.caption.monospacedDigit())
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            if let seconds = model.player?.currentTime().seconds, seconds.isFinite { model.seconds = seconds }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Global").font(.title3.bold())
            Picker("Controls", selection: $inspectorMode) {
                Text("Easy").tag("Easy")
                Text("Advanced").tag("Advanced")
            }.pickerStyle(.segmented)
            if model.draft == nil { Text("Import a file to begin.").foregroundStyle(.secondary) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if inspectorMode == "Easy" { easyInspector }
                        else { advancedInspector }
                        if model.kind == .photo { cropInspector }
                        Divider()
                        HStack {
                            Button("Reset Easy") { model.change { $0.color.resetEasy() } }
                            Button("Reset Manual") { model.change { $0.color.resetManual() } }
                        }
                        Button("Reset All") { confirmReset = true }
                    }.padding(.vertical, 6)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.13, green: 0.15, blue: 0.15))
    }

    private var easyInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Underwater Easy").font(.headline)
            easySlider("Water Color", \.waterColor, range: -100...100, hint: "Deepen Blue   ·   Remove Green")
            easySlider("Color Recovery", \.colorRecovery, range: 0...100)
            easySlider("Light", \.light, range: -100...100)
            easySlider("Visibility", \.visibility, range: 0...100)
            if model.draft?.color.manualDelta.isNeutral == false {
                Text(shownManualHelp ? "Customized in Advanced" : "Manual refinements are preserved when you change Easy controls. Start with Easy and finish with Advanced.")
                    .font(.caption).foregroundStyle(.secondary)
                    .onAppear { shownManualHelp = true }
            }
        }
    }

    private var cropInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Crop").font(.headline)
            Picker("Aspect", selection: Binding(get: { model.draft?.geometry.aspect ?? .original }, set: { value in
                model.change { $0.geometry.aspect = value }
            })) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in Text(aspect.rawValue).tag(aspect) }
            }
            if model.draft?.geometry.aspect != .original {
                Text("Horizontal position")
                Slider(value: Binding(get: { model.draft?.geometry.centerX ?? 0.5 }, set: { value in
                    model.change { $0.geometry.centerX = value }
                }), in: 0...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                Text("Vertical position")
                Slider(value: Binding(get: { model.draft?.geometry.centerY ?? 0.5 }, set: { value in
                    model.change { $0.geometry.centerY = value }
                }), in: 0...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
            }
        }
    }

    private func easySlider(_ title: String, _ key: WritableKeyPath<EasySettings, Double>, range: ClosedRange<Double>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text("\(Int(model.draft?.color.easy[keyPath: key] ?? 0))").monospacedDigit() }
            Slider(value: Binding(get: { model.draft?.color.easy[keyPath: key] ?? 0 }, set: { value in
                model.change { $0.color.setEasy { $0[keyPath: key] = value.rounded() } }
            }), in: range, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .accessibilityLabel(title)
            if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var advancedInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Light").font(.headline)
            ForEach([Parameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks], id: \.self) { parameter in advancedSlider(parameter) }
            Divider()
            Text("Color").font(.headline)
            ForEach([Parameter.temperature, .tint, .saturation, .vibrance], id: \.self) { parameter in advancedSlider(parameter) }
            Divider()
            Text("Color Mixer").font(.headline)
            Picker("Band", selection: $selectedBand) {
                ForEach(0..<bands.count, id: \.self) { index in Text(bands[index]).tag(index) }
            }
            Text("Positive Green Hue moves toward Aqua; positive Aqua Hue moves toward Blue.")
                .font(.caption2).foregroundStyle(.secondary)
            let parameters = Array(Parameter.allCases.dropFirst(10))
            ForEach(parameters[(selectedBand * 3)..<(selectedBand * 3 + 3)], id: \.self) { parameter in advancedSlider(parameter) }
        }
    }

    private func advancedSlider(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(parameter.title)
                    .onTapGesture(count: 2) { model.change { $0.color.setEffective(parameter, to: $0.color.base[parameter]) } }
                Spacer()
                Text(parameter == .exposure ? String(format: "%.2f", model.draft?.color.effective[parameter] ?? 0) : String(format: "%.0f", model.draft?.color.effective[parameter] ?? 0))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { model.draft?.color.effective[parameter] ?? 0 }, set: { value in
                model.change { $0.color.setEffective(parameter, to: value) }
            }), in: parameter.limits, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .accessibilityLabel(parameter.title)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { AVPlayerView() }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player; view.controlsStyle = .none }
}
