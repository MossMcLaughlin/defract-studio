import SwiftUI
import EditorCore

struct GradientOverlay: View {
    @ObservedObject var model: EditorModel
    @State private var dragging = false

    var body: some View {
        GeometryReader { view in
            if let recipe = model.draft, let mask = model.selectedMask,
               model.sourceSize.width > 0, model.sourceSize.height > 0,
               mask.kind == .linear || mask.kind == .radial {
                let inputSize = recipe.geometry.outputSize(for: model.sourceSize)
                let displaySize = recipe.outputFrame.map { CGSize(width: $0.width, height: $0.height) } ?? inputSize
                let scale = min(view.size.width / displaySize.width, view.size.height / displaySize.height)
                let origin = CGPoint(x: (view.size.width - displaySize.width * scale) / 2,
                                     y: (view.size.height - displaySize.height * scale) / 2)
                ZStack(alignment: .topLeading) {
                    if mask.kind == .linear {
                        let start = project(mask.start, recipe: recipe, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize)
                        let end = project(mask.end, recipe: recipe, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize)
                        Path { path in path.move(to: start); path.addLine(to: end) }
                            .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        handle(at: start, role: .start, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize, recipe: recipe)
                        handle(at: end, role: .end, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize, recipe: recipe)
                    } else {
                        let center = project(mask.center, recipe: recipe, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize)
                        let xPoint = project(NormalizedPoint(mask.center.x + mask.radiusX, mask.center.y), recipe: recipe, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize)
                        let yPoint = project(NormalizedPoint(mask.center.x, mask.center.y + mask.radiusY), recipe: recipe, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize)
                        Path { path in
                            path.move(to: center); path.addLine(to: xPoint)
                            path.move(to: center); path.addLine(to: yPoint)
                        }.stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        handle(at: center, role: .center, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize, recipe: recipe)
                        handle(at: xPoint, role: .radiusX, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize, recipe: recipe)
                        handle(at: yPoint, role: .radiusY, origin: origin, scale: scale, inputSize: inputSize, displaySize: displaySize, recipe: recipe)
                    }
                }
            }
        }
        .coordinateSpace(name: "gradientOverlay")
        .accessibilityLabel("Gradient handles. Drag to change mask position and direction.")
    }

    private enum Role { case start, end, center, radiusX, radiusY }

    private func project(_ point: NormalizedPoint, recipe: EditRecipe, origin: CGPoint, scale: CGFloat, inputSize: CGSize, displaySize: CGSize) -> CGPoint {
        var output = recipe.geometry.outputPoint(fromSourceNormalized: point, sourceSize: model.sourceSize)
        if let frame = recipe.outputFrame { output = frame.outputPoint(fromInputNormalized: output, inputSize: inputSize) }
        return CGPoint(x: origin.x + output.x * displaySize.width * scale,
                       y: origin.y + output.y * displaySize.height * scale)
    }

    private func handle(at position: CGPoint, role: Role, origin: CGPoint, scale: CGFloat, inputSize: CGSize, displaySize: CGSize, recipe: EditRecipe) -> some View {
        Circle().fill(Color.white).overlay(Circle().stroke(Color.blue, lineWidth: 2))
            .frame(width: 14, height: 14)
            .position(position)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("gradientOverlay"))
                .onChanged { value in
                    if !dragging { model.beginGesture(); dragging = true }
                    let u = (value.location.x - origin.x) / max(1, displaySize.width * scale)
                    let v = (value.location.y - origin.y) / max(1, displaySize.height * scale)
                    let output = recipe.outputFrame?.inputPoint(fromOutputNormalized: NormalizedPoint(u, v), inputSize: inputSize) ?? NormalizedPoint(u, v)
                    let source = recipe.geometry.sourcePoint(fromOutputNormalized: output, sourceSize: model.sourceSize)
                    model.updateMask { mask in
                        switch role {
                        case .start: mask.start = source
                        case .end: mask.end = source
                        case .center: mask.center = source
                        case .radiusX: mask.radiusX = min(1, max(0.02, abs(source.x - mask.center.x)))
                        case .radiusY: mask.radiusY = min(1, max(0.02, abs(source.y - mask.center.y)))
                        }
                    }
                }
                .onEnded { _ in if dragging { model.endGesture(); dragging = false } })
    }
}
