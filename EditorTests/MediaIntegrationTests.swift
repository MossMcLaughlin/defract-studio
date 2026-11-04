import XCTest
import AVFoundation
import ImageIO
import CryptoKit
import Vision
import AppKit
import EditorCore

final class MediaIntegrationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func checksum(_ url: URL) throws -> SHA256.Digest {
        SHA256.hash(data: try Data(contentsOf: url))
    }

    private func decodedTenBitLuma(_ asset: AVURLAsset, track: AVAssetTrack) throws -> [UInt16] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        ])
        reader.add(output)
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "10-bit frame could not be decoded"])
        }
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) / 2
        let plane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt16.self)
        var codes: [UInt16] = []
        for y in stride(from: height / 8, to: height * 7 / 8, by: max(1, height / 48)) {
            for x in stride(from: width / 8, to: width * 7 / 8, by: max(1, width / 48)) {
                codes.append(plane[y * rowStride + x] >> 6)
            }
        }
        return codes
    }

    private func meanRGBDifference(_ first: CGImage, _ second: CGImage) -> Double {
        let a = NSBitmapImageRep(cgImage: first)
        let b = NSBitmapImageRep(cgImage: second)
        var total = 0.0
        for y in 1...8 {
            for x in 1...8 {
                let ca = a.colorAt(x: x * (a.pixelsWide - 1) / 9, y: y * (a.pixelsHigh - 1) / 9)!.usingColorSpace(.deviceRGB)!
                let cb = b.colorAt(x: x * (b.pixelsWide - 1) / 9, y: y * (b.pixelsHigh - 1) / 9)!.usingColorSpace(.deviceRGB)!
                total += abs(ca.redComponent - cb.redComponent)
                    + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent)
            }
        }
        return total / (64 * 3)
    }

    func testRenderOnlyTimingSmoke() async throws {
        let url = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let source = CIImage(cgImage: frame)
        let destination = CGColorSpace(name: CGColorSpace.sRGB)!
        var recipe = EditRecipe(sourcePath: url.path, kind: .video)
        recipe.color = ColorState()
        recipe.color.setEasy { $0.waterColor = 50; $0.colorRecovery = 40 }
        recipe.color.setEffective(.exposure, to: 0.25)
        var mask = EditMask(name: "Water", kind: .radial)
        mask.adjustment[.exposure] = 0.3
        recipe.masks = [mask]
        let context = MediaIO.context(for: recipe)
        func measure(_ label: String, recipe: EditRecipe) {
            var times: [Double] = []
            for iteration in 0..<8 {
                let start = CFAbsoluteTimeGetCurrent()
                let plan = RenderPlan(recipe: recipe)
                let output = plan.applyOutputFrame(plan.grade(source))
                let rendered = plan.version >= 6 ? CoreRenderer.ditherV6(output, bits: 10, video: true) : output
                let result = context.createCGImage(rendered, from: rendered.extent, format: .RGBA8, colorSpace: destination)
                XCTAssertNotNil(result)
                if iteration >= 2 { times.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
            }
            let sorted = times.sorted()
            print("CP6_RENDER \(label) \(frame.width)x\(frame.height) iterations=\(sorted.count) median_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted.last!)")
        }
        recipe.schemaVersion = 3
        recipe.rendererVersion = 3
        measure("v3", recipe: recipe)
        recipe.schemaVersion = 4
        recipe.rendererVersion = 4
        measure("v4_no_analysis", recipe: recipe)
        let identity = try SourceNoiseAnalysis.identity(recipe: recipe, url: url)
        recipe.noiseAnalysis = NoiseAnalysis(identity: identity, chromaSigma: 0.015, luminanceSigma: 0.012,
                                            confidence: 1, validTiles: 16, frameCount: 3)
        measure("v4_auto", recipe: recipe)
        recipe.detail.autoProtection = false
        recipe.detail.colorNoise = 60
        recipe.detail.luminanceNoise = 25
        measure("v4_manual", recipe: recipe)
        recipe.schemaVersion = 5
        recipe.rendererVersion = 5
        recipe.color = ColorState(mappingVersion: 2)
        recipe.color.setEasy { $0.waterColor = 50; $0.colorRecovery = 40 }
        recipe.color.setEffective(.exposure, to: 0.25)
        recipe.detail.autoProtection = true
        recipe.detail.colorNoise = 0
        recipe.detail.luminanceNoise = 0
        let v5Identity = try SourceNoiseAnalysis.identity(recipe: recipe, url: url)
        recipe.noiseAnalysis = NoiseAnalysis(identity: v5Identity, chromaSigma: 0.015, luminanceSigma: 0.012,
                                            confidence: 1, validTiles: 16, frameCount: 3,
                                            water: WaterAnalysis(red: 0.12, green: 0.25, blue: 0.34,
                                                                 confidence: 0.8, samples: 150, frameCount: 3))
        measure("v5_neutral", recipe: recipe)
        recipe.color.setEasy { $0.visibility = 50 }
        measure("v5_mild", recipe: recipe)
        recipe.color.setEasy { $0.visibility = 0 }
        recipe.color.setEffective(.clarity, to: 60)
        recipe.color.setEffective(.dehaze, to: 50)
        measure("v5_strong", recipe: recipe)
        recipe.detail.autoProtection = false
        recipe.detail.colorNoise = 60
        recipe.detail.luminanceNoise = 25
        measure("v5_combined_noise", recipe: recipe)
        recipe.schemaVersion = 6
        recipe.rendererVersion = 6
        recipe.color.setEffective(.clarity, to: 0)
        recipe.color.setEffective(.dehaze, to: 0)
        recipe.detail.autoProtection = true
        recipe.detail.colorNoise = 0
        recipe.detail.luminanceNoise = 0
        measure("v6_neutral_output", recipe: recipe)
        recipe.detail.sharpening = 60
        measure("v6_sharpened_output", recipe: recipe)
        recipe.detail.sharpening = 0
        recipe.color.setEasy { $0.visibility = 50 }
        measure("v6_visibility", recipe: recipe)
        recipe.color.setEasy { $0.visibility = 0 }
        recipe.color.setEffective(.clarity, to: 60)
        recipe.color.setEffective(.dehaze, to: 50)
        recipe.detail.autoProtection = false
        recipe.detail.colorNoise = 60
        recipe.detail.luminanceNoise = 25
        recipe.detail.sharpening = 60
        measure("v6_demanding", recipe: recipe)
        recipe.noiseAnalysis = nil
        recipe.detail = TechnicalDetail()
        recipe.schemaVersion = 5
        recipe.rendererVersion = 5
        measure("v5_no_analysis", recipe: recipe)
        recipe.schemaVersion = 6
        recipe.rendererVersion = 6
        measure("v6_no_analysis_output", recipe: recipe)
        recipe.detail.sharpening = 60
        measure("v6_no_analysis_sharpened", recipe: recipe)
    }

    func testSourceColorDescriptorsUseMediaMetadata() async throws {
        let tenBit = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let eightBit = fixtures.appendingPathComponent("test_media/videos/GX011123.MP4")
        let photo = fixtures.appendingPathComponent("test_media/photos/P8110319.JPG")
        let high = try await MediaIO.sourceColorDescriptor(url: tenBit, kind: .video)
        let standard = try await MediaIO.sourceColorDescriptor(url: eightBit, kind: .video)
        let still = try await MediaIO.sourceColorDescriptor(url: photo, kind: .photo)
        XCTAssertEqual(high.sourceBitDepth, 10)
        XCTAssertEqual(standard.sourceBitDepth, 8)
        XCTAssertEqual(high.dynamicRange, .sdr)
        XCTAssertEqual(standard.dynamicRange, .sdr)
        XCTAssertNotNil(high.primaries)
        XCTAssertNotNil(still.profile)
    }

    func testV6PhotoSRGBConversionAndEncodedDither() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let p3Image = CIImage(bitmapData: [Float](repeating: 0.0, count: 32 * 32 * 4)
            .enumerated().map { index, _ in [Float(0.83), 0.27, 0.12, 1][index % 4] }
            .withUnsafeBytes { Data($0) }, bytesPerRow: 32 * 16,
            size: CGSize(width: 32, height: 32), format: .RGBAf, colorSpace: p3)
        let p3Source = folder.appendingPathComponent("p3.png")
        try MediaIO.v2Context.writePNGRepresentation(of: p3Image, to: p3Source, format: .RGBA16,
                                                     colorSpace: p3)
        let expectedSource = try MediaIO.photoImage(url: p3Source)
        let expected = try XCTUnwrap(MediaIO.v2Context.createCGImage(expectedSource, from: expectedSource.extent,
                                                                     format: .RGBA8, colorSpace: srgb))
        var recipe = EditRecipe(sourcePath: p3Source.path, kind: .photo)
        let p3Output = folder.appendingPathComponent("p3-out.png")
        try MediaIO.exportPhoto(url: p3Source, to: p3Output, recipe: recipe, format: .png)
        let p3Export = try XCTUnwrap(CGImageSourceCreateWithURL(p3Output as CFURL, nil))
        let actual = try XCTUnwrap(CGImageSourceCreateImageAtIndex(p3Export, 0, nil))
        XCTAssertEqual(actual.colorSpace?.name, srgb.name)
        XCTAssertLessThan(meanRGBDifference(expected, actual), 0.008)

        let halfCode = (120.5 / 255 + 0.055) / 1.055
        let linear = Float(pow(halfCode, 2.4))
        let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let ramp = CIImage(bitmapData: [Float](repeating: 0.0, count: 256 * 128 * 4)
            .enumerated().map { index, _ in index % 4 == 3 ? 1 : linear }
            .withUnsafeBytes { Data($0) }, bytesPerRow: 256 * 16,
            size: CGSize(width: 256, height: 128), format: .RGBAf, colorSpace: linearSpace)
        let rampSource = folder.appendingPathComponent("ramp16.png")
        try MediaIO.v2Context.writePNGRepresentation(of: ramp, to: rampSource, format: .RGBA16,
                                                     colorSpace: srgb)
        recipe.sourcePath = rampSource.path
        let dithered = folder.appendingPathComponent("ramp-v6.png")
        try MediaIO.exportPhoto(url: rampSource, to: dithered, recipe: recipe, format: .png)
        recipe.schemaVersion = 5; recipe.rendererVersion = 5
        let legacy = folder.appendingPathComponent("ramp-v5.png")
        try MediaIO.exportPhoto(url: rampSource, to: legacy, recipe: recipe, format: .png)
        func codes(_ url: URL) throws -> Set<UInt8> {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.bitsPerComponent, 8)
            let bytes = Array(try XCTUnwrap(image.dataProvider?.data) as Data)
            return Set(stride(from: 1, to: bytes.count, by: max(1, image.bitsPerPixel / 8)).map { bytes[$0] })
        }
        let legacyCodes = try codes(legacy), ditherCodes = try codes(dithered)
        print("CP6_PNG_DITHER legacy_codes=\(legacyCodes.sorted()) v6_codes=\(ditherCodes.sorted())")
        XCTAssertGreaterThan(ditherCodes.count, legacyCodes.count)
    }

    func testSourceNoiseAnalysisOnSuppliedPhotoAndGoPro() async throws {
        for (path, kind) in [("test_media/photos/P8110319.JPG", MediaKind.photo),
                             ("test_media/photos/P7310233.JPG", MediaKind.photo),
                             ("test_media/videos/GX011247.MP4", MediaKind.video)] {
            let url = fixtures.appendingPathComponent(path)
            var recipe = EditRecipe(sourcePath: url.path, kind: kind)
            recipe.sourceColor = try await MediaIO.sourceColorDescriptor(url: url, kind: kind)
            let identity = try SourceNoiseAnalysis.identity(recipe: recipe, url: url)
            let result = try await SourceNoiseAnalysis.analyze(url: url, recipe: recipe, identity: identity)
            XCTAssertEqual(result.identity, identity)
            XCTAssertEqual(result.frameCount, kind == .photo ? 1 : 3)
            XCTAssertGreaterThanOrEqual(result.validTiles, 5)
            XCTAssertGreaterThan(result.confidence, 0)
            XCTAssertTrue(result.chromaSigma.isFinite && result.luminanceSigma.isFinite)
            XCTAssertTrue((0...1).contains(result.confidence))
            print("CP4_ANALYSIS \(path) chroma=\(result.chromaSigma) luma=\(result.luminanceSigma) confidence=\(result.confidence) tiles=\(result.validTiles) frames=\(result.frameCount)")
            print("CP5_WATER \(path) rgb=\(String(describing: result.water.map { [$0.red, $0.green, $0.blue] })) confidence=\(result.water?.confidence ?? 0) samples=\(result.water?.samples ?? 0) frames=\(result.water?.frameCount ?? 0)")
        }
    }

    @MainActor func testImportedPhotoAndVideoInterpretationPersists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder)
        let model = EditorModel(store: store)
        let photo = fixtures.appendingPathComponent("test_media/photos/P8110319.JPG")
        let video = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        model.importURLs([photo, video])
        let photoRecipe = try XCTUnwrap(model.items.first { $0.current.sourcePath == photo.path }?.current)
        XCTAssertEqual(photoRecipe.rendererVersion, 6)
        XCTAssertEqual(photoRecipe.sourceColor?.dynamicRange, .sdr)
        for _ in 0..<50 {
            if model.items.first(where: { $0.current.sourcePath == video.path })?.current.sourceColor != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let videoRecipe = try XCTUnwrap(model.items.first { $0.current.sourcePath == video.path }?.current)
        XCTAssertEqual(videoRecipe.rendererVersion, 6)
        XCTAssertEqual(videoRecipe.sourceColor?.sourceBitDepth, 10)
        XCTAssertEqual(videoRecipe.sourceColor?.dynamicRange, .sdr)
        for _ in 0..<80 {
            if model.items.first(where: { $0.current.id == videoRecipe.id })?.current.noiseAnalysis != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let analyzedVideo = try XCTUnwrap(model.items.first(where: { $0.current.id == videoRecipe.id })?.current.noiseAnalysis)
        XCTAssertEqual(analyzedVideo.frameCount, 3)
        model.select(photoRecipe.id)
        for _ in 0..<80 {
            if model.items.first(where: { $0.current.id == photoRecipe.id })?.current.noiseAnalysis != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let analyzedPhoto = try XCTUnwrap(model.items.first(where: { $0.current.id == photoRecipe.id })?.current.noiseAnalysis)
        XCTAssertEqual(analyzedPhoto.frameCount, 1)
        let project = folder.appendingPathComponent("Sources.defractproject")
        try model.saveProject(to: project)
        let reopened = EditorModel(store: store)
        reopened.openProject(project)
        XCTAssertEqual(reopened.items.first { $0.current.id == photoRecipe.id }?.current.sourceColor, photoRecipe.sourceColor)
        XCTAssertEqual(reopened.items.first { $0.current.id == videoRecipe.id }?.current.sourceColor, videoRecipe.sourceColor)
        XCTAssertEqual(reopened.items.first { $0.current.id == photoRecipe.id }?.current.noiseAnalysis, analyzedPhoto)
        XCTAssertEqual(reopened.items.first { $0.current.id == videoRecipe.id }?.current.noiseAnalysis, analyzedVideo)
    }

    func testNeutralV2PhotoMatchesLegacySDRBaseline() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/P8110319.JPG")
        var current = EditRecipe(sourcePath: source.path, kind: .photo)
        current.schemaVersion = 2
        current.rendererVersion = 2
        var legacy = current
        legacy.schemaVersion = 1
        legacy.rendererVersion = nil
        let v2 = try MediaIO.photoPreviewCGImage(url: source, recipe: current)
        let v1 = try MediaIO.photoPreviewCGImage(url: source, recipe: legacy)
        XCTAssertEqual(v2.width, v1.width)
        XCTAssertEqual(v2.height, v1.height)
        // V1's untagged device-RGB preview and V2's tagged sRGB preview can
        // display-convert differently; compare their encoded pixel codes here.
        let a = NSBitmapImageRep(cgImage: v1)
        let b = NSBitmapImageRep(cgImage: v2)
        var difference = 0.0
        for y in 1...8 {
            for x in 1...8 {
                let first = try XCTUnwrap(a.colorAt(x: x * (a.pixelsWide - 1) / 9, y: y * (a.pixelsHigh - 1) / 9))
                let second = try XCTUnwrap(b.colorAt(x: x * (b.pixelsWide - 1) / 9, y: y * (b.pixelsHigh - 1) / 9))
                difference += abs(first.redComponent - second.redComponent)
                    + abs(first.greenComponent - second.greenComponent)
                    + abs(first.blueComponent - second.blueComponent)
            }
        }
        XCTAssertLessThan(difference / (64 * 3), 0.001)
    }

    func testPhotoGradeAndExportPreserveOriginal() async throws {
        let source = fixtures.appendingPathComponent("test_media/photos/P8110319.JPG")
        let before = try checksum(source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: output) }
        var color = ColorState(mappingVersion: 2)
        color.setEasy { $0.waterColor = 50; $0.colorRecovery = 40; $0.light = 20; $0.visibility = 40 }
        color.setEffective(.aquaHue, to: 20)
        var recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        recipe.color = color
        recipe.detail.sharpening = 30
        let photoIdentity = try SourceNoiseAnalysis.identity(recipe: recipe, url: source)
        recipe.noiseAnalysis = try await SourceNoiseAnalysis.analyze(url: source, recipe: recipe, identity: photoIdentity)
        recipe.geometry.aspect = .fourFive
        let preview = try MediaIO.photoPreview(url: source, recipe: recipe)
        XCTAssertEqual(Int(preview.size.width), 1350)
        try MediaIO.exportPhoto(url: source, to: output, recipe: recipe)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(image), 1)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1536)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 1920)
        let previewCG = try XCTUnwrap(preview.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let exportedCG = try XCTUnwrap(CGImageSourceCreateImageAtIndex(image, 0, nil))
        XCTAssertLessThan(meanRGBDifference(previewCG, exportedCG), 0.12)
        XCTAssertEqual(try checksum(source), before)
    }

    func testExportOptionsPNGOverwriteAndValidation() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/IMG_3635.jpeg")
        let before = try checksum(source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        var options = ExportOptions(recipe: recipe, sourceSize: CGSize(width: 1536, height: 2048))
        options.folder = folder
        options.preset = .instagram
        options.aspect = .fourFive
        options.updateSuggestedSize(sourceSize: CGSize(width: 1536, height: 2048), kind: .photo)
        XCTAssertEqual([options.width, options.height], [1080, 1350])
        options.photoFormat = .png
        let output = try options.destination(kind: .photo)
        recipe.outputFrame = options.outputFrame
        try MediaIO.exportPhoto(url: source, to: output, recipe: recipe, format: .png)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1080)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 1350)
        let first = try checksum(output)
        XCTAssertThrowsError(try MediaIO.exportPhoto(url: source, to: output, recipe: recipe, format: .png))
        XCTAssertEqual(try checksum(output), first)
        recipe.color.setEffective(.exposure, to: 0.3)
        try MediaIO.exportPhoto(url: source, to: output, recipe: recipe, format: .png, overwrite: true)
        XCTAssertNotEqual(try checksum(output), first)
        options.name = "../unsafe"
        XCTAssertThrowsError(try options.destination(kind: .photo))
        XCTAssertEqual(try checksum(source), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [output.lastPathComponent])
    }

    func testReefPNGPortraitAndAlphaExport() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/image.png")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Optional local reef PNG fixture is absent")
        }
        let before = try checksum(source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        let recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        let preview = try MediaIO.photoPreviewCGImage(url: source, recipe: recipe)
        XCTAssertEqual(preview.width, 638)
        XCTAssertEqual(preview.height, 1130)
        try MediaIO.exportPhoto(url: source, to: output, recipe: recipe, format: .png)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let rendered = try XCTUnwrap(CGImageSourceCreateImageAtIndex(image, 0, nil))
        XCTAssertEqual(rendered.width, 638)
        XCTAssertEqual(rendered.height, 1130)
        XCTAssertNotEqual(rendered.alphaInfo, .none)
        XCTAssertEqual(try checksum(source), before)
    }

    @MainActor func testModelPhotoExportPersistsCompletedState() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder.appendingPathComponent("projects"))
        let source = fixtures.appendingPathComponent("test_media/photos/IMG_3635.jpeg")
        let model = EditorModel(store: store)
        model.importURLs([source])
        model.change { $0.color.setEffective(.exposure, to: 0.4) }
        XCTAssertTrue(model.hasUnexportedEdits)
        var options = ExportOptions(recipe: try XCTUnwrap(model.draft), sourceSize: CGSize(width: 1536, height: 2048))
        options.folder = folder
        options.width = 600
        options.height = 800
        try model.startExport(options, overwrite: false)
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.exportProgress, 1)
        XCTAssertFalse(model.hasUnexportedEdits)
        let output = try XCTUnwrap(model.lastExportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let reopened = EditorModel(store: store)
        XCTAssertFalse(reopened.hasUnexportedEdits)
    }

    func testCancelledVideoExportLeavesNoOutput() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("cancelled.mp4")
        var recipe = EditRecipe(sourcePath: source.path, kind: .video)
        recipe.outputFrame = OutputFrame(width: 1080, height: 1920, mode: .fit)
        let work = Task { try await MediaIO.exportVideo(url: source, to: output, recipe: recipe) }
        try await Task.sleep(for: .milliseconds(100))
        work.cancel()
        do {
            try await work.value
            XCTFail("Export unexpectedly completed after cancellation")
        } catch { XCTAssertTrue(error is CancellationError || (error as NSError).code == NSUserCancelledError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    func testMain10PortraitVideoGradeAndExport() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let before = try checksum(source)
        let input = AVURLAsset(url: source)
        let inputTracks = try await input.loadTracks(withMediaType: .video)
        let inputVideo = try XCTUnwrap(inputTracks.first)
        let inputAudio = try await input.loadTracks(withMediaType: .audio)
        XCTAssertFalse(inputAudio.isEmpty)
        let sourceAudioFormats = try await inputAudio[0].load(.formatDescriptions)
        let sourceAudioFormat = try XCTUnwrap(sourceAudioFormats.first)
        XCTAssertEqual(CMAudioFormatDescriptionGetStreamBasicDescription(sourceAudioFormat)?.pointee.mChannelsPerFrame, 2)
        let inputTransform = try await inputVideo.load(.preferredTransform)
        XCTAssertGreaterThan(abs(inputTransform.b), 0.9)
        let formats = try await inputVideo.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        let codec = CMFormatDescriptionGetMediaSubType(format)
        XCTAssertTrue(codec == 0x68766331 || codec == 0x68657631)
        let sourceMetadata = CMFormatDescriptionGetExtensions(format) as? [String: Any]
        XCTAssertEqual(sourceMetadata?["BitsPerComponent"] as? Int, 10)
        XCTAssertEqual(sourceMetadata?["CVImageBufferColorPrimaries"] as? String, "ITU_R_709_2")
        XCTAssertEqual(sourceMetadata?["CVImageBufferTransferFunction"] as? String, "ITU_R_709_2")
        XCTAssertEqual(sourceMetadata?["CVImageBufferYCbCrMatrix"] as? String, "ITU_R_709_2")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        var recipe = EditRecipe(sourcePath: source.path, kind: .video)
        recipe.color.setEffective(.exposure, to: 0.25)
        recipe.color.setEffective(.saturation, to: 12)
        recipe.color.setEffective(.clarity, to: 25)
        recipe.color.setEffective(.dehaze, to: 20)
        recipe.detail.colorNoise = 60
        recipe.detail.luminanceNoise = 25
        recipe.detail.sharpening = 25
        recipe.videoTrim.startSeconds = 0.3
        recipe.videoTrim.endSeconds = 2.5
        recipe.geometry.aspect = .fourFive
        var gradient = EditMask(name: "Water", kind: .linear)
        gradient.adjustment[.exposure] = 0.3
        recipe.masks.append(gradient)
        let videoIdentity = try SourceNoiseAnalysis.identity(recipe: recipe, url: source)
        recipe.noiseAnalysis = try await SourceNoiseAnalysis.analyze(url: source, recipe: recipe, identity: videoIdentity)
        let item = try await MediaIO.videoItem(url: source, recipe: recipe)
        XCTAssertNotNil(item.videoComposition)
        print("GX011247 composition size: \(String(describing: item.videoComposition?.renderSize))")
        let generator = AVAssetImageGenerator(asset: input)
        generator.videoComposition = item.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 128, height: 128)
        let previewFrame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertGreaterThan(previewFrame.height, previewFrame.width)
        _ = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        let repeatedFrame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertLessThan(meanRGBDifference(previewFrame, repeatedFrame), 0.001)
        try await MediaIO.exportVideo(url: source, to: output, recipe: recipe)
        let exported = AVURLAsset(url: output)
        let outputDuration = try await exported.load(.duration).seconds
        XCTAssertEqual(outputDuration, 2.2, accuracy: 0.12)
        let outputTracks = try await exported.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(outputTracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = CGRect(origin: .zero, size: size).applying(transform).standardized
        XCTAssertGreaterThan(display.height, display.width)
        XCTAssertEqual(display.height / display.width, 1.25, accuracy: 0.03)
        let exportedFormats = try await track.load(.formatDescriptions)
        let exportedFormat = try XCTUnwrap(exportedFormats.first)
        let outputMetadata = CMFormatDescriptionGetExtensions(exportedFormat) as? [String: Any]
        print("CP6_H264 depth=\(String(describing: outputMetadata?["BitsPerComponent"])) fullRange=\(String(describing: outputMetadata?["FullRangeVideo"]))")
        XCTAssertEqual(outputMetadata?["CVImageBufferColorPrimaries"] as? String, "ITU_R_709_2")
        XCTAssertEqual(outputMetadata?["CVImageBufferTransferFunction"] as? String, "ITU_R_709_2")
        XCTAssertEqual(outputMetadata?["CVImageBufferYCbCrMatrix"] as? String, "ITU_R_709_2")
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(exportedFormat), 0x61766331)
        let outputGenerator = AVAssetImageGenerator(asset: exported)
        outputGenerator.appliesPreferredTrackTransform = true
        outputGenerator.maximumSize = CGSize(width: 128, height: 128)
        let outputFrame = try await outputGenerator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
        let difference = meanRGBDifference(previewFrame, outputFrame)
        print("GX011247 preview/export mean RGB difference: \(difference)")
        XCTAssertLessThan(difference, 0.15)
        let outputAudio = try await exported.loadTracks(withMediaType: .audio)
        XCTAssertFalse(outputAudio.isEmpty)
        let outputAudioFormats = try await outputAudio[0].load(.formatDescriptions)
        let outputAudioFormat = try XCTUnwrap(outputAudioFormats.first)
        XCTAssertEqual(CMAudioFormatDescriptionGetStreamBasicDescription(outputAudioFormat)?.pointee.mChannelsPerFrame, 2)
        XCTAssertEqual(try checksum(source), before)
    }

    func testV6NeutralMain10DecodedColorAgainstSource() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let originalHash = try checksum(source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        var recipe = EditRecipe(sourcePath: source.path, kind: .video)
        recipe.videoCodec = .hevc
        recipe.outputFrame = OutputFrame(width: 540, height: 960, mode: .fit)
        recipe.videoTrim.endSeconds = 0.6
        try await MediaIO.exportVideo(url: source, to: output, recipe: recipe)
        let inputGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        inputGenerator.appliesPreferredTrackTransform = true
        inputGenerator.maximumSize = CGSize(width: 256, height: 256)
        let sourceFrame = try await inputGenerator.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
        let outputGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        outputGenerator.appliesPreferredTrackTransform = true
        outputGenerator.maximumSize = CGSize(width: 256, height: 256)
        let exportedFrame = try await outputGenerator.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
        let difference = meanRGBDifference(sourceFrame, exportedFrame)
        print("CP6_NEUTRAL_SOURCE_EXPORT mean_rgb_difference=\(difference)")
        XCTAssertLessThan(difference, 0.05)
        XCTAssertEqual(try checksum(source), originalHash)
    }

    func testVisionForegroundTrial() throws {
        for name in ["P8110319.JPG", "B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG"] {
            let source = fixtures.appendingPathComponent("test_media/photos/" + name)
            let data = try VisionMask.foregroundPNG(url: source)
            XCTAssertGreaterThan(data.count, 1000)
            var mask = EditMask(name: "Subject", kind: .subject)
            mask.mattePNG = data
            mask.strokes.append(BrushStroke(operation: .erase, points: [NormalizedPoint(0.5, 0.5)], size: 0.1, feather: 0.5))
            let restored = try JSONDecoder().decode(EditMask.self, from: JSONEncoder().encode(mask))
            XCTAssertEqual(restored.strokes, mask.strokes)
            XCTAssertEqual(restored.mattePNG, data)
            if name == "P8110319.JPG" {
                var recipe = EditRecipe(sourcePath: source.path, kind: .photo)
                let neutral = try MediaIO.photoPreviewCGImage(url: source, recipe: recipe)
                mask.adjustment[.exposure] = 0.8
                recipe.masks.append(mask)
                let graded = try MediaIO.photoPreviewCGImage(url: source, recipe: recipe)
                XCTAssertGreaterThan(meanRGBDifference(neutral, graded), 0.0005)
            }
            print("Vision \(name): saved \(data.count) bytes of source-aligned matte")
        }
    }

    func testWhiteBalanceControlsChangeRealPhoto() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/IMG_3635.jpeg")
        let recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        let neutral = try MediaIO.photoPreviewCGImage(url: source, recipe: recipe)
        for parameter in [Parameter.temperature, .tint] {
            var editedRecipe = recipe
            editedRecipe.color.setEffective(parameter, to: 50)
            let edited = try MediaIO.photoPreviewCGImage(url: source, recipe: editedRecipe)
            XCTAssertGreaterThan(meanRGBDifference(neutral, edited), 0.001, "\(parameter) had no visible effect")
        }
    }

    func testOpposingGoProRotationsExportUpright() async throws {
        // AVFoundation's preferredTransform.b sign is opposite ffprobe's display-rotation label.
        for (name, expectedSign) in [("GX011123.MP4", -1.0), ("GX011176.MP4", 1.0)] {
            let source = fixtures.appendingPathComponent("test_media/videos/" + name)
            let before = try checksum(source)
            let asset = AVURLAsset(url: source)
            let inputTracks = try await asset.loadTracks(withMediaType: .video)
            let inputTrack = try XCTUnwrap(inputTracks.first)
            let inputTransform = try await inputTrack.load(.preferredTransform)
            XCTAssertEqual(inputTransform.b.sign == .plus ? 1 : -1, Int(expectedSign))
            var recipe = EditRecipe(sourcePath: source.path, kind: .video)
            recipe.color.setEasy { $0.waterColor = 50 }
            recipe.geometry.aspect = .nineSixteen
            var gradient = EditMask(name: "Water", kind: .radial)
            gradient.adjustment[.exposure] = 0.4
            recipe.masks.append(gradient)
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            try await MediaIO.exportVideo(url: source, to: output, recipe: recipe)
            let exported = AVURLAsset(url: output)
            let outputTracks = try await exported.loadTracks(withMediaType: .video)
            let outputTrack = try XCTUnwrap(outputTracks.first)
            let size = try await outputTrack.load(.naturalSize)
            let transform = try await outputTrack.load(.preferredTransform)
            let display = CGRect(origin: .zero, size: size).applying(transform).standardized
            XCTAssertGreaterThan(display.height, display.width, name)
            XCTAssertEqual(display.height / display.width, 16.0 / 9, accuracy: 0.03, name)
            let audio = try await exported.loadTracks(withMediaType: .audio)
            XCTAssertFalse(audio.isEmpty, name)
            XCTAssertEqual(try checksum(source), before)
        }
    }

    @MainActor func testModelBrushStrokeAutosaveUndoAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        let source = fixtures.appendingPathComponent("test_media/photos/P7310233.JPG")
        let model = EditorModel(store: store)
        model.importURLs([source])
        XCTAssertEqual(model.items.count, 1)
        model.addMask(.brush)
        model.updateMask { $0.adjustment[.exposure] = 0.4 }
        model.beginStroke(at: NormalizedPoint(0.4, 0.5))
        model.extendStroke(to: NormalizedPoint(0.5, 0.5))
        model.endStroke()
        XCTAssertEqual(model.items[0].undoStack.count, 3)
        XCTAssertEqual(model.draft?.masks[0].strokes[0].points.count, 2)
        let project = directory.appendingPathComponent("Brush.defractproject")
        try model.saveProject(to: project)
        let reopened = EditorModel(store: store)
        reopened.openProject(project)
        XCTAssertEqual(reopened.draft?.masks[0].strokes[0].points.count, 2)
        XCTAssertEqual(reopened.draft?.masks[0].adjustment[.exposure], 0.4)
        XCTAssertFalse(reopened.canUndo)
        XCTAssertFalse(reopened.canRedo)
    }

    func testVideoQuarterTurnProducesLandscapeOutput() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        var recipe = EditRecipe(sourcePath: source.path, kind: .video)
        recipe.geometry.rotateQuarterTurns = 1
        recipe.videoCodec = .hevc
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        try await MediaIO.exportVideo(url: source, to: output, recipe: recipe)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = CGRect(origin: .zero, size: size).applying(transform).standardized
        XCTAssertGreaterThan(display.width, display.height)
        XCTAssertEqual(display.width / display.height, 16.0 / 9, accuracy: 0.03)
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        let codec = CMFormatDescriptionGetMediaSubType(format)
        XCTAssertTrue(codec == 0x68766331 || codec == 0x68657631)
        let metadata = CMFormatDescriptionGetExtensions(format) as? [String: Any]
        print("CP6_HEVC subtype=\(codec) depth=\(String(describing: metadata?["BitsPerComponent"])) matrix=\(String(describing: metadata?["CVImageBufferYCbCrMatrix"])) fullRange=\(String(describing: metadata?["FullRangeVideo"]))")
        XCTAssertEqual(codec, 0x68766331)
        XCTAssertEqual(metadata?["BitsPerComponent"] as? Int, 10)
        let original = AVURLAsset(url: source)
        let originalTracks = try await original.loadTracks(withMediaType: .video)
        let originalTrack = try XCTUnwrap(originalTracks.first)
        let sourceCodes = try decodedTenBitLuma(original, track: originalTrack)
        let outputCodes = try decodedTenBitLuma(asset, track: track)
        print("CP6_10BIT_CODES source_low_bits=\(Set(sourceCodes.map { $0 & 3 }).count) output_low_bits=\(Set(outputCodes.map { $0 & 3 }).count) output_unique=\(Set(outputCodes).count)")
        XCTAssertGreaterThan(Set(outputCodes.map { $0 & 3 }).count, 1)
        let previewItem = try await MediaIO.videoItem(url: source, recipe: recipe)
        let previewGenerator = AVAssetImageGenerator(asset: original)
        previewGenerator.videoComposition = previewItem.videoComposition
        previewGenerator.appliesPreferredTrackTransform = true
        previewGenerator.maximumSize = CGSize(width: 256, height: 256)
        let previewFrame = try await previewGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let outputGenerator = AVAssetImageGenerator(asset: asset)
        outputGenerator.appliesPreferredTrackTransform = true
        outputGenerator.maximumSize = CGSize(width: 256, height: 256)
        let outputFrame = try await outputGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let decodedDifference = meanRGBDifference(previewFrame, outputFrame)
        print("CP6_HEVC_PREVIEW_EXPORT mean_rgb_difference=\(decodedDifference)")
        XCTAssertLessThan(decodedDifference, 0.05)
        XCTAssertEqual(metadata?["CVImageBufferColorPrimaries"] as? String, "ITU_R_709_2")
        XCTAssertEqual(metadata?["CVImageBufferTransferFunction"] as? String, "ITU_R_709_2")
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)
    }

    func testBrushMaskExportMatchesReloadedPreview() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/P7310233.JPG")
        let before = try checksum(source)
        var recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        recipe.geometry.aspect = .fourFive
        var brush = EditMask(name: "Diver", kind: .brush)
        brush.strokes = [
            BrushStroke(operation: .add, points: [NormalizedPoint(0.45, 0.5), NormalizedPoint(0.55, 0.55)], size: 0.45, feather: 0.3),
            BrushStroke(operation: .erase, points: [NormalizedPoint(0.55, 0.55)], size: 0.08, feather: 0.4)
        ]
        brush.adjustment[.exposure] = 0.8
        brush.adjustment[.aquaHue] = 20
        recipe.masks = [brush]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        try store.save(EditHistory(recipe))
        let restored = try store.load(id: recipe.id).current
        XCTAssertEqual(restored.masks, recipe.masks)
        let preview = try MediaIO.photoPreviewCGImage(url: source, recipe: restored)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: output) }
        try MediaIO.exportPhoto(url: source, to: output, recipe: restored)
        let sourceImage = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
        XCTAssertLessThan(meanRGBDifference(preview, exported), 0.12)
        XCTAssertEqual(try checksum(source), before)
    }

    func testVideoFitAndFillMatchPreviewAtExactSize() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        var frames: [CGImage] = []
        for mode in [FrameMode.fit, .fill] {
            var recipe = EditRecipe(sourcePath: source.path, kind: .video)
            recipe.geometry.aspect = .fourFive
            recipe.outputFrame = OutputFrame(width: 1080, height: 1920, mode: mode)
            recipe.color.setEffective(.exposure, to: 0.3)
            let input = AVURLAsset(url: source)
            let item = try await MediaIO.videoItem(url: source, recipe: recipe)
            let previewGenerator = AVAssetImageGenerator(asset: input)
            previewGenerator.videoComposition = item.videoComposition
            previewGenerator.appliesPreferredTrackTransform = true
            previewGenerator.maximumSize = CGSize(width: 128, height: 128)
            let preview = try await previewGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            try await MediaIO.exportVideo(url: source, to: output, recipe: recipe)
            let exported = AVURLAsset(url: output)
            let tracks = try await exported.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let display = CGRect(origin: .zero, size: size).applying(transform).standardized
            XCTAssertEqual(Int(display.width), 1080)
            XCTAssertEqual(Int(display.height), 1920)
            let outputGenerator = AVAssetImageGenerator(asset: exported)
            outputGenerator.appliesPreferredTrackTransform = true
            outputGenerator.maximumSize = CGSize(width: 128, height: 128)
            let frame = try await outputGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            XCTAssertLessThan(meanRGBDifference(preview, frame), 0.15)
            frames.append(frame)
        }
        XCTAssertGreaterThan(meanRGBDifference(frames[0], frames[1]), 0.01)
    }

    @MainActor func testV6PlaybackPreviewCapKeepsFullExportAndLegacySize() async throws {
        let source = fixtures.appendingPathComponent("test_media/videos/GX011247.MP4")
        let asset = AVURLAsset(url: source)
        var recipe = EditRecipe(sourcePath: source.path, kind: .video)
        recipe.color.setEasy { $0.colorRecovery = 35 }
        recipe.geometry.aspect = .fourFive
        recipe.geometry.rotateQuarterTurns = 1
        var mask = EditMask(name: "Water", kind: .linear)
        mask.adjustment[.exposure] = 0.2
        recipe.masks = [mask]
        let preview = try await MediaIO.videoItem(url: source, recipe: recipe)
        let full = try await MediaIO.videoComposition(asset: asset, recipe: recipe)
        let previewSize = try XCTUnwrap(preview.videoComposition?.renderSize)
        XCTAssertLessThanOrEqual(max(previewSize.width, previewSize.height), 1920)
        XCTAssertGreaterThan(max(full.renderSize.width, full.renderSize.height), 3000)
        XCTAssertEqual(previewSize.width / previewSize.height,
                       full.renderSize.width / full.renderSize.height, accuracy: 0.002)

        func frame(_ composition: AVVideoComposition) async throws -> CGImage {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.videoComposition = composition
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 256, height: 256)
            return try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        }
        let previewFrame = try await frame(try XCTUnwrap(preview.videoComposition))
        let fullFrame = try await frame(full)
        XCTAssertLessThan(meanRGBDifference(previewFrame, fullFrame), 0.06)

        recipe.schemaVersion = 5
        recipe.rendererVersion = 5
        let legacy = try await MediaIO.videoItem(url: source, recipe: recipe)
        XCTAssertEqual(legacy.videoComposition?.renderSize, full.renderSize)
    }

    @MainActor func testProjectSaveNewOpenMissingAndTrash() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder.appendingPathComponent("legacy"))
        let source = fixtures.appendingPathComponent("test_media/photos/P7310233.JPG")
        let original = try checksum(source)
        let project = folder.appendingPathComponent("Dive.defractproject")
        let model = EditorModel(store: store)
        model.importURLs([source])
        model.change { $0.color.setEffective(.exposure, to: 0.4); $0.geometry.aspect = .fourFive }
        model.addMask(.brush)
        for _ in 0..<50 where model.items.first?.current.noiseAnalysis == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let saved = try XCTUnwrap(model.draft)
        let missing = EditRecipe(sourcePath: folder.appendingPathComponent("offline.JPG").path, kind: .photo)
        model.items.append(EditHistory(missing))
        try model.saveProject(to: project)
        XCTAssertFalse(model.projectDirty)
        model.newProject()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertFalse(model.canUndo)
        model.openProject(project)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.visibleItems.count, 1)
        XCTAssertEqual(model.missingSources, ["offline.JPG"])
        XCTAssertEqual(model.draft?.color.effective[.exposure], saved.color.effective[.exposure])
        XCTAssertEqual(model.draft?.masks, saved.masks)
        XCTAssertEqual(model.draft?.geometry, saved.geometry)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(try checksum(source), original)
        try model.moveCurrentProjectToTrash()
        XCTAssertNil(model.projectURL)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.path))
        XCTAssertEqual(try checksum(source), original)
    }

    @MainActor func testMissingProjectDeletionKeepsEditorState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = folder.appendingPathComponent("Moved.defractproject")
        let model = EditorModel(store: ProjectStore(directory: folder.appendingPathComponent("legacy")))
        model.importURLs([fixtures.appendingPathComponent("test_media/photos/P7310233.JPG")])
        try model.saveProject(to: project)
        try FileManager.default.moveItem(at: project, to: folder.appendingPathComponent("Elsewhere.defractproject"))
        XCTAssertThrowsError(try model.moveCurrentProjectToTrash())
        XCTAssertEqual(model.projectURL, project)
        XCTAssertEqual(model.items.count, 1)
    }

    @MainActor func testLegacySessionMigratesOnlyAfterSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(directory: folder.appendingPathComponent("legacy"))
        let source = fixtures.appendingPathComponent("test_media/photos/P7310233.JPG")
        let recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        try store.save(EditHistory(recipe))
        let model = EditorModel(store: store)
        XCTAssertTrue(model.projectDirty)
        XCTAssertEqual(model.selectedID, recipe.id)
        XCTAssertEqual(try store.load(id: recipe.id).current, recipe)
        let project = folder.appendingPathComponent("Recovered.defractproject")
        try model.saveProject(to: project)
        XCTAssertThrowsError(try store.load(id: recipe.id))
        let reopened = EditorModel(store: store)
        XCTAssertTrue(reopened.items.isEmpty)
        reopened.openProject(project)
        XCTAssertEqual(reopened.draft?.id, recipe.id)
        XCTAssertEqual(reopened.draft?.sourcePath, recipe.sourcePath)
    }
}
