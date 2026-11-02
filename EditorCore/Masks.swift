import Foundation
import CoreImage

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public enum MaskKind: String, Codable, Sendable { case brush, subject, linear, radial }
public enum BrushOperation: String, Codable, Sendable { case add, erase }

public struct BrushStroke: Codable, Equatable, Sendable {
    public var operation: BrushOperation
    public var points: [NormalizedPoint]
    public var size: Double
    public var feather: Double

    public init(operation: BrushOperation, points: [NormalizedPoint], size: Double, feather: Double) {
        self.operation = operation
        self.points = points
        self.size = size
        self.feather = feather
    }
}

public struct EditMask: Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: MaskKind
    public var enabled = true
    public var inverted = false
    public var center = NormalizedPoint(0.5, 0.5)
    public var radiusX = 0.3
    public var radiusY = 0.3
    public var start = NormalizedPoint(0.5, 0.2)
    public var end = NormalizedPoint(0.5, 0.8)
    public var feather = 0.3
    public var strokes: [BrushStroke] = []
    public var mattePNG: Data?
    public var adjustment = AdjustmentVector()

    public init(name: String, kind: MaskKind) { self.name = name; self.kind = kind }
}

public enum MaskMath {
    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func smooth(_ x: Double) -> Double { let t = clamp(x); return t * t * (3 - 2 * t) }

    public static func alpha(at point: NormalizedPoint, mask: EditMask) -> Double {
        var value = 0.0
        switch mask.kind {
        case .linear:
            let dx = mask.end.x - mask.start.x
            let dy = mask.end.y - mask.start.y
            let length = max(0.00001, dx * dx + dy * dy)
            let projection = ((point.x - mask.start.x) * dx + (point.y - mask.start.y) * dy) / length
            value = smooth((projection - 0.5) / max(0.01, mask.feather) + 0.5)
        case .radial:
            let dx = (point.x - mask.center.x) / max(0.0001, mask.radiusX)
            let dy = (point.y - mask.center.y) / max(0.0001, mask.radiusY)
            let distance = sqrt(dx * dx + dy * dy)
            value = 1 - smooth((distance - (1 - mask.feather)) / max(0.01, mask.feather))
        case .brush, .subject:
            value = 0
        }
        for stroke in mask.strokes {
            let radius = max(0.0001, stroke.size / 2)
            var strokeAlpha = 0.0
            for sample in stroke.points {
                let distance = hypot(point.x - sample.x, point.y - sample.y)
                let weight = 1 - smooth((distance - radius * (1 - stroke.feather)) / max(0.0001, radius * stroke.feather))
                strokeAlpha = max(strokeAlpha, weight)
            }
            if stroke.operation == .add { value = max(value, strokeAlpha) }
            else { value *= 1 - strokeAlpha }
        }
        return mask.inverted ? 1 - value : value
    }
}

public enum MaskRenderer {
    private static func solid(_ value: CGFloat, extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1)).cropped(to: extent)
    }

    public static func alphaImage(for mask: EditMask, extent: CGRect) -> CIImage {
        var alpha: CIImage
        switch mask.kind {
        case .linear:
            let dx = (mask.end.x - mask.start.x) * extent.width
            let dy = (mask.end.y - mask.start.y) * extent.height
            let midX = extent.minX + (mask.start.x + mask.end.x) * extent.width / 2
            let midY = extent.minY + (mask.start.y + mask.end.y) * extent.height / 2
            let scale = max(mask.feather, 0.01) / 2
            alpha = CIImage.empty().applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: midX - dx * scale, y: midY - dy * scale),
                "inputPoint1": CIVector(x: midX + dx * scale, y: midY + dy * scale),
                "inputColor0": CIColor.black,
                "inputColor1": CIColor.white
            ]).cropped(to: extent)
        case .radial:
            let radius = min(extent.width, extent.height)
            let center = CIVector(x: extent.minX + mask.center.x * extent.width, y: extent.minY + mask.center.y * extent.height)
            let circle = CIImage.empty().applyingFilter("CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": radius * (1 - mask.feather),
                "inputRadius1": radius,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ])
            let transform = CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: mask.radiusX * extent.width / radius, y: mask.radiusY * extent.height / radius))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            alpha = circle.transformed(by: transform).cropped(to: extent)
        case .subject:
            if let data = mask.mattePNG, let matte = CIImage(data: data), matte.extent.width > 0, matte.extent.height > 0 {
                alpha = matte.transformed(by: CGAffineTransform(scaleX: extent.width / matte.extent.width, y: extent.height / matte.extent.height))
                    .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
            } else { alpha = solid(0, extent: extent) }
        case .brush:
            alpha = solid(0, extent: extent)
        }
        for stroke in mask.strokes {
            let radius = max(1, stroke.size * min(extent.width, extent.height) / 2)
            for point in stroke.points {
                let center = CIVector(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
                let brush = CIImage.empty().applyingFilter("CIRadialGradient", parameters: [
                    "inputCenter": center,
                    "inputRadius0": radius * (1 - stroke.feather),
                    "inputRadius1": radius,
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.black
                ]).cropped(to: extent)
                alpha = stroke.operation == .add
                    ? brush.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: alpha])
                    : brush.applyingFilter("CIColorInvert").applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: alpha])
            }
        }
        return mask.inverted ? alpha.applyingFilter("CIColorInvert") : alpha
    }
}

public extension CoreRenderer {
    static func render(_ source: CIImage, color: ColorState, masks: [EditMask]) -> CIImage {
        var current = render(source, adjustment: color.effective)
        for mask in masks where mask.enabled && !mask.adjustment.isNeutral {
            let local = render(current, adjustment: mask.adjustment)
            let alpha = MaskRenderer.alphaImage(for: mask, extent: source.extent)
            current = local.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: current,
                "inputMaskImage": alpha
            ])
        }
        return current
    }
}
