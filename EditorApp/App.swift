import SwiftUI
import AppKit
import AVKit
import CoreImage
import EditorCore

@main
struct EditorApp: App {
    @NSApplicationDelegateAdaptor(EditorApplicationDelegate.self) private var applicationDelegate
    var body: some Scene {
        WindowGroup("Photo & Video Editor") {
            EditorView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}


struct EditorView: View {
    @StateObject private var model = EditorModel()
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("inspectorMode") private var inspectorMode = "Advanced"
    @AppStorage("inspectorTab") private var inspectorTab = "Global"
    @AppStorage("shownManualHelp") private var shownManualHelp = false
    @State private var selectedBand = 0
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var panAtDragStart: CGSize?
    @State private var confirmReset = false
    @State private var painting = false
    @State private var hoverLocation: CGPoint?

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
        .onAppear { model.maskPanelActive = inspectorTab == "Masks"; model.refresh() }
        .sheet(isPresented: $model.exportSheetRequested) { ExportSheet(model: model) }
        .background(WindowCloseObserver(model: model).frame(width: 0, height: 0))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            if !sidebarVisible { Button("Show Files") { sidebarVisible = true }.accessibilityLabel("Show Files") }
            Button("Undo", action: model.undo).disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
            Button("Redo", action: model.redo).disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            Button(model.showingOriginal ? "Show Edited" : "Before/After") { model.showingOriginal.toggle(); model.refresh() }
                .disabled(model.draft == nil)
            Button(model.cropEditing ? "Done Cropping" : "Crop & Rotate") { resetZoom(); model.toggleCropEditing() }
                .disabled(model.draft == nil)
            Spacer()
            Text("Photo & Video Editor").font(.headline).foregroundStyle(.secondary)
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button("Export…") { model.exportSheetRequested = true }
                .disabled(model.draft == nil || model.busy || model.sourceSize == .zero)
                .keyboardShortcut("e", modifiers: .command)
                .tint(Color(red: 0.82, green: 0.63, blue: 0.22))
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color(red: 0.13, green: 0.15, blue: 0.15))
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Import", action: model.importFiles).keyboardShortcut("o", modifiers: .command)
                Spacer()
                Button { sidebarVisible = false } label: { Image(systemName: "sidebar.left") }
                    .help("Hide Files").accessibilityLabel("Hide Files")
            }.buttonStyle(.borderless).padding(.horizontal, 8).padding(.top, 8)
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.items, id: \.current.id) { history in
                    let recipe = history.current
                    Button {
                        model.select(recipe.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            MediaThumbnail(path: recipe.sourcePath, kind: recipe.kind)
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
        }
        .frame(width: 128)
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
                    .overlay {
                        if model.cropEditing { CropOverlay(model: model) }
                        else if inspectorTab == "Masks", model.selectedMask?.kind == .linear || model.selectedMask?.kind == .radial {
                            GradientOverlay(model: model)
                        }
                    }
            } else if let image = model.image {
                GeometryReader { geometry in
                    ZStack {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(zoom)
                            .offset(pan)
                            .clipped()
                        if model.cropEditing { CropOverlay(model: model) }
                        else if inspectorTab == "Masks", model.selectedMask?.kind == .linear || model.selectedMask?.kind == .radial {
                            GradientOverlay(model: model)
                        }
                        else if inspectorTab == "Masks", model.kind == .photo,
                           model.selectedMask?.kind == .brush || model.selectedMask?.kind == .subject {
                            Color.clear.contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location): hoverLocation = location
                                    case .ended: hoverLocation = nil
                                    }
                                }
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let point = brushPoint(value.location, viewSize: geometry.size, imageSize: image.size) else { return }
                                        if !painting { model.beginStroke(at: point); painting = true }
                                        else { model.extendStroke(to: point) }
                                    }
                                    .onEnded { _ in if painting { model.endStroke(); painting = false } })
                            if let hoverLocation {
                                Circle().stroke(.white, lineWidth: 1.5)
                                    .frame(width: brushDiameter(viewSize: geometry.size, imageSize: image.size), height: brushDiameter(viewSize: geometry.size, imageSize: image.size))
                                    .position(hoverLocation)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .background(WheelZoomView { delta, location in
                        changeZoom(by: delta, at: location, viewSize: geometry.size)
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { value in
                        guard zoom > 1, inspectorTab != "Masks", !model.cropEditing else { return }
                        if panAtDragStart == nil { panAtDragStart = pan }
                        let start = panAtDragStart ?? .zero
                        pan = constrainedPan(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height), viewSize: geometry.size, imageSize: image.size)
                    }.onEnded { _ in panAtDragStart = nil })
                    .onChange(of: geometry.size) { _, size in
                        pan = constrainedPan(pan, viewSize: size, imageSize: image.size)
                    }
                    .onChange(of: zoom) { _, _ in
                        pan = constrainedPan(pan, viewSize: geometry.size, imageSize: image.size)
                    }
                }
            } else if model.draft == nil {
                Button("Open Photos or Videos", action: model.importFiles)
                    .font(.title2)
            } else { ProgressView() }
            Spacer(minLength: 0)
            if model.kind == .video { videoControls }
            else if model.kind == .photo {
                HStack {
                    Button("Fit") { resetZoom() }
                    Slider(value: $zoom, in: 1...4).frame(width: 120)
                    Text(zoom == 1 ? "Fit" : String(format: "%.1f× Fit", zoom))
                }.font(.caption)
            }
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.09, blue: 0.09))
    }

    private var videoControls: some View {
        VStack(spacing: 5) {
            HStack {
                Button("Play") { model.player?.play() }
                Button("Pause") { model.player?.pause() }
                Slider(value: Binding(get: { model.seconds }, set: { model.seconds = $0; model.player?.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }), in: 0...max(model.duration, 0.01))
                Text(String(format: "%.1f / %.1f", model.seconds, model.duration)).font(.caption.monospacedDigit())
            }
            HStack {
                Text("In \(model.draft?.videoTrim.startSeconds ?? 0, specifier: "%.2f")")
                Slider(value: Binding(get: { model.draft?.videoTrim.startSeconds ?? 0 }, set: { value in
                    model.change { $0.videoTrim.startSeconds = min(value, ($0.videoTrim.endSeconds ?? model.duration) - 0.05) }
                }), in: 0...max(0.01, (model.draft?.videoTrim.endSeconds ?? model.duration) - 0.05), onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                Text("Out \(model.draft?.videoTrim.endSeconds ?? model.duration, specifier: "%.2f")")
                Slider(value: Binding(get: { model.draft?.videoTrim.endSeconds ?? model.duration }, set: { value in
                    model.change { $0.videoTrim.endSeconds = max(value, $0.videoTrim.startSeconds + 0.05) }
                }), in: min(model.duration, (model.draft?.videoTrim.startSeconds ?? 0) + 0.05)...max(model.duration, 0.05), onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
            }.font(.caption)
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            if let seconds = model.player?.currentTime().seconds, seconds.isFinite { model.seconds = seconds }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Inspector", selection: $inspectorTab) {
                Text("Global").tag("Global")
                Text("Masks").tag("Masks")
            }.pickerStyle(.segmented)
            .onChange(of: inspectorTab) { _, mode in model.maskPanelActive = mode == "Masks"; model.refresh() }
            if model.draft == nil { Text("Import a file to begin.").foregroundStyle(.secondary) }
            else if inspectorTab == "Masks" { MaskInspector(model: model) }
            else {
                Picker("Controls", selection: $inspectorMode) {
                    Text("Easy").tag("Easy")
                    Text("Advanced").tag("Advanced")
                }.pickerStyle(.segmented)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if inspectorMode == "Easy" { easyInspector }
                        else { advancedInspector }
                        if model.kind != nil { cropInspector }
                        Divider()
                        Menu("More") { Button("Reset All Global Color…") { confirmReset = true } }
                    }.padding(.vertical, 6)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.13, green: 0.15, blue: 0.15))
    }

    private func brushPoint(_ location: CGPoint, viewSize: CGSize, imageSize: NSSize) -> NormalizedPoint? {
        guard let recipe = model.draft, model.sourceSize.width > 0, model.sourceSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height) * zoom
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let u = (location.x - pan.width - (viewSize.width - width) / 2) / width
        let v = (location.y - pan.height - (viewSize.height - height) / 2) / height
        guard (0...1).contains(u), (0...1).contains(v) else { return nil }
        let geometrySize = recipe.geometry.outputSize(for: model.sourceSize)
        let outputPoint = recipe.outputFrame?.inputPoint(fromOutputNormalized: NormalizedPoint(u, v), inputSize: geometrySize)
            ?? NormalizedPoint(u, v)
        guard (0...1).contains(outputPoint.x), (0...1).contains(outputPoint.y) else { return nil }
        let point = recipe.geometry.sourcePoint(fromOutputNormalized: outputPoint, sourceSize: model.sourceSize)
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        return point
    }

    private func resetZoom() { zoom = 1; pan = .zero; panAtDragStart = nil }

    private func constrainedPan(_ proposed: CGSize, viewSize: CGSize, imageSize: NSSize) -> CGSize {
        let fit = min(viewSize.width / max(1, imageSize.width), viewSize.height / max(1, imageSize.height))
        let limitX = max(0, (imageSize.width * fit * zoom - viewSize.width) / 2)
        let limitY = max(0, (imageSize.height * fit * zoom - viewSize.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, proposed.width)), height: min(limitY, max(-limitY, proposed.height)))
    }

    private func changeZoom(by delta: CGFloat, at location: CGPoint, viewSize: CGSize) {
        guard model.kind == .photo, let image = model.image else { return }
        let old = zoom
        zoom = min(4, max(1, zoom * exp(Double(delta) * 0.015)))
        let factor = zoom / old
        let proposed = CGSize(width: (pan.width - (location.x - viewSize.width / 2)) * factor + (location.x - viewSize.width / 2),
                              height: (pan.height - (location.y - viewSize.height / 2)) * factor + (location.y - viewSize.height / 2))
        pan = zoom == 1 ? .zero : constrainedPan(proposed, viewSize: viewSize, imageSize: image.size)
    }

    private func brushDiameter(viewSize: CGSize, imageSize: NSSize) -> CGFloat {
        guard let recipe = model.draft, model.sourceSize.width > 0, imageSize.width > 0 else { return 10 }
        let output = recipe.geometry.outputSize(for: model.sourceSize)
        let center = NormalizedPoint(0.5, 0.5)
        let edge = NormalizedPoint(0.5 + model.brushSize * min(model.sourceSize.width, model.sourceSize.height) / (2 * model.sourceSize.width), 0.5)
        var displayedCenter = recipe.geometry.outputPoint(fromSourceNormalized: center, sourceSize: model.sourceSize)
        var displayedEdge = recipe.geometry.outputPoint(fromSourceNormalized: edge, sourceSize: model.sourceSize)
        if let frame = recipe.outputFrame {
            displayedCenter = frame.outputPoint(fromInputNormalized: displayedCenter, inputSize: output)
            displayedEdge = frame.outputPoint(fromInputNormalized: displayedEdge, inputSize: output)
        }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height) * zoom
        let dx = (displayedEdge.x - displayedCenter.x) * imageSize.width
        let dy = (displayedEdge.y - displayedCenter.y) * imageSize.height
        return max(4, 2 * hypot(dx, dy) * scale)
    }

    private var easyInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Underwater Easy", help: "Reset Easy sliders") { model.change { $0.color.resetEasy() } }
            easySlider("Water Color", \.waterColor, range: -100...100, hint: "Deepen Blue|Remove Green")
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
            sectionHeader("Crop & Rotate", help: "Reset crop and rotation") { model.change { $0.geometry = Geometry() } }
            Picker("Aspect", selection: Binding(get: { model.draft?.geometry.aspect ?? .original }, set: { value in
                model.change { $0.geometry.aspect = value }
            })) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in Text(aspect.rawValue).tag(aspect) }
            }
            if model.draft?.geometry.aspect == .free {
                Text("Crop width")
                Slider(value: Binding(get: { model.draft?.geometry.freeWidth ?? 1 }, set: { value in
                    model.change { $0.geometry.freeWidth = value }
                }), in: 0.1...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                Text("Crop height")
                Slider(value: Binding(get: { model.draft?.geometry.freeHeight ?? 1 }, set: { value in
                    model.change { $0.geometry.freeHeight = value }
                }), in: 0.1...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
            } else if model.draft?.geometry.aspect != .original {
                Text("Crop size")
                Slider(value: Binding(get: { model.draft?.geometry.cropScale ?? 1 }, set: { value in
                    model.change { $0.geometry.cropScale = value }
                }), in: 0.1...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
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
            HStack {
                Button("Rotate Left") { model.change { $0.geometry.rotateQuarterTurns -= 1 } }
                Button("Rotate Right") { model.change { $0.geometry.rotateQuarterTurns += 1 } }
            }
            Text("Straighten \(model.draft?.geometry.straightenDegrees ?? 0, specifier: "%.1f")°")
            Slider(value: Binding(get: { model.draft?.geometry.straightenDegrees ?? 0 }, set: { value in
                model.change { $0.geometry.straightenDegrees = value }
            }), in: -20...20, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
        }
    }

    private func easySlider(_ title: String, _ key: WritableKeyPath<EasySettings, Double>, range: ClosedRange<Double>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text("\(Int(model.draft?.color.easy[keyPath: key] ?? 0))").monospacedDigit() }
            Slider(value: Binding(get: { model.draft?.color.easy[keyPath: key] ?? 0 }, set: { value in
                model.change { $0.color.setEasy { $0[keyPath: key] = value.rounded() } }
            }), in: range, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .accessibilityLabel(title)
            if let hint {
                let labels = hint.split(separator: "|")
                HStack { Text(String(labels[0])); Spacer(); Text(String(labels.count > 1 ? labels[1] : "")) }
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var advancedInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Light", help: "Reset manual Light adjustments") { model.change { $0.color.resetManual([.exposure, .contrast, .highlights, .shadows, .whites, .blacks]) } }
            ForEach([Parameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks], id: \.self) { parameter in advancedSlider(parameter) }
            Divider()
            sectionHeader("Color", help: "Reset manual Color adjustments") { model.change { $0.color.resetManual([.temperature, .tint, .saturation, .vibrance]) } }
            ForEach([Parameter.temperature, .tint, .saturation, .vibrance], id: \.self) { parameter in advancedSlider(parameter) }
            Divider()
            sectionHeader("Color Mixer", help: "Reset all manual Color Mixer adjustments") { model.change { $0.color.resetManual(Array(Parameter.allCases.dropFirst(10))) } }
            MixerBandPicker(selection: $selectedBand)
            Text("Positive Green Hue moves toward Aqua; positive Aqua Hue moves toward Blue.")
                .font(.caption2).foregroundStyle(.secondary)
            let parameters = Array(Parameter.allCases.dropFirst(10))
            ForEach(parameters[(selectedBand * 3)..<(selectedBand * 3 + 3)], id: \.self) { parameter in advancedSlider(parameter, mixer: true) }
        }
    }

    private func advancedSlider(_ parameter: Parameter, mixer: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(mixer ? String(parameter.title.split(separator: " ").last ?? "") : parameter.title)
                    .onTapGesture(count: 2) { model.change { $0.color.setEffective(parameter, to: $0.color.base[parameter]) } }
                Spacer()
                Text(parameter == .exposure ? String(format: "%.2f", model.draft?.color.effective[parameter] ?? 0) : String(format: "%.0f", model.draft?.color.effective[parameter] ?? 0))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { model.draft?.color.effective[parameter] ?? 0 }, set: { value in
                model.change { $0.color.setEffective(parameter, to: value) }
            }), in: parameter.limits, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .accessibilityLabel(parameter.title)
            if mixer && parameter.rawValue.hasSuffix("Hue") { MixerHueGuide(band: selectedBand) }
        }
    }

    private func sectionHeader(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action: action) { Image(systemName: "arrow.counterclockwise").font(.caption) }
                .buttonStyle(.borderless).help(help).accessibilityLabel(help)
        }
    }
}

