import SwiftUI
import EditorCore

struct CropOverlay: View {
    @ObservedObject var model: EditorModel
    @State private var startGeometry: Geometry?
    private let handles: [(CGFloat, CGFloat)] = [
        (0, 0), (0.5, 0), (1, 0), (1, 0.5),
        (1, 1), (0.5, 1), (0, 1), (0, 0.5)
    ]

    var body: some View {
        GeometryReader { view in
            if let recipe = model.draft, model.sourceSize.width > 0, model.sourceSize.height > 0 {
                let sourceBounds = CGRect(origin: .zero, size: model.sourceSize)
                let crop = recipe.geometry.cropRect(in: sourceBounds)
                let scale = min(view.size.width / sourceBounds.width, view.size.height / sourceBounds.height)
                let origin = CGPoint(x: (view.size.width - sourceBounds.width * scale) / 2,
                                     y: (view.size.height - sourceBounds.height * scale) / 2)
                let frame = CGRect(x: origin.x + crop.minX * scale,
                                   y: origin.y + (sourceBounds.height - crop.maxY) * scale,
                                   width: crop.width * scale, height: crop.height * scale)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: view.size))
                        path.addRect(frame)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    Rectangle().stroke(Color(red: 0.82, green: 0.63, blue: 0.22), lineWidth: 2)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle())
                        .frame(width: max(1, frame.width - 24), height: max(1, frame.height - 24))
                        .position(x: frame.midX, y: frame.midY)
                        .gesture(moveGesture(scale: scale, sourceSize: sourceBounds.size))
                    ForEach(0..<handles.count, id: \.self) { index in
                        let handle = handles[index]
                        Circle().fill(Color(red: 0.82, green: 0.63, blue: 0.22))
                            .frame(width: 12, height: 12)
                            .position(x: frame.minX + frame.width * handle.0,
                                      y: frame.minY + frame.height * handle.1)
                            .gesture(resizeGesture(handle: handle, scale: scale, sourceSize: sourceBounds.size))
                    }
                }
            }
        }
        .accessibilityLabel("Crop frame. Drag inside to move or drag handles to resize.")
    }

    private func beginIfNeeded() {
        if startGeometry == nil {
            startGeometry = model.draft?.geometry
            model.beginGesture()
        }
    }

    private func finish() {
        if startGeometry != nil { model.endGesture() }
        startGeometry = nil
    }

    private func moveGesture(scale: CGFloat, sourceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                beginIfNeeded()
                guard let startGeometry else { return }
                let crop = startGeometry.cropRect(in: CGRect(origin: .zero, size: sourceSize))
                let marginX = max(1, sourceSize.width - crop.width)
                let marginY = max(1, sourceSize.height - crop.height)
                model.change { geometryRecipe in
                    geometryRecipe.geometry.centerX = min(1, max(0, startGeometry.centerX + value.translation.width / scale / marginX))
                    geometryRecipe.geometry.centerY = min(1, max(0, startGeometry.centerY - value.translation.height / scale / marginY))
                }
            }
            .onEnded { _ in finish() }
    }

    private func resizeGesture(handle: (CGFloat, CGFloat), scale: CGFloat, sourceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                beginIfNeeded()
                guard let startGeometry else { return }
                let signX: CGFloat = handle.0 < 0.5 ? -1 : handle.0 > 0.5 ? 1 : 0
                let signY: CGFloat = handle.1 < 0.5 ? -1 : handle.1 > 0.5 ? 1 : 0
                let dx = signX * value.translation.width / scale / sourceSize.width * 2
                let dy = signY * value.translation.height / scale / sourceSize.height * 2
                model.change { recipe in
                    if startGeometry.aspect == .original { recipe.geometry.aspect = .free }
                    if recipe.geometry.aspect == .free {
                        recipe.geometry.freeWidth = min(1, max(0.1, startGeometry.freeWidth + dx))
                        recipe.geometry.freeHeight = min(1, max(0.1, startGeometry.freeHeight + dy))
                    } else {
                        recipe.geometry.cropScale = min(1, max(0.1, startGeometry.cropScale + dx + dy))
                    }
                }
            }
            .onEnded { _ in finish() }
    }
}
