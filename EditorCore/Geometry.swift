import Foundation
import CoreImage

public enum CropAspect: String, CaseIterable, Codable, Sendable {
    case original = "Original"
    case free = "Free"
    case square = "1:1"
    case fourFive = "4:5"
    case nineSixteen = "9:16"
    case sixteenNine = "16:9"

    public var ratio: Double? {
        switch self {
        case .original, .free: nil
        case .square: 1
        case .fourFive: 4.0 / 5
        case .nineSixteen: 9.0 / 16
        case .sixteenNine: 16.0 / 9
        }
    }
}

public struct Geometry: Codable, Equatable, Sendable {
    public var aspect: CropAspect = .original
    public var centerX = 0.5
    public var centerY = 0.5
    public var cropScale = 1.0
    public var freeWidth = 1.0
    public var freeHeight = 1.0
    public var rotateQuarterTurns = 0
    public var straightenDegrees = 0.0

    public init() {}

    public func cropRect(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        if aspect == .original { return bounds }
        if aspect == .free {
            let width = bounds.width * min(1, max(0.1, freeWidth))
            let height = bounds.height * min(1, max(0.1, freeHeight))
            return CGRect(x: bounds.minX + min(max(centerX, 0), 1) * (bounds.width - width),
                          y: bounds.minY + min(max(centerY, 0), 1) * (bounds.height - height),
                          width: width, height: height)
        }
        guard let ratio = aspect.ratio else { return bounds }
        let current = bounds.width / bounds.height
        let scale = min(1, max(0.1, cropScale))
        let width = (current > ratio ? bounds.height * ratio : bounds.width) * scale
        let height = (current > ratio ? bounds.height : bounds.width / ratio) * scale
        let x = bounds.minX + min(max(centerX, 0), 1) * (bounds.width - width)
        let y = bounds.minY + min(max(centerY, 0), 1) * (bounds.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func safeStraightenScale(for size: CGSize) -> CGFloat {
        let angle = abs(straightenDegrees) * .pi / 180
        guard angle > 0.000001 else { return 1 }
        let width = size.width * cos(angle) - size.height * sin(angle)
        let height = size.height * cos(angle) - size.width * sin(angle)
        return max(0.05, min(width / size.width, height / size.height))
    }

    public func outputSize(for sourceSize: CGSize) -> CGSize {
        let crop = cropRect(in: CGRect(origin: .zero, size: sourceSize))
        let scale = safeStraightenScale(for: crop.size)
        let width = crop.width * scale
        let height = crop.height * scale
        return abs(rotateQuarterTurns % 2) == 1 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    public func sourcePoint(fromOutputNormalized output: NormalizedPoint, sourceSize: CGSize) -> NormalizedPoint {
        let crop = cropRect(in: CGRect(origin: .zero, size: sourceSize))
        let scale = safeStraightenScale(for: crop.size)
        let safeWidth = crop.width * scale
        let safeHeight = crop.height * scale
        let outputSize = outputSize(for: sourceSize)
        let ox = output.x * outputSize.width
        let oy = (1 - output.y) * outputSize.height
        let x: CGFloat
        let y: CGFloat
        switch (rotateQuarterTurns % 4 + 4) % 4 {
        case 1: x = oy; y = safeHeight - ox
        case 2: x = safeWidth - ox; y = safeHeight - oy
        case 3: x = safeWidth - oy; y = ox
        default: x = ox; y = oy
        }
        let center = CGPoint(x: crop.width / 2, y: crop.height / 2)
        let rx = x + (crop.width - safeWidth) / 2 - center.x
        let ry = y + (crop.height - safeHeight) / 2 - center.y
        let angle = straightenDegrees * .pi / 180
        let sourceX = crop.minX + center.x + cos(angle) * rx + sin(angle) * ry
        let sourceY = crop.minY + center.y - sin(angle) * rx + cos(angle) * ry
        return NormalizedPoint(sourceX / max(1, sourceSize.width), sourceY / max(1, sourceSize.height))
    }

    public func outputPoint(fromSourceNormalized source: NormalizedPoint, sourceSize: CGSize) -> NormalizedPoint {
        let crop = cropRect(in: CGRect(origin: .zero, size: sourceSize))
        let scale = safeStraightenScale(for: crop.size)
        let safeWidth = crop.width * scale
        let safeHeight = crop.height * scale
        let center = CGPoint(x: crop.width / 2, y: crop.height / 2)
        let px = source.x * sourceSize.width - crop.minX - center.x
        let py = source.y * sourceSize.height - crop.minY - center.y
        let angle = straightenDegrees * .pi / 180
        let x = center.x + cos(angle) * px - sin(angle) * py - (crop.width - safeWidth) / 2
        let y = center.y + sin(angle) * px + cos(angle) * py - (crop.height - safeHeight) / 2
        let ox: CGFloat
        let oy: CGFloat
        switch (rotateQuarterTurns % 4 + 4) % 4 {
        case 1: ox = safeHeight - y; oy = x
        case 2: ox = safeWidth - x; oy = safeHeight - y
        case 3: ox = y; oy = safeWidth - x
        default: ox = x; oy = y
        }
        let size = outputSize(for: sourceSize)
        return NormalizedPoint(ox / max(1, size.width), 1 - oy / max(1, size.height))
    }
}

public extension CoreRenderer {
    static func applyGeometry(_ image: CIImage, geometry: Geometry) -> CIImage {
        let crop = geometry.cropRect(in: image.extent)
        var result = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        if abs(geometry.straightenDegrees) > 0.000001 {
            let center = CGPoint(x: crop.width / 2, y: crop.height / 2)
            let rotation = CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: geometry.straightenDegrees * .pi / 180))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            result = result.transformed(by: rotation)
            let scale = geometry.safeStraightenScale(for: crop.size)
            let safe = CGSize(width: crop.width * scale, height: crop.height * scale)
            let rect = CGRect(x: center.x - safe.width / 2, y: center.y - safe.height / 2, width: safe.width, height: safe.height)
            result = result.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        if geometry.rotateQuarterTurns % 4 != 0 {
            result = result.transformed(by: CGAffineTransform(rotationAngle: CGFloat(geometry.rotateQuarterTurns) * .pi / 2))
            result = result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
        }
        return result
    }
}