struct MixerBandPicker: View {
    @Binding var selection: Int
    private let names = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
    private let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { index in
                Button { selection = index } label: {
                    Circle().fill(colors[index]).frame(width: 22, height: 22)
                        .padding(3)
                        .overlay(Circle().stroke(selection == index ? Color.white : .clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain).help(names[index]).accessibilityLabel(names[index])
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}

struct MixerHueGuide: View {
    let band: Int
    private let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    var body: some View {
        LinearGradient(colors: [colors[(band + 7) % 8], colors[band], colors[(band + 1) % 8]], startPoint: .leading, endPoint: .trailing)
            .frame(height: 4).clipShape(Capsule()).padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { AVPlayerView() }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player; view.controlsStyle = .none }
}

struct WheelZoomView: NSViewRepresentable {
    let onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) { view.onScroll = onScroll }

    final class WheelView: NSView {
        var onScroll: ((CGFloat, CGPoint) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onScroll?(event.scrollingDeltaY, CGPoint(x: point.x, y: bounds.height - point.y))
        }
    }
}

struct MediaThumbnail: View {
    let path: String
    let kind: MediaKind
    @State private var image: NSImage?
    @MainActor private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: kind == .video ? "film" : "photo").resizable().scaledToFit().padding(12) }
        }
        .frame(width: 108, height: 68).clipped().background(.black.opacity(0.25))
        .task(id: path) {
            if let cached = Self.cache.object(forKey: path as NSString) { image = cached; return }
            let url = URL(fileURLWithPath: path)
            let cg = await Task.detached(priority: .utility) { await MediaIO.thumbnailCGImage(url: url, kind: kind) }.value
            if let cg {
                let loaded = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                Self.cache.setObject(loaded, forKey: path as NSString)
                image = loaded
            }
        }
    }
}
