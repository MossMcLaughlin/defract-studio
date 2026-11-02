import Foundation
import CoreImage

public enum ColorMath {
    static let cubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static func bounded(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func smooth(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = bounded((value - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }
    private static func srgbEncode(_ value: Double) -> Double {
        let x = bounded(value)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }
    private static func srgbDecode(_ value: Double) -> Double {
        let x = bounded(value)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    private static let bands: [(Double, Parameter, Parameter, Parameter)] = [
        (0, .redHue, .redSaturation, .redLuminance),
        (30, .orangeHue, .orangeSaturation, .orangeLuminance),
        (60, .yellowHue, .yellowSaturation, .yellowLuminance),
        (120, .greenHue, .greenSaturation, .greenLuminance),
        (180, .aquaHue, .aquaSaturation, .aquaLuminance),
        (240, .blueHue, .blueSaturation, .blueLuminance),
        (275, .purpleHue, .purpleSaturation, .purpleLuminance),
        (320, .magentaHue, .magentaSaturation, .magentaLuminance)
    ]

    private static func rgbToHSL(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        let maximum = max(rgb.0, rgb.1, rgb.2)
        let minimum = min(rgb.0, rgb.1, rgb.2)
        let difference = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard difference > 0.000001 else { return (0, 0, lightness) }
        let saturation = difference / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maximum == rgb.0 { hue = 60 * ((rgb.1 - rgb.2) / difference).truncatingRemainder(dividingBy: 6) }
        else if maximum == rgb.1 { hue = 60 * ((rgb.2 - rgb.0) / difference + 2) }
        else { hue = 60 * ((rgb.0 - rgb.1) / difference + 4) }
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    private static func hslToRGB(_ hue: Double, _ saturation: Double, _ lightness: Double) -> (Double, Double, Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let rgb: (Double, Double, Double)
        switch h {
        case ..<60: rgb = (c, x, 0)
        case ..<120: rgb = (x, c, 0)
        case ..<180: rgb = (0, c, x)
        case ..<240: rgb = (0, x, c)
        case ..<300: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    public static func applyLinearRGB(_ red: Double, _ green: Double, _ blue: Double, adjustment: AdjustmentVector) -> (Double, Double, Double) {
        if adjustment.isNeutral { return (red, green, blue) }
        let exposure = pow(2, adjustment[.exposure])
        var r = bounded(red * exposure)
        var g = bounded(green * exposure)
        var b = bounded(blue * exposure)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        var tone = luminance
        tone += adjustment[.contrast] / 100 * (tone - 0.5) * 2 * tone * (1 - tone)
        tone += adjustment[.highlights] / 100 * 0.25 * smooth(0.4, 0.9, luminance) * (1 - luminance)
        tone += adjustment[.shadows] / 100 * 0.25 * (1 - smooth(0.1, 0.6, luminance)) * luminance
        tone += adjustment[.whites] / 100 * 0.15 * smooth(0.65, 1, luminance) * (1 - luminance)
        tone += adjustment[.blacks] / 100 * 0.15 * (1 - smooth(0, 0.35, luminance)) * luminance
        let change = tone - luminance
        r = srgbEncode(bounded(r + change))
        g = srgbEncode(bounded(g + change))
        b = srgbEncode(bounded(b + change))
        var (h, s, l) = rgbToHSL((r, g, b))
        var weightedHue = 0.0
        var weightedSaturation = 0.0
        var weightedLuminance = 0.0
        var weightSum = 0.0
        for (center, hueParameter, saturationParameter, luminanceParameter) in bands {
            let distance = abs(h - center)
            let wrapped = min(distance, 360 - distance)
            let weight = pow(1 - smooth(0, 70, wrapped), 2)
            weightedHue += weight * adjustment[hueParameter]
            weightedSaturation += weight * adjustment[saturationParameter]
            weightedLuminance += weight * adjustment[luminanceParameter]
            weightSum += weight
        }
        if weightSum > 0 {
            h += 0.45 * weightedHue / weightSum
            s = bounded(s * (1 + weightedSaturation / weightSum / 100))
            l = bounded(l + weightedLuminance / weightSum / 100 * 0.25)
        }
        s = bounded(s * (1 + adjustment[.saturation] / 100))
        s = bounded(s * (1 + adjustment[.vibrance] / 100 * pow(1 - s, 2)))
        (r, g, b) = hslToRGB(h, s, l)
        return (srgbDecode(r), srgbDecode(g), srgbDecode(b))
    }
}

public extension CoreRenderer {
    static func render(_ source: CIImage, adjustment: AdjustmentVector) -> CIImage {
        if adjustment.isNeutral { return source }
        var image = source
        if adjustment[.temperature] != 0 || adjustment[.tint] != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 + adjustment[.temperature] * 25, y: adjustment[.tint] * 0.5)
            ])
        }
        let dimension = 33
        let key = Parameter.allCases.map { String(adjustment[$0].bitPattern) }.joined(separator: ":") as NSString
        if let cached = ColorMath.cubeCache.object(forKey: key) {
            return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": dimension, "inputCubeData": cached])
        }
        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let result = ColorMath.applyLinearRGB(Double(red) / 32, Double(green) / 32, Double(blue) / 32, adjustment: adjustment)
                    let offset = ((blue * dimension + green) * dimension + red) * 4
                    cube[offset] = Float(result.0)
                    cube[offset + 1] = Float(result.1)
                    cube[offset + 2] = Float(result.2)
                    cube[offset + 3] = 1
                }
            }
        }
        let data = cube.withUnsafeBytes { Data($0) }
        ColorMath.cubeCache.setObject(data as NSData, forKey: key, cost: data.count)
        return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": dimension, "inputCubeData": data])
    }
}
