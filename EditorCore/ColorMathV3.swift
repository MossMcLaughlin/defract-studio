import Foundation
import CoreImage

/// Renderer 3's log-luminance curve. The projection guarantees an ordered result
/// even when neighboring controls pull the curve in opposite directions.
public enum ToneCurveV3 {
    public static let count = 4096
    public static let lower = -14.0
    public static let upper = 10.0

    public static func samples(for adjustment: AdjustmentVector) -> [Float] {
        let contrast = adjustment[.contrast] / 100
        let shadows = adjustment[.shadows] / 100
        let highlights = adjustment[.highlights] / 100
        let blacks = adjustment[.blacks] / 100
        let whites = adjustment[.whites] / 100
        let slope = exp2(0.5 * contrast)
        let step = (upper - lower) / Double(count - 1)
        var values = (0..<count).map { index -> Double in
            let x = lower + Double(index) * step
            func bell(_ center: Double, _ width: Double) -> Double {
                exp(-0.5 * pow((x - center) / width, 2))
            }
            return slope * x + 1.25 * shadows * bell(-3, 1.8)
                + highlights * bell(2, 1.5) + blacks * bell(-7, 1.5)
                + 0.75 * whites * bell(3.5, 1.2)
        }
        // Pool-adjacent-violators on f(x) - 0.05x.
        var starts: [Int] = []
        var sums: [Double] = []
        var lengths: [Int] = []
        for index in values.indices {
            let x = lower + Double(index) * step
            starts.append(index)
            sums.append(values[index] - 0.05 * x)
            lengths.append(1)
            while sums.count > 1 {
                let last = sums.count - 1
                if sums[last - 1] / Double(lengths[last - 1]) <= sums[last] / Double(lengths[last]) { break }
                sums[last - 1] += sums[last]
                lengths[last - 1] += lengths[last]
                sums.removeLast(); lengths.removeLast(); starts.removeLast()
            }
        }
        for block in starts.indices {
            let average = sums[block] / Double(lengths[block])
            for index in starts[block]..<(starts[block] + lengths[block]) {
                values[index] = average + 0.05 * (lower + Double(index) * step)
            }
        }
        return values.map(Float.init)
    }
}

private final class ColorKernelBundleAnchor {}

