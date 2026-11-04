import Foundation
import CoreImage

private final class OutputKernelBundleAnchor {}

private enum OutputKernelV6 {
    private static func kernel(_ name: String) -> CIKernel {
        guard let url = Bundle(for: OutputKernelBundleAnchor.self).url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let kernel = try? CIKernel(functionName: name, fromMetalLibraryData: data) else {
            preconditionFailure("Renderer v6 output kernel \(name) is missing")
        }
        return kernel
    }

    static let sharpening = kernel("sharpenV6")
    static let dither = kernel("ditherV6")
}

public extension CoreRenderer {
    static func sharpenV6(_ source: CIImage, amount: Double, noise: NoiseAnalysis?) -> CIImage {
        guard amount > 0 else { return source }
        let blurred = source.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.85])
            .cropped(to: source.extent)
        guard let result = OutputKernelV6.sharpening.apply(extent: source.extent,
                                                            roiCallback: { _, rect in rect },
                                                            arguments: [source, blurred,
                                                                        Float(min(1, amount / 100)),
                                                                        Float(noise?.luminanceSigma ?? 0)]) else {
            preconditionFailure("Renderer v6 Sharpening kernel failed")
        }
        return result
    }

    static func ditherV6(_ source: CIImage, bits: Int, video: Bool, frameIndex: Int64 = 0) -> CIImage {
        guard bits == 8 || bits == 10 else { return source }
        guard let result = OutputKernelV6.dither.apply(extent: source.extent,
                                                       roiCallback: { _, rect in rect },
                                                       arguments: [source, Float(bits), video ? Float(1) : Float(0),
                                                                   Float(frameIndex & 0x00ff_ffff)]) else {
            preconditionFailure("Renderer v6 output dither kernel failed")
        }
        return result
    }
}
