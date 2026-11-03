import Foundation
import CoreImage

public struct WaterAnalysis: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var confidence: Double
    public var samples: Int
    public var frameCount: Int

    public init(red: Double, green: Double, blue: Double, confidence: Double,
                samples: Int, frameCount: Int) {
        self.red = red
        self.green = green
        self.blue = blue
        self.confidence = confidence
        self.samples = samples
        self.frameCount = frameCount
    }
}

public enum WaterEstimator {
    public struct Frame: Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let confidence: Double
        public let samples: Int
    }

    private static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        return ordered[ordered.count / 2]
    }

    public static func frame(_ pixels: [Float], width: Int, height: Int) -> Frame? {
        guard width >= 96, height >= 96, pixels.count >= width * height * 4 else { return nil }
        func sample(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
            let offset = (y * width + x) * 4
            return (Double(pixels[offset]), Double(pixels[offset + 1]),
                    Double(pixels[offset + 2]), Double(pixels[offset + 3]))
        }
        var candidates: [(Double, Double, Double)] = []
        var occupiedRows = Set<Int>()
        for row in 0..<16 {
            for column in 0..<24 {
                let x = min(width - 7, max(6, Int((Double(column) + 0.5) * Double(width) / 24)))
                let y = min(height - 7, max(6, Int((Double(row) + 0.5) * Double(height) / 16)))
                let center = sample(x, y)
                let rgb = [center.0, center.1, center.2]
                guard center.3 > 0.98, rgb.allSatisfy(\.isFinite),
                      rgb.min()! > -0.02, rgb.max()! < 0.9,
                      max(center.1, center.2) - center.0 > 0.035 else { continue }
                let luma = 0.2126 * center.0 + 0.7152 * center.1 + 0.0722 * center.2
                guard luma > 0.035, luma < 0.65 else { continue }
                let neighbors = [sample(x - 5, y), sample(x + 5, y), sample(x, y - 5), sample(x, y + 5)]
                let variation = neighbors.map {
                    abs(0.2126 * $0.0 + 0.7152 * $0.1 + 0.0722 * $0.2 - luma)
                }.reduce(0, +) / 4
                guard variation < 0.018, neighbors.allSatisfy({ $0.3 > 0.98 }) else { continue }
                candidates.append((center.0, center.1, center.2))
                occupiedRows.insert(row)
            }
        }
        guard candidates.count >= 8 else { return nil }
        let red = max(0, median(candidates.map(\.0)))
        let green = median(candidates.map(\.1))
        let blue = median(candidates.map(\.2))
        let deviations = candidates.map { (abs($0.0 - red) + abs($0.1 - green) + abs($0.2 - blue)) / 3 }
        let scale = max(0.025, (red + green + blue) / 3)
        let consistency = max(0, 1 - median(deviations) / (0.35 * scale))
        let confidence = min(1, Double(candidates.count) / 48)
            * min(1, Double(occupiedRows.count) / 8) * consistency
        return Frame(red: red, green: green, blue: blue,
                     confidence: confidence, samples: candidates.count)
    }

    public static func summarize(_ frames: [Frame]) -> WaterAnalysis? {
        guard !frames.isEmpty else { return nil }
        let red = max(0, median(frames.map(\.red)))
        let green = median(frames.map(\.green))
        let blue = median(frames.map(\.blue))
        let disagreement = median(frames.map {
            (abs($0.red - red) + abs($0.green - green) + abs($0.blue - blue)) / 3
        })
        let scale = max(0.025, (red + green + blue) / 3)
        let agreement = max(0, 1 - disagreement / (0.3 * scale))
        return WaterAnalysis(red: red, green: green, blue: blue,
                             confidence: median(frames.map(\.confidence)) * agreement,
                             samples: frames.reduce(0) { $0 + $1.samples }, frameCount: frames.count)
    }
}

private final class VisibilityKernelBundleAnchor {}

private enum VisibilityRendererV5 {
    static let logKernel: CIKernel = kernel("logLuminanceV5")
    static let clarityKernel: CIKernel = kernel("clarityV5")
    static let dehazeKernel: CIKernel = kernel("dehazeV5")

    private static func kernel(_ name: String) -> CIKernel {
        guard let url = Bundle(for: VisibilityKernelBundleAnchor.self).url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let kernel = try? CIKernel(functionName: name, fromMetalLibraryData: data) else {
            preconditionFailure("Renderer v5 visibility kernel \(name) is missing")
        }
        return kernel
    }

    static func dehaze(_ source: CIImage, amount: Double, water: WaterAnalysis?, noise: NoiseAnalysis?) -> CIImage {
        guard amount > 0, let water, water.confidence > 0.05 else { return source }
        let radius = max(1, min(8, min(source.extent.width, source.extent.height) / 2048 * 4))
        let smooth = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: source.extent)
        let sigma = max(noise?.chromaSigma ?? 0, noise?.luminanceSigma ?? 0)
        let noisePenalty = 1 - 0.6 * min(1, max(0, (sigma - 0.002) / 0.013))
        let confidence = Float(water.confidence * noisePenalty)
        guard let result = dehazeKernel.apply(extent: source.extent, roiCallback: { _, rect in rect },
                                  arguments: [source, smooth, Float(water.red), Float(water.green),
                                              Float(water.blue), Float(min(1, amount / 100)), confidence]) else {
            preconditionFailure("Renderer v5 Dehaze kernel failed")
        }
        return result
    }

    static func clarity(_ source: CIImage, amount: Double, noise: NoiseAnalysis?) -> CIImage {
        guard amount != 0 else { return source }
        guard let logImage = logKernel.apply(extent: source.extent, roiCallback: { _, rect in rect },
                                              arguments: [source]) else {
            preconditionFailure("Renderer v5 Clarity luminance kernel failed")
        }
        let radius = max(3, min(24, min(source.extent.width, source.extent.height) / 2048 * 12))
        let reduced = logImage.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let base = reduced.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": logImage, "inputRadius": radius, "inputEpsilon": 0.02
        ]).cropped(to: source.extent)
        guard let result = clarityKernel.apply(extent: source.extent, roiCallback: { _, rect in rect },
                                   arguments: [source, logImage, base, Float(amount / 100),
                                               Float(noise?.luminanceSigma ?? 0)]) else {
            preconditionFailure("Renderer v5 Clarity kernel failed")
        }
        return result
    }
}

public extension CoreRenderer {
    static func renderV5(_ source: CIImage, color: ColorState, masks: [EditMask],
                         detail: TechnicalDetail, analysis: NoiseAnalysis?) -> CIImage {
        let protected = protectV4(source, color: color, masks: masks, detail: detail,
                                  analysis: analysis, includeVisibilityStress: true)
        var current = VisibilityRendererV5.dehaze(protected, amount: color.effective[.dehaze],
                                                  water: analysis?.water, noise: analysis)
        var creative = color.effective
        creative[.clarity] = 0
        creative[.dehaze] = 0
        current = ColorRendererV3.render(current, adjustment: creative)
        current = VisibilityRendererV5.clarity(current, amount: color.effective[.clarity], noise: analysis)
        for mask in masks where mask.enabled && !mask.adjustment.isNeutral {
            var localCreative = mask.adjustment
            localCreative[.clarity] = 0
            localCreative[.dehaze] = 0
            var local = ColorRendererV3.render(current, adjustment: localCreative)
            local = VisibilityRendererV5.clarity(local, amount: mask.adjustment[.clarity], noise: analysis)
            let alpha = MaskRenderer.alphaImage(for: mask, extent: source.extent)
            current = local.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: current, "inputMaskImage": alpha
            ])
        }
        return current
    }
}
