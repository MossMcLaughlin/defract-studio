import Foundation
import CoreImage

public enum FrameMode: String, Codable, Sendable { case fit, fill }

public struct OutputFrame: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var mode: FrameMode
    public var positionX = 0.5
    public var positionY = 0.5

    public init(width: Int, height: Int, mode: FrameMode) {
        self.width = width
        self.height = height
        self.mode = mode
    }

    private func placement(for inputSize: CGSize) -> (Double, Double, Double) {
        let xScale = Double(width) / max(1, inputSize.width)
        let yScale = Double(height) / max(1, inputSize.height)
        let scale = mode == .fit ? min(xScale, yScale) : max(xScale, yScale)
        let x = (Double(width) - inputSize.width * scale) * min(1, max(0, positionX))
        let y = (Double(height) - inputSize.height * scale) * min(1, max(0, positionY))
        return (scale, x, y)
    }

    public func outputPoint(fromInputNormalized input: NormalizedPoint, inputSize: CGSize) -> NormalizedPoint {
        let (scale, x, y) = placement(for: inputSize)
        return NormalizedPoint((input.x * inputSize.width * scale + x) / Double(width),
                               1 - ((1 - input.y) * inputSize.height * scale + y) / Double(height))
    }

    public func inputPoint(fromOutputNormalized output: NormalizedPoint, inputSize: CGSize) -> NormalizedPoint {
        let (scale, x, y) = placement(for: inputSize)
        return NormalizedPoint((output.x * Double(width) - x) / scale / inputSize.width,
                               1 - ((1 - output.y) * Double(height) - y) / scale / inputSize.height)
    }
}

public extension CoreRenderer {
    static func applyOutputFrame(_ image: CIImage, frame: OutputFrame?) -> CIImage {
        guard let frame, frame.width > 0, frame.height > 0,
              image.extent.width > 0, image.extent.height > 0 else { return image }
        let output = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let xScale = output.width / image.extent.width
        let yScale = output.height / image.extent.height
        let scale = frame.mode == .fit ? min(xScale, yScale) : max(xScale, yScale)
        let scaledWidth = image.extent.width * scale
        let scaledHeight = image.extent.height * scale
        let x = (output.width - scaledWidth) * min(1, max(0, frame.positionX))
        let y = (output.height - scaledHeight) * min(1, max(0, frame.positionY))
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                          tx: x - image.extent.minX * scale,
                                          ty: y - image.extent.minY * scale)
        let placed = image.transformed(by: transform)
        if frame.mode == .fit {
            let background = CIImage(color: .black).cropped(to: output)
            return placed.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: background]).cropped(to: output)
        }
        return placed.cropped(to: output)
    }
}
