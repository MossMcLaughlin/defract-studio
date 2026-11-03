import Foundation
import CoreImage

public enum NoiseProtection {
    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func smooth(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    public static func demand(adjustment: AdjustmentVector, detail: TechnicalDetail,
                              analysis: NoiseAnalysis?, includeManual: Bool = true,
                              includeVisibilityStress: Bool = false) -> (color: Double, luminance: Double) {
        let manualColor = includeManual ? clamp(detail.colorNoise / 100) : 0
        let manualLuminance = includeManual ? clamp(detail.luminanceNoise / 100) : 0
        guard detail.autoProtection, !adjustment.isNeutral, let analysis, analysis.confidence > 0 else {
            return (manualColor, manualLuminance)
        }
        let bandSaturation = Parameter.allCases.filter { $0.rawValue.hasSuffix("Saturation") }
            .map { max(0, adjustment[$0]) / 100 }.max() ?? 0
        let stress = clamp(max(0, adjustment[.exposure]) / 2 + max(0, adjustment[.shadows]) / 100
            + 0.5 * max(0, adjustment[.temperature]) / 100
            + max(0, adjustment[.saturation]) / 100 + max(0, adjustment[.vibrance]) / 100
            + bandSaturation + (includeVisibilityStress
                ? max(0, adjustment[.dehaze]) / 100 + 0.5 * abs(adjustment[.clarity]) / 100 : 0))
        let confidence = clamp(analysis.confidence)
        let colorEvidence = smooth((analysis.chromaSigma - 0.002) / 0.013)
        let lumaEvidence = smooth((analysis.luminanceSigma - 0.002) / 0.013)
        return (max(manualColor, 0.45 * stress * colorEvidence * confidence),
                max(manualLuminance, 0.20 * stress * lumaEvidence * confidence))
    }
}

public enum NoiseEstimator {
    public struct Tile: Sendable {
        public let chromaSigma: Double
        public let luminanceSigma: Double
        public let usableFraction: Double
    }

    private static func encoded(_ value: Double) -> Double {
        let magnitude = abs(value)
        let result = magnitude <= 0.0031308 ? 12.92 * magnitude
            : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return value < 0 ? -result : result
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func deviation(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) }) / 0.6745
    }

    public static func tile(_ pixels: [Float], width: Int, height: Int) -> Tile? {
        guard width >= 16, height >= 16, pixels.count >= width * height * 4 else { return nil }
        var luma: [Double] = []
        var blueDifference: [Double] = []
        var redDifference: [Double] = []
        luma.reserveCapacity(width * height / 4)
        for y in stride(from: 0, to: height - 1, by: 2) {
            for x in stride(from: 0, to: width - 1, by: 2) {
                var samples: [(Double, Double, Double)] = []
                for dy in 0...1 {
                    for dx in 0...1 {
                        let offset = ((y + dy) * width + x + dx) * 4
                        let alpha = Double(pixels[offset + 3])
                        guard alpha >= 0.98 else { continue }
                        let red = encoded(Double(pixels[offset]) / alpha)
                        let green = encoded(Double(pixels[offset + 1]) / alpha)
                        let blue = encoded(Double(pixels[offset + 2]) / alpha)
                        let yValue = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                        // Wide-gamut conversion can put an underwater red channel slightly below zero.
                        guard [red, green, blue].allSatisfy(\.isFinite),
                              yValue > 0.01, yValue < 0.98 else { continue }
                        samples.append((yValue, blue - yValue, red - yValue))
                    }
                }
                guard samples.count == 4 else { continue }
                let ys = samples.map(\.0), us = samples.map(\.1), vs = samples.map(\.2)
                guard (ys.max()! - ys.min()!) < 0.06,
                      (us.max()! - us.min()!) < 0.08,
                      (vs.max()! - vs.min()!) < 0.08 else { continue }
                func haar(_ values: [Double]) -> Double {
                    (values[0] - values[1] - values[2] + values[3]) / 2
                }
                luma.append(haar(ys))
                blueDifference.append(haar(us))
                redDifference.append(haar(vs))
            }
        }
        let capacity = (width / 2) * (height / 2)
        guard luma.count >= max(64, capacity / 8) else { return nil }
        return Tile(chromaSigma: max(deviation(blueDifference), deviation(redDifference)),
                    luminanceSigma: deviation(luma), usableFraction: Double(luma.count) / Double(capacity))
    }

    public static func summarize(_ tiles: [Tile], identity: NoiseAnalysisIdentity, frameCount: Int) -> NoiseAnalysis {
        let usable = tiles.filter { $0.chromaSigma.isFinite && $0.luminanceSigma.isFinite }
        let confidence = usable.count < 5 ? 0 : min(1, Double(usable.count - 4) / 12)
            * min(1, median(usable.map(\.usableFraction)) / 0.6)
        let chroma = usable.map(\.chromaSigma).sorted()
        let luminance = usable.map(\.luminanceSigma).sorted()
        let quartile = usable.isEmpty ? 0 : (usable.count - 1) / 4
        return NoiseAnalysis(identity: identity, chromaSigma: chroma.isEmpty ? 0 : chroma[quartile],
                             luminanceSigma: luminance.isEmpty ? 0 : luminance[quartile],
                             confidence: confidence, validTiles: usable.count, frameCount: frameCount)
    }
}

