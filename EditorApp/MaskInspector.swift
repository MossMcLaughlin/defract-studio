import SwiftUI
import EditorCore

struct MaskInspector: View {
    @ObservedObject var model: EditorModel
    @State private var selectedBand = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Masks").font(EditorTheme.heading)
                    Spacer()
                    Menu("Add Mask") {
                        if model.kind == .photo {
                            Button("Select Subject") { model.detectSubject() }
                            Button("Brush") { model.addMask(.brush) }
                        }
                        Button("Linear Gradient") { model.addMask(.linear) }
                        Button("Radial Gradient") { model.addMask(.radial) }
                    }
                }
                if model.detectingSubject {
                    HStack { ProgressView(); Text("Finding subject…"); Button("Stop") { model.cancelSubject() } }
                }
                ForEach(model.draft?.masks ?? [], id: \.id) { mask in
                    HStack {
                        Button(mask.name) { model.selectMask(mask.id) }
                            .buttonStyle(.plain)
                            .fontWeight(model.selectedMaskID == mask.id ? .bold : .regular)
                            .foregroundStyle(model.selectedMaskID == mask.id ? EditorTheme.gold : EditorTheme.primaryText)
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { mask.enabled }, set: { enabled in
                            model.change { recipe in
                                if let index = recipe.masks.firstIndex(where: { $0.id == mask.id }) { recipe.masks[index].enabled = enabled }
                            }
                        })).labelsHidden()
                    }
                    .padding(6)
                    .background(model.selectedMaskID == mask.id ? EditorTheme.pacific.opacity(0.25) : .clear)
                }
                if let mask = model.selectedMask {
                    Divider().overlay(EditorTheme.divider)
                    HStack {
                        TextField("Mask name", text: Binding(get: { model.selectedMask?.name ?? "" }, set: { value in
                            model.updateMask { $0.name = value }
                        }))
                        Button("Delete Mask", systemImage: "trash", role: .destructive) { model.deleteSelectedMask() }
                            .labelStyle(.iconOnly).help("Delete selected mask; Undo restores it")
                            .accessibilityLabel("Delete selected mask")
                    }
                    Toggle("Invert selection", isOn: Binding(get: { model.selectedMask?.inverted ?? false }, set: { value in
                        model.updateMask { $0.inverted = value }
                    }))
                    Button("Create Inverted Mask") { model.duplicateSelectedMaskAsInverse() }
                    Toggle("Show mask overlay", isOn: Binding(get: { model.overlayVisible }, set: { value in
                        model.overlayVisible = value
                        model.refresh()
                    }))
                    if mask.kind == .brush || mask.kind == .subject { brushControls }
                    if mask.kind == .radial { radialControls }
                    if mask.kind == .linear { linearControls }
                    Divider().overlay(EditorTheme.divider)
                    localHeader("Local Light", parameters: [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
                    ForEach([Parameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks], id: \.self) { localSlider($0) }
                    Divider().overlay(EditorTheme.divider)
                    localHeader("Local Color", parameters: [.temperature, .tint, .saturation, .vibrance])
                    ForEach([Parameter.temperature, .tint, .saturation, .vibrance], id: \.self) { localSlider($0) }
                    Divider().overlay(EditorTheme.divider)
                    localHeader("Local Color Mixer", parameters: Array(Parameter.allCases.dropFirst(10)))
                    MixerBandPicker(selection: $selectedBand)
                    let parameters = Array(Parameter.allCases.dropFirst(10))
                    ForEach(parameters[(selectedBand * 3)..<(selectedBand * 3 + 3)], id: \.self) { localSlider($0, mixer: true) }
                } else {
                    Text("Add a mask to adjust part of the image.").font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.trailing, 28)
        }
        .font(EditorTheme.control)
        .foregroundStyle(EditorTheme.primaryText)
        .tint(EditorTheme.gold)
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Brush correction").font(EditorTheme.heading)
            Picker("Mode", selection: $model.brushOperation) {
                Text("Add").tag(BrushOperation.add)
                Text("Erase").tag(BrushOperation.erase)
            }.pickerStyle(.segmented)
            Text("Size \(Int(model.brushSize * 100))%")
            Slider(value: $model.brushSize, in: 0.01...0.3)
                .modifier(GoldSliderTrack(value: model.brushSize, range: 0.01...0.3))
            Text("Feather \(Int(model.brushFeather * 100))%")
            Slider(value: $model.brushFeather, in: 0...1)
                .modifier(GoldSliderTrack(value: model.brushFeather, range: 0...1))
            Text("Paint directly on the photo. Each stroke can be undone.").font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
        }
    }

    private var radialControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Radial Gradient").font(EditorTheme.heading)
            geometrySlider("Center X", \.center.x)
            geometrySlider("Center Y", \.center.y)
            geometrySlider("Width", \.radiusX)
            geometrySlider("Height", \.radiusY)
            Text("Rotation \(Int(radialRotationValue.rounded()))°").font(.caption)
            Slider(value: Binding(get: { radialRotationValue }, set: { value in
                model.updateMask { $0.rotationDegrees = value }
            }), in: -90...90, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .modifier(GoldSliderTrack(value: radialRotationValue, range: -90...90))
                .accessibilityLabel("Radial rotation")
            geometrySlider("Feather", \.feather)
            Text("Softens the mask edge.").font(EditorTheme.helper).foregroundStyle(EditorTheme.secondaryText)
        }
    }

    private var radialRotationValue: Double {
        let angle = (model.selectedMask?.rotationDegrees ?? 0).truncatingRemainder(dividingBy: 180)
        return angle > 90 ? angle - 180 : angle < -90 ? angle + 180 : angle
    }

    private var linearControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Linear Gradient").font(EditorTheme.heading)
            geometrySlider("Start X", \.start.x)
            geometrySlider("Start Y", \.start.y)
            geometrySlider("End X", \.end.x)
            geometrySlider("End Y", \.end.y)
            geometrySlider("Feather", \.feather)
        }
    }

    private func geometrySlider(_ title: String, _ key: WritableKeyPath<EditMask, Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title) \(Int((model.selectedMask?[keyPath: key] ?? 0) * 100))").font(.caption)
            Slider(value: Binding(get: { model.selectedMask?[keyPath: key] ?? 0.5 }, set: { value in
                model.updateMask { $0[keyPath: key] = value }
            }), in: 0...1, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .modifier(GoldSliderTrack(value: model.selectedMask?[keyPath: key] ?? 0.5, range: 0...1))
                .accessibilityLabel(title)
        }
    }

    private func localSlider(_ parameter: Parameter, mixer: Bool = false) -> some View {
        InspectorSliderRow(title: mixer ? String(parameter.title.split(separator: " ").last ?? "") : parameter.title,
                           value: parameter == .exposure ? String(format: "%+.2f", model.selectedMask?.adjustment[parameter] ?? 0) : String(format: "%+.0f", model.selectedMask?.adjustment[parameter] ?? 0),
                           selection: Binding(get: { model.selectedMask?.adjustment[parameter] ?? 0 }, set: { value in
                model.updateMask { $0.adjustment[parameter] = value }
            }), range: parameter.limits, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() },
                           accessibilityLabel: "Local \(parameter.title)",
                           hueBand: mixer && parameter.rawValue.hasSuffix("Hue") ? selectedBand : nil)
    }

    private func localHeader(_ title: String, parameters: [Parameter]) -> some View {
        HStack {
            Text(title).font(EditorTheme.heading)
            Spacer()
            Button {
                model.updateMask { mask in for parameter in parameters { mask.adjustment[parameter] = 0 } }
            } label: { Image(systemName: "arrow.counterclockwise").font(.caption) }
                .buttonStyle(.plain).foregroundStyle(EditorTheme.gold)
                .frame(width: 28, height: 28).help("Reset \(title) adjustments")
                .accessibilityLabel("Reset \(title) adjustments")
        }
    }
}
