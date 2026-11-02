import Foundation
import CoreImage

public enum CropAspect: String, CaseIterable, Codable, Sendable {
    case original = "Original"
    case square = "1:1"
    case fourFive = "4:5"
    case nineSixteen = "9:16"
    case sixteenNine = "16:9"

    public var ratio: Double? {
        switch self {
        case .original: nil
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
    public var rotateQuarterTurns = 0
    public var straightenDegrees = 0.0

    public init() {}

    public func cropRect(in bounds: CGRect) -> CGRect {
        guard let ratio = aspect.ratio, bounds.width > 0, bounds.height > 0 else { return bounds }
        let current = bounds.width / bounds.height
        let width = current > ratio ? bounds.height * ratio : bounds.width
        let height = current > ratio ? bounds.height : bounds.width / ratio
        let x = bounds.minX + min(max(centerX, 0), 1) * (bounds.width - width)
        let y = bounds.minY + min(max(centerY, 0), 1) * (bounds.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public extension CoreRenderer {
    static func applyGeometry(_ image: CIImage, geometry: Geometry) -> CIImage {
        let crop = geometry.cropRect(in: image.extent)
        return image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }
}