private final class NoiseKernelBundleAnchor {}

private enum NoiseRenderer {
    static let kernel: CIKernel = {
        guard let url = Bundle(for: NoiseKernelBundleAnchor.self).url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let kernel = try? CIKernel(functionName: "sourceProtectV4", fromMetalLibraryData: data) else {
            preconditionFailure("Renderer v4 noise kernel is missing")
        }
        return kernel
    }()

    static func constant(_ color: Double, _ luminance: Double, extent: CGRect) -> CIImage {
        let values: [Float] = [Float(color), Float(luminance), 0, 1]
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil).clampedToExtent().cropped(to: extent)
    }
}

public extension CoreRenderer {
    static func protectV4(_ source: CIImage, color: ColorState, masks: [EditMask],
                          detail: TechnicalDetail, analysis: NoiseAnalysis?,
                          includeVisibilityStress: Bool = false) -> CIImage {
        let global = NoiseProtection.demand(adjustment: color.effective, detail: detail, analysis: analysis,
                                             includeVisibilityStress: includeVisibilityStress)
        var maximumColor = global.color
        var maximumLuminance = global.luminance
        var localDemands: [(EditMask, Double, Double)] = []
        for mask in masks where mask.enabled && !mask.adjustment.isNeutral {
            let local = NoiseProtection.demand(adjustment: mask.adjustment, detail: detail,
                                                analysis: analysis, includeManual: false,
                                                includeVisibilityStress: includeVisibilityStress)
            if local.color > 0 || local.luminance > 0 {
                maximumColor = max(maximumColor, local.color)
                maximumLuminance = max(maximumLuminance, local.luminance)
                localDemands.append((mask, local.color, local.luminance))
            }
        }
        // No filter graph, texture allocation, or spatial pass at zero strength.
        if maximumColor == 0 && maximumLuminance == 0 { return source }
        var field = NoiseRenderer.constant(global.color, global.luminance, extent: source.extent)
        for (mask, colorDemand, lumaDemand) in localDemands {
            let alpha = MaskRenderer.alphaImage(for: mask, extent: source.extent)
            let masked = NoiseRenderer.constant(colorDemand, lumaDemand, extent: source.extent)
                .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: NoiseRenderer.constant(0, 0, extent: source.extent),
                    "inputMaskImage": alpha
                ])
            field = field.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: masked])
        }
        let sigmaY = max(0.012, 3 * (analysis?.luminanceSigma ?? 0))
        let sigmaC = max(0.018, 3 * (analysis?.chromaSigma ?? 0))
        let radius = max(0.75, min(source.extent.width, source.extent.height) / 2048)
        let padding = ceil(2 * radius + 1)
        let protected = NoiseRenderer.kernel.apply(extent: source.extent, roiCallback: { index, rect in
            index == 0 ? rect.insetBy(dx: -padding, dy: -padding) : rect
        }, arguments: [source.clampedToExtent(), field, Float(sigmaY), Float(sigmaC), Float(radius)])
        guard let protected else { preconditionFailure("Renderer v4 noise kernel rejected the source") }
        return protected
    }
}
