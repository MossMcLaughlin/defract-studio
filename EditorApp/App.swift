import SwiftUI
import AppKit
import AVKit
import CoreImage
import EditorCore

@main
struct EditorApp: App {
    @NSApplicationDelegateAdaptor(EditorApplicationDelegate.self) private var applicationDelegate
    var body: some Scene {
        WindowGroup("Defract Studio") {
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
    @State private var showingEasyHelp = false

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
        .background(EditorTheme.canvas)
        .alert("Editor notice", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            if model.draft != nil { Button("Relink…") { model.error = nil; model.relink() } }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Reset all global adjustments?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) { model.change {
                $0.color = ColorState(mappingVersion: $0.color.underwaterMappingVersion)
                if ($0.rendererVersion ?? 1) >= 4 { $0.detail = TechnicalDetail() }
            } }
        }
        .onAppear { model.maskPanelActive = inspectorTab == "Masks"; model.refresh() }
        .sheet(isPresented: $model.exportSheetRequested) { ExportSheet(model: model) }
        .background(WindowCloseObserver(model: model).frame(width: 0, height: 0))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !sidebarVisible {
                Button { sidebarVisible = true } label: {
                    Label("Show Files", systemImage: "sidebar.left")
                        .labelStyle(.iconOnly).modifier(ToolbarButtonSurface())
                }
                    .help("Show Files").accessibilityLabel("Show Files")
            }
            Button(action: model.undo) { Label("Undo", systemImage: "arrow.uturn.backward").modifier(ToolbarButtonSurface()) }
                .disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo")
            Button(action: model.redo) { Label("Redo", systemImage: "arrow.uturn.forward").modifier(ToolbarButtonSurface()) }
                .disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
            Rectangle().fill(EditorTheme.divider).frame(width: 1, height: 20).padding(.horizontal, 5)
            Button { model.showingOriginal.toggle(); model.refresh() } label: {
                Label(model.showingOriginal ? "Show Edited" : "Before/After", systemImage: "rectangle.split.2x1")
                    .modifier(ToolbarButtonSurface())
            }
                .disabled(model.draft == nil).help("Toggle original and edited preview")
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button { model.exportSheetRequested = true } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
                    .foregroundStyle(EditorTheme.primaryText)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(EditorTheme.divider))
            }
                .disabled(model.draft == nil || model.busy || model.sourceSize == .zero)
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.plain).help("Export selected file")
        }
        .buttonStyle(.plain)
        .font(EditorTheme.control)
        .foregroundStyle(EditorTheme.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EditorTheme.toolbar)
        .overlay {
            if let recipe = model.draft {
                GeometryReader { geometry in
                    Text(URL(fileURLWithPath: recipe.sourcePath).lastPathComponent)
                        .font(EditorTheme.control)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: max(0, min(240, geometry.size.width - 2 * (sidebarVisible ? 325 : 390))))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
        }
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
                        .background(model.selectedID == recipe.id ? EditorTheme.pacific.opacity(0.45) : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(URL(fileURLWithPath: recipe.sourcePath).lastPathComponent)")
                }
            }.padding(6)
            }
        }
        .frame(width: 128)
        .background(EditorTheme.panel)
    }

    private var preview: some View {
        VStack(spacing: 4) {
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
            if model.kind == .video {
                videoControls
                HStack { cropButton; Spacer(); mediaDimensions }
            }
            else if model.kind == .photo {
                HStack {
                    cropButton
                    Button("Fit") { resetZoom() }
                    Slider(value: $zoom, in: 1...4).frame(width: 120)
                    Text(zoom == 1 ? "Fit" : String(format: "%.1f× Fit", zoom))
                    Spacer(minLength: 6)
                    mediaDimensions
                }.font(EditorTheme.control).tint(EditorTheme.gold)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(EditorTheme.canvas)
    }

    private var cropButton: some View {
        Button { resetZoom(); model.toggleCropEditing() } label: {
            Image(systemName: "crop.rotate")
                .frame(width: 28, height: 26)
                .foregroundStyle(model.cropEditing ? EditorTheme.primaryText : EditorTheme.secondaryText)
                .background(model.cropEditing ? EditorTheme.pacific : EditorTheme.raised, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(model.draft == nil)
        .help("Crop & Rotate")
        .accessibilityLabel("Crop & Rotate")
    }

    private var mediaDimensions: some View {
        Group {
            if model.sourceSize.width > 0, model.sourceSize.height > 0 {
                Text("\(Int(model.sourceSize.width.rounded())) × \(Int(model.sourceSize.height.rounded()))")
                    .font(EditorTheme.helper.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .help("Display-oriented source dimensions in pixels")
            }
        }
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
        .tint(EditorTheme.gold)
        .font(EditorTheme.control)
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            if let seconds = model.player?.currentTime().seconds, seconds.isFinite { model.seconds = seconds }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorTabs(selection: $inspectorTab, names: ["Global", "Masks"], symbols: ["slider.horizontal.3", "circle.dotted.circle"], primary: true)
            .onChange(of: inspectorTab) { _, mode in model.maskPanelActive = mode == "Masks"; model.refresh() }
            if model.draft == nil { Text("Import a file to begin.").foregroundStyle(EditorTheme.secondaryText) }
            else if inspectorTab == "Masks" { MaskInspector(model: model) }
            else {
                EditorTabs(selection: $inspectorMode, names: ["Easy", "Advanced"], primary: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if inspectorMode == "Easy" { easyInspector }
                        else { advancedInspector }
                        if model.kind != nil { cropInspector }
                        if inspectorMode == "Advanced" {
                            Divider().overlay(EditorTheme.divider)
                            resetTextButton("Reset All Global Adjustments…") { confirmReset = true }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.trailing, 28)
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 14)
        .background(EditorTheme.panel)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "water.waves").foregroundStyle(EditorTheme.pacific)
                Text("Underwater Easy").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { showingEasyHelp.toggle() } label: {
                    Image(systemName: "info.circle").foregroundStyle(EditorTheme.secondaryText)
                }
                    .buttonStyle(.plain)
                    .help("Easy gives you quick underwater corrections using a few sliders, while Advanced shows the precise color controls behind the result. You can fine-tune in Advanced, and those refinements remain when you return to Easy.")
                    .accessibilityLabel("Underwater Easy information")
                    .popover(isPresented: $showingEasyHelp) {
                        Text("Easy gives you quick underwater corrections using a few sliders, while Advanced shows the precise color controls behind the result. You can fine-tune in Advanced, and those refinements remain when you return to Easy.")
                            .font(EditorTheme.helper).padding(14).frame(width: 290)
                    }
            }
            Text("Quick, natural adjustments for underwater photos. Restore color, balance light, and improve clarity in a few steps.")
                .font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            easySlider("Water Color", \.waterColor, range: -100...100,
                       description: "Adjust the blue/green cast in the water.")
            easySlider("Color Recovery", \.colorRecovery, range: 0...100,
                       description: "Restore natural colors in the subject and reef.")
            easySlider("Light", \.light, range: -100...100,
                       description: "Brighten and balance the overall exposure.")
            easySlider("Visibility", \.visibility, range: 0...100,
                       description: "Improve clarity and distance by reducing haze.")
            if model.draft?.color.manualDelta.isNeutral == false {
                Text(shownManualHelp ? "Customized in Advanced" : "Manual refinements are preserved when you change Easy controls. Start with Easy and finish with Advanced.")
                    .font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
                    .onAppear { shownManualHelp = true }
            }
            Divider().overlay(EditorTheme.divider)
            resetTextButton("Reset Underwater Easy") { model.change { $0.color.resetEasy() } }
        }
    }

    private var cropInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(EditorTheme.divider)
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
                    .modifier(GoldSliderTrack(value: model.draft?.geometry.freeWidth ?? 1, range: 0.1...1))
                Text("Crop height")
                Slider(value: Binding(get: { model.draft?.geometry.freeHeight ?? 1 }, set: { value in
                    model.change { $0.geometry.freeHeight = value }
                }), in: 0.1...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                    .modifier(GoldSliderTrack(value: model.draft?.geometry.freeHeight ?? 1, range: 0.1...1))
            } else if model.draft?.geometry.aspect != .original {
                Text("Crop size")
                Slider(value: Binding(get: { model.draft?.geometry.cropScale ?? 1 }, set: { value in
                    model.change { $0.geometry.cropScale = value }
                }), in: 0.1...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                    .modifier(GoldSliderTrack(value: model.draft?.geometry.cropScale ?? 1, range: 0.1...1))
            }
            if model.draft?.geometry.aspect != .original {
                Text("Horizontal position")
                Slider(value: Binding(get: { model.draft?.geometry.centerX ?? 0.5 }, set: { value in
                    model.change { $0.geometry.centerX = value }
                }), in: 0...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                    .modifier(GoldSliderTrack(value: model.draft?.geometry.centerX ?? 0.5, range: 0...1))
                Text("Vertical position")
                Slider(value: Binding(get: { model.draft?.geometry.centerY ?? 0.5 }, set: { value in
                    model.change { $0.geometry.centerY = value }
                }), in: 0...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                    .modifier(GoldSliderTrack(value: model.draft?.geometry.centerY ?? 0.5, range: 0...1))
            }
            HStack {
                Button("Rotate Left") { model.change { $0.geometry.rotateQuarterTurns -= 1 } }
                Button("Rotate Right") { model.change { $0.geometry.rotateQuarterTurns += 1 } }
            }
            Text("Straighten \(model.draft?.geometry.straightenDegrees ?? 0, specifier: "%.1f")°")
            Slider(value: Binding(get: { model.draft?.geometry.straightenDegrees ?? 0 }, set: { value in
                model.change { $0.geometry.straightenDegrees = value }
            }), in: -20...20, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .modifier(GoldSliderTrack(value: model.draft?.geometry.straightenDegrees ?? 0, range: -20...20))
        }
        .font(EditorTheme.control)
        .foregroundStyle(EditorTheme.primaryText)
        .tint(EditorTheme.gold)
    }

    private func easySlider(_ title: String, _ key: WritableKeyPath<EasySettings, Double>, range: ClosedRange<Double>,
                            description: String, endpoints: (String, String)? = nil) -> some View {
        InspectorSliderRow(title: title, value: String(format: "%+.0f", model.draft?.color.easy[keyPath: key] ?? 0),
                           selection: Binding(get: { model.draft?.color.easy[keyPath: key] ?? 0 }, set: { value in
                model.change { $0.color.setEasy { $0[keyPath: key] = value.rounded() } }
            }), range: range, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() },
                           description: description, endpoints: endpoints)
    }

    private var advancedInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Light", help: "Reset manual Light adjustments") { model.change { $0.color.resetManual([.exposure, .contrast, .highlights, .shadows, .whites, .blacks]) } }
            ForEach([Parameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks], id: \.self) { parameter in advancedSlider(parameter) }
            Divider().overlay(EditorTheme.divider)
            sectionHeader("Color", help: "Reset manual Color adjustments") { model.change { $0.color.resetManual([.temperature, .tint, .saturation, .vibrance]) } }
            ForEach([Parameter.temperature, .tint, .saturation, .vibrance], id: \.self) { parameter in advancedSlider(parameter) }
            Divider().overlay(EditorTheme.divider)
            sectionHeader("Color Mixer", help: "Reset all manual Color Mixer adjustments") { model.change { $0.color.resetManual(Array(Parameter.allCases.dropFirst(10).prefix(24))) } }
            MixerBandPicker(selection: $selectedBand)
            let parameters = Array(Parameter.allCases.dropFirst(10).prefix(24))
            ForEach(parameters[(selectedBand * 3)..<(selectedBand * 3 + 3)], id: \.self) { parameter in advancedSlider(parameter, mixer: true) }
            if (model.draft?.rendererVersion ?? 1) >= 5 {
                Divider().overlay(EditorTheme.divider)
                sectionHeader("Visibility", help: "Reset manual Visibility adjustments") {
                    model.change { $0.color.resetManual([.clarity, .dehaze]) }
                }
                advancedSlider(.clarity)
                advancedSlider(.dehaze)
            }
            if (model.draft?.rendererVersion ?? 1) >= 4 {
                Divider().overlay(EditorTheme.divider)
                sectionHeader("Detail", help: "Reset Detail controls") { model.change { $0.detail = TechnicalDetail() } }
                Toggle("Auto protection", isOn: Binding(
                    get: { model.draft?.detail.autoProtection ?? true },
                    set: { value in model.change { var detail = $0.detail; detail.autoProtection = value; $0.detail = detail } }
                ))
                .toggleStyle(.switch).help("Apply measured noise protection when the grade would reveal source noise.")
                detailSlider("Color Noise", \.colorNoise)
                detailSlider("Luminance Noise", \.luminanceNoise)
                if model.draft?.noiseAnalysis == nil {
                    Text("Auto protection is waiting for source analysis. Manual Detail controls work now.")
                        .font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailSlider(_ title: String, _ key: WritableKeyPath<TechnicalDetail, Double>) -> some View {
        InspectorSliderRow(title: title, value: String(format: "%.0f", model.draft?.detail[keyPath: key] ?? 0),
                           selection: Binding(get: { model.draft?.detail[keyPath: key] ?? 0 }, set: { value in
                model.change { var detail = $0.detail; detail[keyPath: key] = value.rounded(); $0.detail = detail }
            }), range: 0...100, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
    }

    private func advancedSlider(_ parameter: Parameter, mixer: Bool = false) -> some View {
        InspectorSliderRow(title: mixer ? String(parameter.title.split(separator: " ").last ?? "") : parameter.title,
                           value: parameter == .exposure ? String(format: "%+.2f", model.draft?.color.effective[parameter] ?? 0) : String(format: "%+.0f", model.draft?.color.effective[parameter] ?? 0),
                           selection: Binding(get: { model.draft?.color.effective[parameter] ?? 0 }, set: { value in
                model.change { $0.color.setEffective(parameter, to: value) }
            }), range: parameter.limits, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() },
                           accessibilityLabel: parameter.title,
                           onLabelDoubleClick: { model.change { $0.color.setEffective(parameter, to: $0.color.base[parameter]) } },
                           hueBand: mixer && parameter.rawValue.hasSuffix("Hue") ? selectedBand : nil)
    }

    private func sectionHeader(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(EditorTheme.heading).foregroundStyle(EditorTheme.primaryText)
            Spacer()
            Button(action: action) { Image(systemName: "arrow.counterclockwise").font(.caption) }
                .buttonStyle(.plain).foregroundStyle(EditorTheme.gold)
                .frame(width: 28, height: 28).help(help).accessibilityLabel(help)
        }
    }

    private func resetTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: "arrow.counterclockwise")
            .font(EditorTheme.control).frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.plain).foregroundStyle(EditorTheme.gold).padding(.vertical, 4)
            .help(title)
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

enum EditorTheme {
    static let canvas = Color(red: 11 / 255, green: 11 / 255, blue: 10 / 255)
    static let toolbar = Color(red: 0.106, green: 0.11, blue: 0.11)
    static let panel = Color(red: 0.063, green: 0.067, blue: 0.067)
    static let raised = Color(red: 0.18, green: 0.19, blue: 0.19)
    static let primaryText = Color(red: 246 / 255, green: 242 / 255, blue: 233 / 255)
    static let secondaryText = Color(red: 174 / 255, green: 179 / 255, blue: 174 / 255)
    static let gold = Color(red: 199 / 255, green: 166 / 255, blue: 106 / 255)
    static let pacific = Color(red: 45 / 255, green: 112 / 255, blue: 143 / 255)
    static let divider = Color.white.opacity(0.12)
    static let heading = Font.system(size: 17, weight: .semibold)
    static let control = Font.system(size: 13, weight: .medium)
    static let value = Font.system(size: 13, weight: .medium).monospacedDigit()
    static let helper = Font.system(size: 11, weight: .regular)
}

private struct ToolbarButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 8).padding(.vertical, 6)
            .background(EditorTheme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct EditorTabs: View {
    @Binding var selection: String
    let names: [String]
    var symbols: [String] = []
    var primary = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(names.indices, id: \.self) { index in
                let name = names[index]
                Button { selection = name } label: {
                    HStack(spacing: 7) {
                        if symbols.indices.contains(index) { Image(systemName: symbols[index]) }
                        Text(name)
                    }
                    .font(EditorTheme.control)
                    .foregroundStyle(selection == name && primary ? EditorTheme.gold : EditorTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: primary ? 42 : 32)
                    .background {
                        if !primary && selection == name { RoundedRectangle(cornerRadius: 7).fill(EditorTheme.pacific) }
                    }
                    .overlay(alignment: .bottom) {
                        if primary && selection == name { EditorTheme.gold.frame(height: 2) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(selection == name ? .isSelected : [])
            }
        }
        .padding(primary ? 0 : 3)
        .background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InspectorSliderRow: View {
    let title: String
    let value: String
    let selection: Binding<Double>
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    var accessibilityLabel: String? = nil
    var description: String? = nil
    var endpoints: (String, String)? = nil
    var onLabelDoubleClick: (() -> Void)? = nil
    var hueBand: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(EditorTheme.control)
                    .onTapGesture(count: 2) { onLabelDoubleClick?() }
                Spacer()
                Text(value).font(EditorTheme.value)
            }
            .foregroundStyle(EditorTheme.primaryText)
            Slider(value: selection, in: range, onEditingChanged: onEditingChanged)
                .modifier(GoldSliderTrack(value: selection.wrappedValue, range: range, hueBand: hueBand))
                .accessibilityLabel(accessibilityLabel ?? title)
            if let endpoints {
                HStack { Text(endpoints.0); Spacer(); Text(endpoints.1) }
                    .font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
            }
            if let description {
                Text(description).font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GoldSliderTrack: ViewModifier {
    let value: Double
    let range: ClosedRange<Double>
    var hueBand: Int? = nil

    func body(content: Content) -> some View {
        content.tint(EditorTheme.raised)
            .overlay {
                GeometryReader { geometry in
                    let fraction = CGFloat(min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))))
                    let trackWidth = max(0, geometry.size.width - 20)
                    let center = range.lowerBound < 0 && range.upperBound > 0
                        ? CGFloat(-range.lowerBound / (range.upperBound - range.lowerBound)) : 0
                    let start = hueBand == nil ? min(center, fraction) : 0
                    let end = hueBand == nil ? max(center, fraction) : 1
                    Capsule().fill(EditorTheme.gold)
                        .frame(width: trackWidth * (end - start), height: 4)
                        .position(x: 10 + trackWidth * (start + end) / 2, y: geometry.size.height / 2)
                        .opacity(hueBand == nil ? 1 : 0)
                    if let hueBand {
                        MixerHueGuide(band: hueBand)
                            .frame(width: trackWidth, height: 4)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

struct MixerHueGuide: View {
    let band: Int
    private let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    var body: some View {
        LinearGradient(colors: [colors[(band + 7) % 8], colors[band], colors[(band + 1) % 8]], startPoint: .leading, endPoint: .trailing)
            .clipShape(Capsule())
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
