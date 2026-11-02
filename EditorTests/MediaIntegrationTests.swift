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
        let grade = BasicGrade(exposure: 0.4, saturation: 15)
        let preview = try MediaIO.photoPreview(url: source, grade: grade)
        XCTAssertEqual(Int(preview.size.width), 1536)
        try MediaIO.exportPhoto(url: source, to: output, grade: grade)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(image), 1)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1536)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 2048)
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
        let grade = BasicGrade(exposure: 0.25, saturation: 12)
        let item = try await MediaIO.videoItem(url: source, grade: grade)
        XCTAssertNotNil(item.videoComposition)
        let generator = AVAssetImageGenerator(asset: input)
        generator.videoComposition = item.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 128, height: 128)
        let previewFrame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertGreaterThan(previewFrame.height, previewFrame.width)
        try await MediaIO.exportVideo(url: source, to: output, grade: grade)
        let exported = AVURLAsset(url: output)
        let outputTracks = try await exported.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(outputTracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = CGRect(origin: .zero, size: size).applying(transform).standardized
        XCTAssertGreaterThan(display.height, display.width)
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
        let outputFrame = try await outputGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let difference = meanRGBDifference(previewFrame, outputFrame)
        print("GX011247 preview/export mean RGB difference: \(difference)")
        XCTAssertLessThan(difference, 0.15)
        let outputAudio = try await exported.loadTracks(withMediaType: .audio)
        XCTAssertFalse(outputAudio.isEmpty)
        XCTAssertEqual(try checksum(source), before)
    }

    func testVisionForegroundTrial() throws {
        for name in ["P8110319.JPG", "B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG"] {
            let source = fixtures.appendingPathComponent("test_media/photos/" + name)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try VNImageRequestHandler(url: source).perform([request])
            let observation = request.results?.first
            print("Vision \(name): \(observation?.allInstances.count ?? 0) instances")
        }
    }
}
