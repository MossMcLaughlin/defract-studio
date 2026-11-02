import SwiftUI
import EditorCore

struct MaskInspector: View {
    @ObservedObject var model: EditorModel
    @State private var selectedBand = 0
    private let bands = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Masks").font(.title3.bold())
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
                            .foregroundStyle(model.selectedMaskID == mask.id ? Color.blue : Color.primary)
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { mask.enabled }, set: { enabled in
                            model.change { recipe in
                                if let index = recipe.masks.firstIndex(where: { $0.id == mask.id }) { recipe.masks[index].enabled = enabled }
                            }
                        })).labelsHidden()
                    }
                    .padding(6)
                    .background(model.selectedMaskID == mask.id ? Color.blue.opacity(0.12) : .clear)
                }
                if let mask = model.selectedMask {
                    Divider()
                    TextField("Mask name", text: Binding(get: { model.selectedMask?.name ?? "" }, set: { value in
                        model.updateMask { $0.name = value }
                    }))
                    Toggle("Invert selection", isOn: Binding(get: { model.selectedMask?.inverted ?? false }, set: { value in
                        model.updateMask { $0.inverted = value }
                    }))
                    Toggle("Show mask overlay", isOn: Binding(get: { model.overlayVisible }, set: { value in
                        model.overlayVisible = value
                        model.refresh()
                    }))
                    if mask.kind == .brush || mask.kind == .subject { brushControls }
                    if mask.kind == .radial { radialControls }
                    if mask.kind == .linear { linearControls }
                    Button("Delete Mask", role: .destructive) { model.deleteSelectedMask() }
                    Divider()
                    Text("Local Light").font(.headline)
                    ForEach([Parameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks], id: \.self) { localSlider($0) }
                    Divider()
                    Text("Local Color").font(.headline)
                    ForEach([Parameter.temperature, .tint, .saturation, .vibrance], id: \.self) { localSlider($0) }
                    Divider()
                    Text("Local Color Mixer").font(.headline)
                    Picker("Band", selection: $selectedBand) {
                        ForEach(0..<bands.count, id: \.self) { index in Text(bands[index]).tag(index) }
                    }
                    let parameters = Array(Parameter.allCases.dropFirst(10))
                    ForEach(parameters[(selectedBand * 3)..<(selectedBand * 3 + 3)], id: \.self) { localSlider($0) }
                } else {
                    Text("Add a mask to adjust part of the image.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 6)
        }
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Brush correction").font(.headline)
            Picker("Mode", selection: $model.brushOperation) {
                Text("Add").tag(BrushOperation.add)
                Text("Erase").tag(BrushOperation.erase)
            }.pickerStyle(.segmented)
            Text("Size \(Int(model.brushSize * 100))%")
            Slider(value: $model.brushSize, in: 0.01...0.3)
            Text("Feather \(Int(model.brushFeather * 100))%")
            Slider(value: $model.brushFeather, in: 0...1)
            Text("Paint directly on the photo. Each stroke can be undone.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var radialControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Radial Gradient").font(.headline)
            geometrySlider("Center X", \.center.x)
            geometrySlider("Center Y", \.center.y)
            geometrySlider("Width", \.radiusX)
            geometrySlider("Height", \.radiusY)
            geometrySlider("Feather", \.feather)
        }
    }

    private var linearControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Linear Gradient").font(.headline)
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
                .accessibilityLabel(title)
        }
    }

    private func localSlider(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(parameter.title)
                Spacer()
                Text(parameter == .exposure ? String(format: "%.2f", model.selectedMask?.adjustment[parameter] ?? 0) : String(format: "%.0f", model.selectedMask?.adjustment[parameter] ?? 0))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { model.selectedMask?.adjustment[parameter] ?? 0 }, set: { value in
                model.updateMask { $0.adjustment[parameter] = value }
            }), in: parameter.limits, onEditingChanged: { editing in editing ? model.beginGesture() : model.endGesture() })
                .accessibilityLabel("Local \(parameter.title)")
        }
    }
}
