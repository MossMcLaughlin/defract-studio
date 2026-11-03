import XCTest
import CoreImage
import AppKit
import EditorCore

final class CoreTests: XCTestCase {
    private let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private func floatPixels(_ image: CIImage) -> [Float] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let context = CIContext(options: [.workingColorSpace: linearSpace, .workingFormat: CIFormat.RGBAh])
        pixels.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 16,
                           bounds: image.extent, format: .RGBAf, colorSpace: linearSpace)
        }
        return pixels
    }

    private func noisyEdgeImage() -> CIImage {
        let width = 128, height = 64
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let base: (Float, Float, Float) = x < 64 ? (0.2, 0.2, 0.2) : (0.36, 0.115, 0.30)
                let seed = (x * 7919 + y * 104729) % 1009
                let colorNoise = (Float(seed) / 1009 - 0.5) * 0.045
                let lumaNoise = (Float((seed * 73) % 1009) / 1009 - 0.5) * 0.018
                let offset = (y * width + x) * 4
                pixels[offset] = base.0 + colorNoise + lumaNoise
                pixels[offset + 1] = base.1 - colorNoise * 0.30 + lumaNoise
                pixels[offset + 2] = base.2 - colorNoise + lumaNoise
                pixels[offset + 3] = 1
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16,
                       size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linearSpace)
    }

    func testV5VisibilityStatePersistenceAndLegacyMapping() throws {
        var recipe = EditRecipe(sourcePath: "/tmp/water.jpg", kind: .photo)
        recipe.color.setEasy { $0.visibility = 50 }
        XCTAssertEqual(recipe.color.base[.contrast], 4)
        XCTAssertEqual(recipe.color.base[.blacks], -3)
        XCTAssertEqual(recipe.color.base[.highlights], -2)
        XCTAssertEqual(recipe.color.base[.clarity], 8)
        XCTAssertEqual(recipe.color.base[.dehaze], 10)
        recipe.color.setEffective(.clarity, to: 25)
        recipe.color.setEffective(.dehaze, to: 30)
        XCTAssertEqual(recipe.color.manualDelta[.clarity], 17)
        XCTAssertEqual(recipe.color.manualDelta[.dehaze], 20)
        let identity = NoiseAnalysisIdentity(recipe: recipe, fileSize: 100, modificationTime: 10)
        let water = WaterAnalysis(red: 0.05, green: 0.2, blue: 0.3,
                                  confidence: 0.75, samples: 80, frameCount: 1)
        recipe.noiseAnalysis = NoiseAnalysis(identity: identity, chromaSigma: 0.003,
                                            luminanceSigma: 0.002, confidence: 0.8,
                                            validTiles: 10, frameCount: 1, water: water)
        var history = EditHistory(recipe)
        history.apply { $0.color.setEasy { $0.visibility = 100 } }
        XCTAssertEqual(history.current.color.effective[.clarity], 33)
        XCTAssertEqual(history.current.color.effective[.dehaze], 40)
        history.undo()
        XCTAssertEqual(history.current.color.effective[.clarity], 25)
        history.redo()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder)
        try store.save(history)
        let reopened = try store.load(id: recipe.id).current
        XCTAssertEqual(reopened.color, history.current.color)
        XCTAssertEqual(reopened.color.underwaterMappingVersion, 2)
        XCTAssertEqual(reopened.noiseAnalysis?.water, water)
        XCTAssertEqual(reopened.noiseAnalysis?.identity.version, 2)
        var legacy = ColorState()
        legacy.setEasy { $0.visibility = 100 }
        XCTAssertEqual(legacy.effective[.contrast], 12)
        XCTAssertEqual(legacy.effective[.clarity], 0)
        XCTAssertEqual(legacy.effective[.dehaze], 0)
    }

    func testV5NeutralBypassAndWaterEstimator() {
        let source = noisyEdgeImage()
        var recipe = EditRecipe(sourcePath: "/tmp/water.jpg", kind: .photo)
        XCTAssertTrue(RenderPlan(recipe: recipe).grade(source) === source)
        let water = WaterAnalysis(red: 0.12, green: 0.25, blue: 0.34,
                                  confidence: 1, samples: 200, frameCount: 1)
        let identity = NoiseAnalysisIdentity(recipe: recipe, fileSize: 1, modificationTime: 1)
        recipe.noiseAnalysis = NoiseAnalysis(identity: identity, chromaSigma: 0, luminanceSigma: 0,
                                            confidence: 1, validTiles: 10, frameCount: 1, water: water)
        XCTAssertTrue(RenderPlan(recipe: recipe).grade(source) === source)
        var pixels = [Float](repeating: 0, count: 128 * 128 * 4)
        for y in 0..<128 {
            for x in 0..<128 {
                let index = (y * 128 + x) * 4
                pixels[index] = 0.12; pixels[index + 1] = 0.25
                pixels[index + 2] = 0.34; pixels[index + 3] = 1
            }
        }
        let estimate = WaterEstimator.frame(pixels, width: 128, height: 128)
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate?.red ?? 0, 0.12, accuracy: 0.001)
        XCTAssertGreaterThan(estimate?.confidence ?? 0, 0.5)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 0.9; pixels[index + 1] = 0.9; pixels[index + 2] = 0.9
        }
        XCTAssertNil(WaterEstimator.frame(pixels, width: 128, height: 128))
    }

    func testV5ClarityDehazeAndMaskAreBounded() {
        let width = 256, height = 128
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let plate: Float = (72..<112).contains(x) && (32..<96).contains(y) ? 0.07 : 0
                let grain = Float((x * 19 + y * 37) % 23) / 23000
                let offset = (y * width + x) * 4
                pixels[offset] = 0.10 + plate * 0.5 + grain
                pixels[offset + 1] = 0.24 + plate + grain
                pixels[offset + 2] = 0.34 + plate + grain
                pixels[offset + 3] = x < 8 ? 0 : 1
            }
        }
        let source = CIImage(bitmapData: pixels.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
                             size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linearSpace)
        var recipe = EditRecipe(sourcePath: "/tmp/water.jpg", kind: .photo)
        let water = WaterAnalysis(red: 0.13, green: 0.28, blue: 0.38,
                                  confidence: 0.8, samples: 100, frameCount: 1)
        let identity = NoiseAnalysisIdentity(recipe: recipe, fileSize: 1, modificationTime: 1)
        recipe.noiseAnalysis = NoiseAnalysis(identity: identity, chromaSigma: 0.002, luminanceSigma: 0.001,
                                            confidence: 1, validTiles: 12, frameCount: 1, water: water)
        recipe.color.setEffective(.clarity, to: 60)
        let clarity = floatPixels(RenderPlan(recipe: recipe).grade(source))
        let original = floatPixels(source)
        let edge = (64 * width + 72) * 4 + 1
        let interior = (64 * width + 90) * 4 + 1
        let outside = (64 * width + 65) * 4 + 1
        XCTAssertTrue(clarity.allSatisfy(\.isFinite))
        print("CP5_CLARITY edge=\(clarity[edge] - original[edge]) interior=\(clarity[interior] - original[interior]) outside=\(clarity[outside] - original[outside])")
        XCTAssertGreaterThan(abs(clarity[edge] - original[edge]), 0.0001)
        XCTAssertLessThan(abs(clarity[interior] - original[interior]), 0.005)
        XCTAssertLessThan(abs(clarity[outside] - original[outside]), 0.01)
        recipe.color.setEffective(.clarity, to: -60)
        let softened = floatPixels(RenderPlan(recipe: recipe).grade(source))
        XCTAssertLessThan(softened[edge] - original[edge], -0.0001)
        recipe.color.setEffective(.clarity, to: 0)
        recipe.color.setEffective(.contrast, to: 30)
        let contrasted = floatPixels(RenderPlan(recipe: recipe).grade(source))
        XCTAssertGreaterThan(abs(contrasted[interior] - original[interior]),
                             abs(clarity[interior] - original[interior]) + 0.005)
        recipe.color.setEffective(.contrast, to: 0)
        recipe.color.setEffective(.dehaze, to: 50)
        let dehazed = floatPixels(RenderPlan(recipe: recipe).grade(source))
        XCTAssertTrue(dehazed.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(abs(dehazed[edge] - original[edge]), 0.0001)
        XCTAssertLessThan(abs(dehazed[edge] - original[edge]), 0.2)
        XCTAssertEqual(dehazed[(64 * width + 2) * 4 + 3], 0, accuracy: 0.001)
        recipe.color.setEffective(.dehaze, to: 0)
        var mask = EditMask(name: "Detail", kind: .radial)
        mask.center = NormalizedPoint(0.35, 0.5)
        mask.radiusX = 0.25; mask.radiusY = 0.4
        mask.adjustment[.clarity] = 60
        recipe.masks = [mask]
        let local = floatPixels(RenderPlan(recipe: recipe).grade(source))
        XCTAssertGreaterThan(abs(local[edge] - original[edge]), 0.0001)
        let far = (64 * width + 220) * 4 + 1
        XCTAssertEqual(local[far], original[far], accuracy: 0.001)

        var gradientPixels = [Float](repeating: 0, count: 128 * 128 * 4)
        for y in 0..<128 {
            for x in 0..<128 {
                let position = (y * 128 + x) * 4
                let fraction = Float(x) / 127
                gradientPixels[position] = 0.03
                gradientPixels[position + 1] = 0.14 + 0.16 * fraction
                gradientPixels[position + 2] = 0.30 + 0.20 * fraction
                gradientPixels[position + 3] = 1
            }
        }
        let gradientImage = CIImage(bitmapData: gradientPixels.withUnsafeBytes { Data($0) }, bytesPerRow: 128 * 16,
                                    size: CGSize(width: 128, height: 128), format: .RGBAf, colorSpace: linearSpace)
        recipe.masks = []
        recipe.color.setEffective(.dehaze, to: 100)
        let gradientOutput = floatPixels(RenderPlan(recipe: recipe).grade(gradientImage))
        XCTAssertTrue(gradientOutput.allSatisfy { $0.isFinite && $0 >= -0.001 && $0 <= 1.001 })
        let row = 64 * 128 * 4
        XCTAssertLessThan(gradientOutput[row + 16 * 4 + 1], gradientOutput[row + 112 * 4 + 1])
        XCTAssertLessThan(gradientOutput[row + 16 * 4 + 2], gradientOutput[row + 112 * 4 + 2])
    }

    func testV4NeutralAndLegacyV3Bypass() {
        let source = noisyEdgeImage()
        var recipe = EditRecipe(sourcePath: "/tmp/noise.png", kind: .photo)
        recipe.schemaVersion = 4; recipe.rendererVersion = 4; recipe.color = ColorState()
        XCTAssertTrue(RenderPlan(recipe: recipe).grade(source) === source)
        recipe.rendererVersion = 3
        recipe.detail.colorNoise = 100
        XCTAssertTrue(RenderPlan(recipe: recipe).grade(source) === source)
        recipe.rendererVersion = 4
        recipe.detail.autoProtection = false
        recipe.detail.colorNoise = 0
        XCTAssertTrue(RenderPlan(recipe: recipe).grade(source) === source)
    }

    func testV4ManualNoiseReducesFlatChromaAndRetainsColorEdge() {
        let source = noisyEdgeImage()
        var recipe = EditRecipe(sourcePath: "/tmp/noise.png", kind: .photo)
        recipe.schemaVersion = 4; recipe.rendererVersion = 4; recipe.color = ColorState()
        recipe.detail.autoProtection = false
        recipe.detail.colorNoise = 80
        recipe.detail.luminanceNoise = 30
        let output = RenderPlan(recipe: recipe).grade(source)
        let before = floatPixels(source), after = floatPixels(output)
        func value(_ pixels: [Float], x: Int, y: Int) -> Double {
            let offset = (y * 128 + x) * 4
            return Double(pixels[offset] - pixels[offset + 2])
        }
        func deviation(_ pixels: [Float]) -> Double {
            let values = (12..<52).flatMap { y in (12..<52).map { x in value(pixels, x: x, y: y) } }
            let mean = values.reduce(0, +) / Double(values.count)
            return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
        }
        let reduction = 1 - deviation(after) / deviation(before)
        let leftBefore = (12..<52).map { value(before, x: 60, y: $0) }.reduce(0, +) / 40
        let rightBefore = (12..<52).map { value(before, x: 67, y: $0) }.reduce(0, +) / 40
        let leftAfter = (12..<52).map { value(after, x: 60, y: $0) }.reduce(0, +) / 40
        let rightAfter = (12..<52).map { value(after, x: 67, y: $0) }.reduce(0, +) / 40
        let edgeRetention = abs(rightAfter - leftAfter) / abs(rightBefore - leftBefore)
        print("CP4_SYNTH chroma_reduction=\(reduction) edge_retention=\(edgeRetention)")
        XCTAssertGreaterThan(reduction, 0.20)
        XCTAssertGreaterThan(edgeRetention, 0.90)
        XCTAssertEqual(floatPixels(output), floatPixels(RenderPlan(recipe: recipe).grade(source)))
    }

    func testV4AnalysisPersistenceUndoAndInvalidation() throws {
        var recipe = EditRecipe(sourcePath: "/tmp/source.mov", kind: .video)
        recipe.schemaVersion = 4; recipe.rendererVersion = 4; recipe.color = ColorState()
        let identity = NoiseAnalysisIdentity(recipe: recipe, fileSize: 100, modificationTime: 10)
        let analysis = NoiseAnalysis(identity: identity, chromaSigma: 0.01, luminanceSigma: 0.005,
                                     confidence: 0.8, validTiles: 10, frameCount: 3)
        var history = EditHistory(recipe)
        history.setNoiseAnalysis(analysis)
        history.apply { $0.detail.colorNoise = 40 }
        history.undo()
        XCTAssertEqual(history.current.noiseAnalysis, analysis)
        history.redo()
        XCTAssertEqual(history.current.detail.colorNoise, 40)
        XCTAssertEqual(history.current.noiseAnalysis, analysis)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder)
        try store.save(history)
        let loaded = try store.load(id: recipe.id)
        XCTAssertEqual(loaded.current.noiseAnalysis, analysis)
        XCTAssertEqual(loaded.current.detail.colorNoise, 40)
        recipe.videoTrim.startSeconds = 2
        XCTAssertFalse(identity.matches(recipe))
        XCTAssertNil(RenderPlan(recipe: recipe).noiseAnalysis)
    }

    func testV4AutoUsesEffectiveGradeAndKeepsMaskProtectionLocal() {
        let source = noisyEdgeImage()
        var recipe = EditRecipe(sourcePath: "/tmp/noise.png", kind: .photo)
        recipe.schemaVersion = 4; recipe.rendererVersion = 4; recipe.color = ColorState()
        let identity = NoiseAnalysisIdentity(recipe: recipe, fileSize: 1, modificationTime: 1)
        recipe.noiseAnalysis = NoiseAnalysis(identity: identity, chromaSigma: 0.015, luminanceSigma: 0.012,
                                            confidence: 1, validTiles: 12, frameCount: 1)
        var mask = EditMask(name: "Local lift", kind: .radial)
        mask.center = NormalizedPoint(0.25, 0.5)
        mask.radiusX = 0.25
        mask.radiusY = 0.45
        mask.adjustment[.exposure] = 1
        recipe.masks = [mask]
        let protected = CoreRenderer.protectV4(source, color: recipe.color, masks: recipe.masks,
                                               detail: recipe.detail, analysis: recipe.noiseAnalysis)
        let before = floatPixels(source), after = floatPixels(protected)
        let inside = (32 * 128 + 32) * 4
        let outside = (32 * 128 + 112) * 4
        XCTAssertGreaterThan((0..<3).reduce(0.0) { $0 + abs(Double(after[inside + $1] - before[inside + $1])) }, 0.0001)
        // The active CI kernel writes half-float output, so outside-mask pixels can round once.
        for channel in 0..<4 { XCTAssertEqual(after[outside + channel], before[outside + channel], accuracy: 0.001) }
        recipe.detail.autoProtection = false
        XCTAssertTrue(CoreRenderer.protectV4(source, color: recipe.color, masks: recipe.masks,
                                             detail: recipe.detail, analysis: recipe.noiseAnalysis) === source)
        var easy = ColorState()
        easy.setEasy { $0.light = 50 }
        var manual = ColorState()
        for parameter in Parameter.allCases {
            manual.setEffective(parameter, to: easy.effective[parameter])
        }
        let a = NoiseProtection.demand(adjustment: easy.effective, detail: TechnicalDetail(), analysis: recipe.noiseAnalysis)
        let b = NoiseProtection.demand(adjustment: manual.effective, detail: TechnicalDetail(), analysis: recipe.noiseAnalysis)
        XCTAssertEqual(a.color, b.color)
        XCTAssertEqual(a.luminance, b.luminance)
    }

    private func v3Pixel(_ rgb: (Float, Float, Float), adjustments: [(Parameter, Double)], alpha: Float = 1) throws -> [Float] {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let sourceValues: [Float] = [rgb.0 * alpha, rgb.1 * alpha, rgb.2 * alpha, alpha]
        let data = sourceValues.withUnsafeBytes { Data($0) }
        let source = CIImage(bitmapData: data, bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                             format: .RGBAf, colorSpace: space)
        var recipe = EditRecipe(sourcePath: "/tmp/swatch.png", kind: .photo)
        for (parameter, value) in adjustments { recipe.color.setEffective(parameter, to: value) }
        let result = RenderPlan(recipe: recipe).grade(source)
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAh])
        var pixels = [Float](repeating: 0, count: 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(result, toBitmap: bytes.baseAddress!, rowBytes: 16,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        }
        return pixels
    }

    func testV3ExposureWhiteBalanceAndNeutral() throws {
        let neutral = try v3Pixel((0.1, 0.2, 0.3), adjustments: [])
        XCTAssertEqual(neutral[0], 0.1, accuracy: 0.001)
        XCTAssertEqual(neutral[1], 0.2, accuracy: 0.001)
        XCTAssertEqual(neutral[2], 0.3, accuracy: 0.001)
        let doubled = try v3Pixel((0.1, 0.2, 0.3), adjustments: [(.exposure, 1)])
        for channel in 0..<3 { XCTAssertEqual(doubled[channel], neutral[channel] * 2, accuracy: 0.005) }
        let warm = try v3Pixel((0.2, 0.2, 0.2), adjustments: [(.temperature, 50)])
        XCTAssertGreaterThan(warm[0], warm[2])
        let magenta = try v3Pixel((0.2, 0.2, 0.2), adjustments: [(.tint, 50)])
        XCTAssertGreaterThan((magenta[0] + magenta[2]) / 2, magenta[1])
    }

    func testV3ToneProjectionAndFiniteExtendedValues() throws {
        var vector = AdjustmentVector()
        vector[.contrast] = -100
        vector[.shadows] = 100
        vector[.highlights] = -100
        vector[.blacks] = 100
        vector[.whites] = -100
        let samples = ToneCurveV3.samples(for: vector)
        XCTAssertEqual(samples.count, 4096)
        let minimumStep = Float(0.05 * 24 / 4095)
        for index in 1..<samples.count {
            XCTAssertTrue(samples[index].isFinite)
            XCTAssertGreaterThanOrEqual(samples[index] - samples[index - 1], minimumStep - 0.00001)
        }
        let extended = try v3Pixel((-0.2, 0.5, 1.4), adjustments: [(.contrast, 50), (.saturation, 50)])
        XCTAssertTrue(extended.allSatisfy(\.isFinite))
        XCTAssertTrue(extended.prefix(3).allSatisfy { (0...1).contains($0) })
    }

    func testV3ToneRenderingIsOrderedAndDirectional() throws {
        let settings: [(Parameter, Double)] = [(.contrast, -100), (.shadows, 100),
                                               (.highlights, -100), (.blacks, 100), (.whites, -100)]
        let grays: [Float] = [0.001, 0.003, 0.01, 0.03, 0.08, 0.18, 0.4, 0.7, 0.95]
        let output = try grays.map { try v3Pixel(($0, $0, $0), adjustments: settings)[0] }
        for index in 1..<output.count { XCTAssertGreaterThan(output[index], output[index - 1]) }
        let shadow = try v3Pixel((0.03, 0.03, 0.03), adjustments: [(.shadows, 50)])
        XCTAssertGreaterThan(shadow[0], 0.03)
        let highlight = try v3Pixel((0.7, 0.7, 0.7), adjustments: [(.highlights, -50)])
        XCTAssertLessThan(highlight[0], 0.7)
        let pivot = try v3Pixel((0.18, 0.18, 0.18), adjustments: [(.contrast, 70)])
        XCTAssertEqual(pivot[0], 0.18, accuracy: 0.002)
        let neutralBright = try v3Pixel((0.9, 0.9, 0.9), adjustments: [])
        let tinyExposure = try v3Pixel((0.9, 0.9, 0.9), adjustments: [(.exposure, 0.0001)])
        XCTAssertLessThan(abs(tinyExposure[0] - neutralBright[0]), 0.001)
    }

    func testV3MixerHueDirectionsGraysAndAlpha() throws {
        let green = try v3Pixel((0.02, 0.45, 0.08), adjustments: [])
        let shiftedGreen = try v3Pixel((0.02, 0.45, 0.08), adjustments: [(.greenHue, 80)])
        XCTAssertGreaterThan(shiftedGreen[2], green[2])
        let aqua = try v3Pixel((0.02, 0.35, 0.48), adjustments: [])
        let shiftedAqua = try v3Pixel((0.02, 0.35, 0.48), adjustments: [(.aquaHue, 80)])
        XCTAssertGreaterThan(shiftedAqua[2] - shiftedAqua[1], aqua[2] - aqua[1])
        let gray = try v3Pixel((0.3, 0.3, 0.3), adjustments: [(.redHue, 100), (.greenHue, 100)])
        XCTAssertEqual(gray[0], gray[1], accuracy: 0.002)
        XCTAssertEqual(gray[1], gray[2], accuracy: 0.002)
        let desaturated = try v3Pixel((0.02, 0.45, 0.08), adjustments: [(.saturation, -100)])
        XCTAssertEqual(desaturated[0], desaturated[1], accuracy: 0.002)
        XCTAssertEqual(desaturated[1], desaturated[2], accuracy: 0.002)
        let redLeft = try v3Pixel((0.5, 0.01, 0.02), adjustments: [(.redHue, 70)])
        let redRight = try v3Pixel((0.5, 0.02, 0.01), adjustments: [(.redHue, 70)])
        for channel in 0..<3 { XCTAssertLessThan(abs(redLeft[channel] - redRight[channel]), 0.06) }
        let transparent = try v3Pixel((0.2, 0.3, 0.4), adjustments: [(.vibrance, 100)], alpha: 0)
        XCTAssertTrue(transparent.allSatisfy(\.isFinite))
        XCTAssertEqual(transparent[3], 0, accuracy: 0.0001)
        let translucent = try v3Pixel((0.2, 0.3, 0.4), adjustments: [(.blueHue, 50)], alpha: 0.25)
        XCTAssertTrue(translucent.allSatisfy(\.isFinite))
        XCTAssertEqual(translucent[3], 0.25, accuracy: 0.001)
    }

    func testV3AllEightMixerBandsRespond() throws {
        let swatches: [((Float, Float, Float), Parameter, Parameter, Parameter)] = [
            ((0.5, 0.02, 0.02), .redHue, .redSaturation, .redLuminance),
            ((0.5, 0.2, 0.01), .orangeHue, .orangeSaturation, .orangeLuminance),
            ((0.5, 0.5, 0.01), .yellowHue, .yellowSaturation, .yellowLuminance),
            ((0.02, 0.5, 0.02), .greenHue, .greenSaturation, .greenLuminance),
            ((0.02, 0.4, 0.5), .aquaHue, .aquaSaturation, .aquaLuminance),
            ((0.01, 0.05, 0.5), .blueHue, .blueSaturation, .blueLuminance),
            ((0.2, 0.01, 0.5), .purpleHue, .purpleSaturation, .purpleLuminance),
            ((0.5, 0.01, 0.2), .magentaHue, .magentaSaturation, .magentaLuminance)
        ]
        for (swatch, hue, saturation, luminance) in swatches {
            let before = try v3Pixel(swatch, adjustments: [])
            for (parameter, value) in [(hue, 50.0), (saturation, -50.0), (luminance, 50.0)] {
                let after = try v3Pixel(swatch, adjustments: [(parameter, value)])
                let change = zip(before.prefix(3), after.prefix(3)).reduce(0 as Float) { $0 + abs($1.0 - $1.1) }
                XCTAssertGreaterThan(change, 0.003, "\(parameter) produced no visible change")
            }
        }
    }

    func testV3SaturationAndVibranceScaleChroma() throws {
        let source: (Float, Float, Float) = (0.24, 0.27, 0.3)
        let neutral = try v3Pixel(source, adjustments: [])
        let saturated = try v3Pixel(source, adjustments: [(.saturation, 60)])
        let vivid = try v3Pixel(source, adjustments: [(.vibrance, 60)])
        let muted = try v3Pixel(source, adjustments: [(.vibrance, -60)])
        func spread(_ pixel: [Float]) -> Float { pixel[2] - pixel[0] }
        XCTAssertGreaterThan(spread(saturated), spread(neutral))
        XCTAssertGreaterThan(spread(vivid), spread(neutral))
        XCTAssertLessThan(spread(muted), spread(neutral))
    }

    func testV3MaskedGradeKeepsGlobalAdjustment() {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAh])
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        var recipe = EditRecipe(sourcePath: "/tmp/masked.png", kind: .photo)
        recipe.color.setEffective(.exposure, to: 0.4)
        let global = RenderPlan(recipe: recipe).grade(source)
        var mask = EditMask(name: "Center", kind: .radial)
        mask.adjustment[.exposure] = 0.5
        recipe.masks = [mask]
        let combined = RenderPlan(recipe: recipe).grade(source)
        func pixel(_ image: CIImage, x: Int, y: Int) -> Float {
            var values = [Float](repeating: 0, count: 4)
            values.withUnsafeMutableBytes { bytes in
                context.render(image, toBitmap: bytes.baseAddress!, rowBytes: 16,
                               bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: space)
            }
            return values[0]
        }
        XCTAssertGreaterThan(pixel(combined, x: 8, y: 8), pixel(global, x: 8, y: 8))
        XCTAssertEqual(pixel(combined, x: 0, y: 0), pixel(global, x: 0, y: 0), accuracy: 0.002)
        XCTAssertGreaterThan(pixel(global, x: 0, y: 0), pixel(source, x: 0, y: 0))
    }

    func testSavedRendererColorReferences() throws {
        let contextV1 = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let contextV2 = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .workingFormat: CIFormat.RGBAh])
        var recipe = EditRecipe(sourcePath: "/tmp/color-reference.jpg", kind: .photo)
        recipe.color = ColorState()
        recipe.color.setEffective(.exposure, to: 0.5)
        recipe.color.setEffective(.temperature, to: 18)
        recipe.color.setEffective(.contrast, to: 24)
        recipe.color.setEffective(.greenHue, to: 42)
        recipe.color.setEffective(.aquaSaturation, to: 35)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.18, 0.18), (0.06, 0.42, 0.11), (0.04, 0.35, 0.48)]
        let expected: [Int: [[UInt8]]] = [
            1: [[57, 60, 64, 255], [16, 157, 74, 255], [2, 149, 237, 255]],
            2: [[49, 49, 51, 255], [3, 120, 54, 255], [1, 98, 143, 255]],
            3: [[53, 51, 49, 255], [0, 125, 59, 255], [5, 103, 144, 255]],
            4: [[53, 51, 49, 255], [0, 125, 59, 255], [5, 103, 144, 255]]
        ]
        for version in [1, 2, 3, 4] {
            recipe.schemaVersion = version
            recipe.rendererVersion = version == 1 ? nil : version
            var savedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
            savedObject.removeValue(forKey: "technicalDetail")
            savedObject.removeValue(forKey: "noiseAnalysis")
            let historical = try JSONDecoder().decode(EditRecipe.self, from: JSONSerialization.data(withJSONObject: savedObject))
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = ProjectStore(directory: folder)
            try store.save(EditHistory(historical))
            let reopened = try store.load(id: recipe.id).current
            let context = version == 1 ? contextV1 : contextV2
            for (index, (red, green, blue)) in colors.enumerated() {
                let source = CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
                let rendered = RenderPlan(recipe: reopened).grade(source)
                let image = try XCTUnwrap(context.createCGImage(rendered, from: rendered.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
                let bytes = Array(try XCTUnwrap(image.dataProvider?.data) as Data)
                XCTAssertEqual(Array(bytes.prefix(4)), try XCTUnwrap(expected[version]?[index]),
                               "Saved renderer v\(version) color changed")
            }
        }
    }
    func testRendererVersionDefaultsAndLegacyDecode() throws {
        let current = EditRecipe(sourcePath: "/tmp/source.jpg", kind: .photo)
        XCTAssertEqual(current.schemaVersion, 5)
        XCTAssertEqual(current.rendererVersion, 5)
        XCTAssertEqual(current.color.underwaterMappingVersion, 2)
        var historical = current
        historical.color = ColorState()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(historical)) as? [String: Any])
        object.removeValue(forKey: "rendererVersion")
        object.removeValue(forKey: "sourceColor")
        object.removeValue(forKey: "technicalDetail")
        object.removeValue(forKey: "noiseAnalysis")
        object["schemaVersion"] = 1
        var legacy = try JSONDecoder().decode(EditRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.rendererVersion)
        XCTAssertEqual(RenderPlan(recipe: legacy).version, 1)
        XCTAssertEqual(legacy.color.underwaterMappingVersion, 1)
        legacy.color.setEasy { $0.visibility = 100 }
        XCTAssertEqual(legacy.color.effective[.contrast], 12)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder)
        try store.save(EditHistory(legacy))
        let reopened = try store.load(id: legacy.id).current
        XCTAssertNil(reopened.rendererVersion)
        XCTAssertEqual(reopened.color.effective, legacy.color.effective)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let expected = CoreRenderer.render(source, color: reopened.color, masks: reopened.masks)
        let actual = RenderPlan(recipe: reopened).grade(source)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let a = try XCTUnwrap(context.createCGImage(expected, from: expected.extent))
        let b = try XCTUnwrap(context.createCGImage(actual, from: actual.extent))
        XCTAssertEqual(Array(try XCTUnwrap(a.dataProvider?.data) as Data), Array(try XCTUnwrap(b.dataProvider?.data) as Data))
    }
    func testV2NeutralPlanAndSourceColorAcrossUndoAndStorage() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        var transitional = EditRecipe(sourcePath: "/tmp/source.jpg", kind: .photo)
        transitional.schemaVersion = 2
        transitional.rendererVersion = 2
        transitional.color = ColorState()
        var history = EditHistory(transitional)
        XCTAssertTrue(RenderPlan(recipe: history.current).grade(source) === source)
        history.apply { $0.color.setEffective(.exposure, to: 0.5) }
        let descriptor = SourceColorDescriptor(sourceBitDepth: 10, primaries: "ITU_R_709_2", transfer: "ITU_R_709_2",
                                               fullRange: true, dynamicRange: .sdr, evidence: "fixture")
        history.setSourceColor(descriptor)
        history.undo()
        XCTAssertEqual(history.current.sourceColor, descriptor)
        history.redo()
        XCTAssertEqual(history.current.sourceColor, descriptor)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder)
        try store.save(history)
        let reopened = try store.load(id: history.current.id)
        XCTAssertEqual(reopened.current.sourceColor, descriptor)
        XCTAssertEqual(reopened.current.rendererVersion, 2)
        XCTAssertEqual(reopened.current.color.manualDelta[.exposure], 0.5)
        var relinked = reopened
        relinked.apply { $0.sourcePath = "/tmp/relinked.jpg"; $0.sourceColor = nil }
        let replacement = SourceColorDescriptor(sourceBitDepth: 8, dynamicRange: .sdr, evidence: "relink")
        relinked.setSourceColor(replacement)
        relinked.undo()
        XCTAssertEqual(relinked.current.sourceColor, descriptor)
    }
    func testNeutralIdentity() {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let result = CoreRenderer.render(source, adjustment: AdjustmentVector())
        XCTAssertTrue(result === source)
    }

    func testGradeSerialization() throws {
        var adjustment = AdjustmentVector()
        adjustment[.exposure] = 0.5
        adjustment[.saturation] = 18
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentVector.self, from: JSONEncoder().encode(adjustment)), adjustment)
    }

    func testEasyBaseManualDeltaAndRoundTrip() throws {
        var state = ColorState()
        state.setEasy { $0.waterColor = 50; $0.colorRecovery = 50 }
        XCTAssertEqual(state.base[.temperature], 7)
        XCTAssertEqual(state.base[.redSaturation], 7)
        state.setEffective(.temperature, to: 15)
        XCTAssertEqual(state.manualDelta[.temperature], 8)
        state.setEasy { $0.waterColor = 100 }
        XCTAssertEqual(state.base[.temperature], 14)
        XCTAssertEqual(state.effective[.temperature], 22)
        XCTAssertEqual(state.effective[.redSaturation], 7)
        let reopened = try JSONDecoder().decode(ColorState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reopened, state)
        XCTAssertFalse(reopened.base.isNeutral)
    }

    func testWaterCurveAndHueDirection() {
        var state = ColorState()
        state.setEasy { $0.waterColor = -50 }
        XCTAssertEqual(state.base[.aquaHue], 6)
        XCTAssertEqual(state.base[.temperature], 0)
        state.setEasy { $0.waterColor = 25 }
        XCTAssertEqual(state.base[.greenHue], 12.5)
        var vector = AdjustmentVector()
        vector[.greenHue] = 100
        let shifted = ColorMath.applyLinearRGB(0, 0.5, 0, adjustment: vector)
        XCTAssertGreaterThan(shifted.2, 0.01)
        XCTAssertTrue(shifted.0.isFinite && shifted.1.isFinite && shifted.2.isFinite)
    }

    func testHistoryAndAtomicStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        var history = EditHistory(EditRecipe(sourcePath: "/tmp/source.jpg", kind: .photo))
        history.apply { $0.color.setEasy { $0.waterColor = 50 } }
        history.apply { $0.color.setEffective(.aquaHue, to: 20) }
        history.undo()
        XCTAssertEqual(history.current.color.effective[.aquaHue], 15)
        history.redo()
        XCTAssertEqual(history.current.color.effective[.aquaHue], 20)
        history.undo()
        history.apply { $0.color.setEffective(.aquaHue, to: 23) }
        XCTAssertTrue(history.redoStack.isEmpty)
        try store.save(history)
        let reopened = try store.load(id: history.current.id)
        XCTAssertEqual(reopened.current.color.effective[.aquaHue], 23)
        XCTAssertEqual(reopened.undoStack.count, 2)
        XCTAssertEqual(try store.loadAll().count, 1)
    }

    func testExportStateAndCorruptSessionRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        var history = EditHistory(EditRecipe(sourcePath: "/tmp/source.jpg", kind: .photo))
        XCTAssertFalse(history.current.hasUnexportedEdits)
        history.apply { $0.color.setEasy { $0.waterColor = 50 } }
        XCTAssertTrue(history.current.hasUnexportedEdits)
        history.markExported()
        XCTAssertFalse(history.current.hasUnexportedEdits)
        try store.save(history)
        let reopened = try store.load(id: history.current.id)
        XCTAssertFalse(reopened.current.hasUnexportedEdits)
        history.apply { $0.color.setEffective(.aquaHue, to: 20) }
        XCTAssertTrue(history.current.hasUnexportedEdits)
        history.undo()
        XCTAssertTrue(history.current.hasUnexportedEdits)
        let corrupt = directory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("broken".utf8).write(to: corrupt)
        let recovered = try store.loadRecovering()
        XCTAssertEqual(recovered.histories.count, 1)
        XCTAssertEqual(recovered.failedFiles.map { $0.standardizedFileURL.path }, [corrupt.standardizedFileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testCropGeometryAcrossOrientations() {
        var geometry = Geometry()
        geometry.aspect = .fourFive
        let portrait = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1536, height: 2048))
        XCTAssertEqual(portrait.width, 1536)
        XCTAssertEqual(portrait.height, 1920)
        geometry.aspect = .nineSixteen
        let landscape = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(landscape.height, 1080)
        XCTAssertEqual(landscape.width, 607.5)
        geometry.centerX = 0
        XCTAssertEqual(geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1920, height: 1080)).minX, 0)
    }

    func testEveryMathControlHasEffect() {
        let hues: [Double] = [0, 30, 60, 120, 180, 240, 275, 320]
        func linear(_ encoded: Double) -> Double {
            encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        for (index, parameter) in Parameter.allCases.prefix(34).enumerated() where parameter != .temperature && parameter != .tint {
            let sample: (Double, Double, Double)
            if index >= 10 {
                let hue = hues[(index - 10) / 3] / 60
                let x = 0.8 * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
                let encoded: (Double, Double, Double)
                switch hue {
                case ..<1: encoded = (0.9, 0.1 + x, 0.1)
                case ..<2: encoded = (0.1 + x, 0.9, 0.1)
                case ..<3: encoded = (0.1, 0.9, 0.1 + x)
                case ..<4: encoded = (0.1, 0.1 + x, 0.9)
                case ..<5: encoded = (0.1 + x, 0.1, 0.9)
                default: encoded = (0.9, 0.1, 0.1 + x)
                }
                sample = (linear(encoded.0), linear(encoded.1), linear(encoded.2))
            } else if parameter == .highlights || parameter == .whites { sample = (0.8, 0.7, 0.6) }
            else if parameter == .shadows || parameter == .blacks { sample = (0.2, 0.15, 0.1) }
            else { sample = (0.4, 0.2, 0.1) }
            var adjustment = AdjustmentVector()
            adjustment[parameter] = parameter == .exposure ? 0.5 : 30
            let changed = ColorMath.applyLinearRGB(sample.0, sample.1, sample.2, adjustment: adjustment)
            let difference = abs(changed.0 - sample.0) + abs(changed.1 - sample.1) + abs(changed.2 - sample.2)
            XCTAssertGreaterThan(difference, 0.0001, "\(parameter) did not change its test color")
        }
    }

    func testMaskMathBrushPersistenceAndLocalBlend() throws {
        var mask = EditMask(name: "Subject", kind: .brush)
        mask.strokes = [
            BrushStroke(operation: .add, points: [NormalizedPoint(0.5, 0.5)], size: 0.4, feather: 0.5),
            BrushStroke(operation: .erase, points: [NormalizedPoint(0.5, 0.5)], size: 0.1, feather: 0.5)
        ]
        XCTAssertEqual(MaskMath.alpha(at: NormalizedPoint(0.5, 0.5), mask: mask), 0, accuracy: 0.001)
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.6, 0.5), mask: mask), 0.5)
        let restored = try JSONDecoder().decode(EditMask.self, from: JSONEncoder().encode(mask))
        XCTAssertEqual(restored, mask)
        var radial = EditMask(name: "Center", kind: .radial)
        radial.adjustment[.exposure] = 1
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let rendered = CoreRenderer.render(source, color: ColorState(), masks: [radial])
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(rendered, from: source.extent))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let center = try XCTUnwrap(bitmap.colorAt(x: 32, y: 32))
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertGreaterThan(center.redComponent, corner.redComponent + 0.05)
        XCTAssertEqual(corner.redComponent, 0.2, accuracy: 0.03)
    }

    func testRotateAndStraightenGeometry() {
        var geometry = Geometry()
        geometry.rotateQuarterTurns = 1
        XCTAssertEqual(geometry.outputSize(for: CGSize(width: 100, height: 200)), CGSize(width: 200, height: 100))
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let rotated = CoreRenderer.applyGeometry(source, geometry: geometry)
        XCTAssertEqual(rotated.extent.size.width, 200, accuracy: 0.001)
        XCTAssertEqual(rotated.extent.size.height, 100, accuracy: 0.001)
        geometry.rotateQuarterTurns = 0
        geometry.straightenDegrees = 10
        let straightened = CoreRenderer.applyGeometry(source, geometry: geometry)
        XCTAssertLessThan(straightened.extent.width, 100)
        XCTAssertLessThan(straightened.extent.height, 200)
        XCTAssertEqual(straightened.extent.width / straightened.extent.height, 0.5, accuracy: 0.001)
    }

    func testFreeCropAndLinearMaskInversion() {
        var geometry = Geometry()
        geometry.aspect = .free
        geometry.freeWidth = 0.5
        geometry.freeHeight = 0.75
        geometry.centerX = 1
        let crop = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(crop, CGRect(x: 500, y: 100, width: 500, height: 600))
        var mask = EditMask(name: "Sky", kind: .linear)
        XCTAssertLessThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.1), mask: mask), 0.01)
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.9), mask: mask), 0.99)
        mask.inverted = true
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.1), mask: mask), 0.99)
    }

    func testSourcePointMappingSurvivesCropAndRotation() {
        let size = CGSize(width: 1536, height: 2048)
        for turn in [-1, 0, 1, 2] {
            var geometry = Geometry()
            geometry.aspect = .fourFive
            geometry.cropScale = 0.8
            geometry.centerX = 0.7
            geometry.centerY = 0.3
            geometry.straightenDegrees = 7
            geometry.rotateQuarterTurns = turn
            let source = NormalizedPoint(0.5, 0.5)
            let displayed = geometry.outputPoint(fromSourceNormalized: source, sourceSize: size)
            let restored = geometry.sourcePoint(fromOutputNormalized: displayed, sourceSize: size)
            XCTAssertEqual(restored.x, source.x, accuracy: 0.000001)
            XCTAssertEqual(restored.y, source.y, accuracy: 0.000001)
        }
    }

    func testIndependentInverseMaskAndRadialRotationRoundTrip() throws {
        var original = EditMask(name: "Foreground", kind: .brush)
        original.strokes = [BrushStroke(operation: .add, points: [NormalizedPoint(0.5, 0.5)], size: 0.4, feather: 0.2)]
        original.adjustment[.exposure] = 1
        let copy = original.invertedCopy()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertTrue(copy.adjustment.isNeutral)
        XCTAssertEqual(MaskMath.alpha(at: NormalizedPoint(0.5, 0.5), mask: copy), 1 - MaskMath.alpha(at: NormalizedPoint(0.5, 0.5), mask: original), accuracy: 0.001)
        original.strokes.removeAll()
        XCTAssertEqual(copy.strokes.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(EditMask.self, from: JSONEncoder().encode(copy)), copy)

        var radial = EditMask(name: "Oval", kind: .radial)
        radial.radiusX = 0.4
        radial.radiusY = 0.1
        let point = NormalizedPoint(0.8, 0.5)
        XCTAssertGreaterThan(MaskMath.alpha(at: point, mask: radial), 0.5)
        radial.rotationDegrees = 90
        XCTAssertLessThan(MaskMath.alpha(at: point, mask: radial), 0.1)
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let renderedMask = MaskRenderer.alphaImage(for: radial, extent: extent)
        let cg = try XCTUnwrap(CIContext().createCGImage(renderedMask, from: extent))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 80, y: 50)).redComponent, 0.2)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 50, y: 80)).redComponent, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(EditMask.self, from: JSONEncoder().encode(radial)), radial)
        let oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(radial)) as! [String: Any]
        var withoutAngle = oldJSON
        withoutAngle.removeValue(forKey: "rotationDegrees")
        XCTAssertNil(try JSONDecoder().decode(EditMask.self, from: JSONSerialization.data(withJSONObject: withoutAngle)).rotationDegrees)
    }

    func testGlobalAndLocalMaskComposeInSavedOrder() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        var global = ColorState()
        global.setEffective(.exposure, to: 0.5)
        var mask = EditMask(name: "Center", kind: .radial)
        mask.adjustment[.exposure] = 0.5
        let context = CIContext()
        func pixel(_ masks: [EditMask], _ x: Int, _ y: Int) throws -> CGFloat {
            let rendered = CoreRenderer.render(source, color: global, masks: masks)
            let image = try XCTUnwrap(context.createCGImage(rendered, from: source.extent))
            return try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)).redComponent
        }
        let globalCenter = try pixel([], 32, 32)
        let maskedCenter = try pixel([mask], 32, 32)
        XCTAssertGreaterThan(maskedCenter, globalCenter + 0.03)
        XCTAssertEqual(try pixel([mask], 0, 0), try pixel([], 0, 0), accuracy: 0.03)
        mask.enabled = false
        XCTAssertEqual(try pixel([mask], 32, 32), globalCenter, accuracy: 0.03)
    }

    func testFitAndFillFrameWithoutStretching() throws {
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let context = CIContext()
        let fit = CoreRenderer.applyOutputFrame(source, frame: OutputFrame(width: 200, height: 200, mode: .fit))
        let fill = CoreRenderer.applyOutputFrame(source, frame: OutputFrame(width: 200, height: 200, mode: .fill))
        XCTAssertEqual(fit.extent.size, CGSize(width: 200, height: 200))
        XCTAssertEqual(fill.extent.size, CGSize(width: 200, height: 200))
        let fitBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.createCGImage(fit, from: fit.extent)))
        let fillBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.createCGImage(fill, from: fill.extent)))
        XCTAssertLessThan(try XCTUnwrap(fitBitmap.colorAt(x: 10, y: 100)).redComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(fitBitmap.colorAt(x: 100, y: 100)).redComponent, 0.95)
        XCTAssertGreaterThan(try XCTUnwrap(fillBitmap.colorAt(x: 10, y: 100)).redComponent, 0.95)
        for mode in [FrameMode.fit, .fill] {
            let frame = OutputFrame(width: 1080, height: 1920, mode: mode)
            let input = NormalizedPoint(0.3, 0.7)
            let shown = frame.outputPoint(fromInputNormalized: input, inputSize: CGSize(width: 800, height: 1000))
            let restored = frame.inputPoint(fromOutputNormalized: shown, inputSize: CGSize(width: 800, height: 1000))
            XCTAssertEqual(restored.x, input.x, accuracy: 0.000001)
            XCTAssertEqual(restored.y, input.y, accuracy: 0.000001)
        }
    }
}