enum ColorRendererV3 {
    private static let kernel: CIKernel = {
        guard let url = Bundle(for: ColorKernelBundleAnchor.self).url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let kernel = try? CIKernel(functionName: "colorGradeV3", fromMetalLibraryData: data) else {
            preconditionFailure("Renderer v3 Metal kernel is missing")
        }
        return kernel
    }()
    private static let curveCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 12
        return cache
    }()
    private static let bandCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 12
        return cache
    }()

    private static func toneImage(_ adjustment: AdjustmentVector) -> CIImage {
        let parameters: [Parameter] = [.contrast, .highlights, .shadows, .whites, .blacks]
        let key = parameters.map { String(adjustment[$0].bitPattern) }.joined(separator: ":") as NSString
        if let cached = curveCache.object(forKey: key) { return cached }
        let samples = ToneCurveV3.samples(for: adjustment)
        let data = samples.withUnsafeBytes { Data($0) }
        let image = CIImage(bitmapData: data, bytesPerRow: ToneCurveV3.count * MemoryLayout<Float>.size,
                            size: CGSize(width: ToneCurveV3.count, height: 1), format: .Rf, colorSpace: nil)
        curveCache.setObject(image, forKey: key)
        return image
    }

    private static let bandParameters: [(Double, Double, Parameter, Parameter, Parameter)] = [
        (0, 42, .redHue, .redSaturation, .redLuminance),
        (30, 36, .orangeHue, .orangeSaturation, .orangeLuminance),
        (60, 54, .yellowHue, .yellowSaturation, .yellowLuminance),
        (120, 72, .greenHue, .greenSaturation, .greenLuminance),
        (180, 72, .aquaHue, .aquaSaturation, .aquaLuminance),
        (240, 57, .blueHue, .blueSaturation, .blueLuminance),
        (275, 48, .purpleHue, .purpleSaturation, .purpleLuminance),
        (320, 51, .magentaHue, .magentaSaturation, .magentaLuminance)
    ]

    private static func bandImage(_ adjustment: AdjustmentVector) -> CIImage {
        let key = bandParameters.flatMap { [$0.2, $0.3, $0.4] }
            .map { String(adjustment[$0].bitPattern) }.joined(separator: ":") as NSString
        if let cached = bandCache.object(forKey: key) { return cached }
        var table = [Float](repeating: 0, count: 1025 * 4)
        for index in 0...1024 {
            let hue = Double(index) * 360 / 1024
            var total = 0.0
            var weighted = (0.0, 0.0, 0.0)
            for (center, width, hueParameter, saturationParameter, luminanceParameter) in bandParameters {
                let distance = abs(hue - center)
                let wrapped = min(distance, 360 - distance)
                let weight = exp(-0.5 * pow(wrapped / width, 2))
                total += weight
                weighted.0 += weight * adjustment[hueParameter] / 100
                weighted.1 += weight * adjustment[saturationParameter] / 100
                weighted.2 += weight * adjustment[luminanceParameter] / 100
            }
            let offset = index * 4
            table[offset] = Float(weighted.0 / total)
            table[offset + 1] = Float(weighted.1 / total)
            table[offset + 2] = Float(weighted.2 / total)
            table[offset + 3] = 1
        }
        let data = table.withUnsafeBytes { Data($0) }
        let image = CIImage(bitmapData: data, bytesPerRow: 1025 * 4 * MemoryLayout<Float>.size,
                            size: CGSize(width: 1025, height: 1), format: .RGBAf, colorSpace: nil)
        bandCache.setObject(image, forKey: key)
        return image
    }

    static func render(_ source: CIImage, adjustment: AdjustmentVector) -> CIImage {
        if adjustment.isNeutral { return source }
        var image = source
        if adjustment[.temperature] != 0 || adjustment[.tint] != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                // The native target neutral is the illuminant to remove; invert UI directions.
                "inputTargetNeutral": CIVector(x: 6500 - adjustment[.temperature] * 25,
                                                 y: -adjustment[.tint] * 0.5)
            ])
        }
        let curve = toneImage(adjustment)
        let bands = bandImage(adjustment)
        let hasTone = [Parameter.contrast, .highlights, .shadows, .whites, .blacks]
            .contains { adjustment[$0] != 0 }
        let hasMixer = adjustment[.saturation] != 0 || adjustment[.vibrance] != 0
            || bandParameters.contains { band in
                let (_, _, hue, saturation, luminance) = band
                return adjustment[hue] != 0 || adjustment[saturation] != 0 || adjustment[luminance] != 0
            }
        // A recipe-wide strength avoids a per-pixel or zero-crossing brightness jump.
        let overflowDrive = max(0, [adjustment[.exposure] / 0.5,
                                    adjustment[.highlights] / 50, adjustment[.whites] / 50,
                                    adjustment[.shadows] / 50, adjustment[.blacks] / 50].max() ?? 0)
        let shoulderPosition = min(1, overflowDrive)
        let shoulder = shoulderPosition * shoulderPosition * (3 - 2 * shoulderPosition)
        let arguments: [Any] = [image, curve, bands, Float(adjustment[.exposure]), hasTone ? 1.0 as Float : 0.0 as Float,
                                Float(adjustment[.saturation] / 100), Float(adjustment[.vibrance] / 100),
                                Float(shoulder),
                                hasMixer ? 1.0 as Float : 0.0 as Float]
        guard let rendered = kernel.apply(extent: image.extent, roiCallback: { index, rect in
            index == 1 ? curve.extent : index == 2 ? bands.extent : rect
        }, arguments: arguments) else { preconditionFailure("Renderer v3 kernel rejected the grade") }
        return rendered
    }
}

public extension CoreRenderer {
    static func renderV3(_ source: CIImage, color: ColorState, masks: [EditMask]) -> CIImage {
        var current = ColorRendererV3.render(source, adjustment: color.effective)
        for mask in masks where mask.enabled && !mask.adjustment.isNeutral {
            let local = ColorRendererV3.render(current, adjustment: mask.adjustment)
            let alpha = MaskRenderer.alphaImage(for: mask, extent: source.extent)
            current = local.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: current, "inputMaskImage": alpha
            ])
        }
        return current
    }
}
