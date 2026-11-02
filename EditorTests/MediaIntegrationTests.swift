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

    func testPhotoGradeAndExportPreserveOriginal() throws {
        let source = fixtures.appendingPathComponent("test_media/photos/P8110319.JPG")
        let before = try checksum(source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: output) }
        var color = ColorState()
        color.setEasy { $0.waterColor = 50; $0.colorRecovery = 40; $0.light = 20 }
        color.setEffective(.aquaHue, to: 20)
        var recipe = EditRecipe(sourcePath: source.path, kind: .photo)
        recipe.color = color
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
        recipe.videoTrim.startSeconds = 0.3
        recipe.videoTrim.endSeconds = 2.5
        recipe.geometry.aspect = .fourFive
        var gradient = EditMask(name: "Water", kind: .linear)
        gradient.adjustment[.exposure] = 0.3
        recipe.masks.append(gradient)
        let item = try await MediaIO.videoItem(url: source, recipe: recipe)
        XCTAssertNotNil(item.videoComposition)
        print("GX011247 composition size: \(String(describing: item.videoComposition?.renderSize))")
        let generator = AVAssetImageGenerator(asset: input)
        generator.videoComposition = item.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 128, height: 128)
        let previewFrame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertGreaterThan(previewFrame.height, previewFrame.width)
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
        let reopened = EditorModel(store: store)
        XCTAssertEqual(reopened.draft?.masks[0].strokes[0].points.count, 2)
        XCTAssertEqual(reopened.draft?.masks[0].adjustment[.exposure], 0.4)
        reopened.undo()
        XCTAssertEqual(reopened.draft?.masks[0].strokes.count, 0)
        reopened.redo()
        XCTAssertEqual(reopened.draft?.masks[0].strokes.count, 1)
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
}
