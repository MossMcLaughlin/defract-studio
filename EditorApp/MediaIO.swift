import Foundation
import AppKit
import CoreImage
import ImageIO
import AVFoundation
import EditorCore

enum MediaIO {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    static let v2Context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .workingFormat: CIFormat.RGBAh
    ])

    static func context(for recipe: EditRecipe) -> CIContext {
        RenderPlan(recipe: recipe).workingSpace == .legacySRGB ? context : v2Context
    }

    private static func validateInterpretation(_ recipe: EditRecipe) throws {
        guard (recipe.rendererVersion ?? 1) == 2 else { return }
        if recipe.sourceColor?.dynamicRange == .hlg || recipe.sourceColor?.dynamicRange == .pq {
            throw NSError(domain: "Editor", code: 15, userInfo: [NSLocalizedDescriptionKey:
                "HDR color conversion is not yet verified for this editor. The source was not graded or exported."])
        }
    }
    static let thumbnailCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 6
        return cache
    }()

    static func sourceColorDescriptor(url: URL, kind: MediaKind) async throws -> SourceColorDescriptor {
        if kind == .photo { return try photoSourceColorDescriptor(url: url) }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let format = try await track.load(.formatDescriptions).first else {
            throw NSError(domain: "Editor", code: 14, userInfo: [NSLocalizedDescriptionKey: "Video color metadata could not be read."])
        }
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        let depth = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int
        let range = extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool
        let dynamicRange: SourceColorDescriptor.DynamicRange
        if transfer?.localizedCaseInsensitiveContains("HLG") == true { dynamicRange = .hlg }
        else if transfer?.localizedCaseInsensitiveContains("PQ") == true || transfer?.localizedCaseInsensitiveContains("2084") == true { dynamicRange = .pq }
        else if transfer != nil { dynamicRange = .sdr }
        else { dynamicRange = .unknown }
        return SourceColorDescriptor(sourceBitDepth: depth, primaries: primaries, transfer: transfer,
                                     matrix: matrix, fullRange: range, dynamicRange: dynamicRange,
                                     evidence: "CoreMedia format description")
    }

    static func photoSourceColorDescriptor(url: URL) throws -> SourceColorDescriptor {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw NSError(domain: "Editor", code: 13, userInfo: [NSLocalizedDescriptionKey: "Photo color metadata could not be read."])
        }
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        let profile = image?.colorSpace.flatMap { space -> String? in
            if let name = space.name { return name as String }
            return space.copyICCData() != nil ? "embedded ICC" : nil
        }
        let depth = properties[kCGImagePropertyDepth as String] as? Int
        return SourceColorDescriptor(sourceBitDepth: depth, profile: profile,
                                     dynamicRange: .sdr,
                                     orientation: properties[kCGImagePropertyOrientation as String] as? Int,
                                     evidence: profile == nil ? "ImageIO; untagged SDR assumption" : "ImageIO embedded color space")
    }

    static func photoImage(url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw NSError(domain: "Editor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image could not be decoded."])
        }
        return image
    }

    static func thumbnailCGImage(url: URL, kind: MediaKind) async -> CGImage? {
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 120)
            return try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160
        ] as CFDictionary)
    }

    static func photoPreview(url: URL, recipe: EditRecipe, selectedMaskID: UUID? = nil) throws -> NSImage {
        let cg = try photoPreviewCGImage(url: url, recipe: recipe, selectedMaskID: selectedMaskID)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func photoPreviewCGImage(url: URL, recipe: EditRecipe, selectedMaskID: UUID? = nil, maxPixelSize: Int = 1800) throws -> CGImage {
        try validateInterpretation(recipe)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path):\(modified):\(maxPixelSize)" as NSString
        let sourceImage: CIImage
        if let cached = thumbnailCache.object(forKey: key) {
            sourceImage = cached
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                  ] as CFDictionary) else {
                throw NSError(domain: "Editor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image preview could not be decoded."])
            }
            sourceImage = CIImage(cgImage: thumbnail)
            thumbnailCache.setObject(sourceImage, forKey: key)
        }
        let plan = RenderPlan(recipe: recipe)
        let graded = plan.grade(sourceImage)
        let cropped = plan.applyGeometry(overlay(graded, recipe: recipe, selectedMaskID: selectedMaskID))
        var previewFrame = recipe.outputFrame
        if var frame = previewFrame, max(frame.width, frame.height) > maxPixelSize {
            let scale = Double(maxPixelSize) / Double(max(frame.width, frame.height))
            frame.width = max(1, Int((Double(frame.width) * scale).rounded()))
            frame.height = max(1, Int((Double(frame.height) * scale).rounded()))
            previewFrame = frame
        }
        let rendered = CoreRenderer.applyOutputFrame(cropped, frame: previewFrame)
        let cg = (recipe.rendererVersion ?? 1) == 1
            ? context.createCGImage(rendered, from: rendered.extent)
            : v2Context.createCGImage(rendered, from: rendered.extent, format: .RGBA8,
                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        guard let cg else {
            throw NSError(domain: "Editor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Image could not be rendered."])
        }
        return cg
    }

    static func exportPhoto(url: URL, to destination: URL, recipe: EditRecipe,
                            format: PhotoFormat = .jpeg, quality: Double = 0.9, overwrite: Bool = false) throws {
        try validateInterpretation(recipe)
        guard url.standardizedFileURL != destination.standardizedFileURL else {
            throw NSError(domain: "Editor", code: 9, userInfo: [NSLocalizedDescriptionKey: "The export destination is the original file."])
        }
        let plan = RenderPlan(recipe: recipe)
        let cropped = plan.applyGeometry(plan.grade(try photoImage(url: url)))
        let rendered = plan.applyOutputFrame(cropped)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = context(for: recipe).createCGImage(rendered, from: rendered.extent, format: .RGBA8, colorSpace: colorSpace),
              let output = CGImageDestinationCreateWithURL(temporary as CFURL, format.imageIOType as CFString, 1, nil) else {
            throw NSError(domain: "Editor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Photo export could not start."])
        }
        let properties: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary : nil
        CGImageDestinationAddImage(output, cg, properties)
        guard CGImageDestinationFinalize(output) else {
            throw NSError(domain: "Editor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Photo export failed."])
        }
        guard CGImageSourceCreateWithURL(temporary as CFURL, nil) != nil else {
            throw NSError(domain: "Editor", code: 10, userInfo: [NSLocalizedDescriptionKey: "Photo output could not be reopened."])
        }
        if Task.isCancelled { throw CancellationError() }
        try commit(temporary, destination: destination, original: url, overwrite: overwrite)
    }

    private static func overlay(_ image: CIImage, recipe: EditRecipe, selectedMaskID: UUID?) -> CIImage {
        guard let selectedMaskID, let mask = recipe.masks.first(where: { $0.id == selectedMaskID }) else { return image }
        let alpha = MaskRenderer.alphaImage(for: mask, extent: image.extent)
        let tint = CIImage(color: CIColor(red: 0.95, green: 0.22, blue: 0.36, alpha: 1)).cropped(to: image.extent)
        let tinted = tint.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, "inputMaskImage": alpha])
        return tinted.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: image, kCIInputTimeKey: 0.4])
    }

    static func videoComposition(asset: AVURLAsset, recipe: EditRecipe, selectedMaskID: UUID? = nil) async throws -> AVVideoComposition {
        try validateInterpretation(recipe)
        let plan = RenderPlan(recipe: recipe)
        let renderContext = context(for: recipe)
        return try await withCheckedThrowingContinuation { continuation in
            AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                let graded = plan.grade(request.sourceImage)
                let framed = plan.applyGeometry(overlay(graded, recipe: recipe, selectedMaskID: selectedMaskID))
                request.finish(with: plan.applyOutputFrame(framed), context: renderContext)
            }, completionHandler: { composition, error in
                if let composition {
                    let output = recipe.outputFrame.map { CGSize(width: $0.width, height: $0.height) }
                        ?? recipe.geometry.outputSize(for: composition.renderSize)
                    composition.renderSize = CGSize(width: 2 * floor(output.width / 2), height: 2 * floor(output.height / 2))
                    continuation.resume(returning: composition)
                }
                else { continuation.resume(throwing: error ?? NSError(domain: "Editor", code: 5)) }
            })
        }
    }

    @MainActor static func videoItem(url: URL, recipe: EditRecipe, selectedMaskID: UUID? = nil) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = try await videoComposition(asset: asset, recipe: recipe, selectedMaskID: selectedMaskID)
        if let end = recipe.videoTrim.endSeconds { item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }
        return item
    }

    static func exportVideo(url: URL, to destination: URL, recipe: EditRecipe,
                            overwrite: Bool = false, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard url.standardizedFileURL != destination.standardizedFileURL else {
            throw NSError(domain: "Editor", code: 9, userInfo: [NSLocalizedDescriptionKey: "The export destination is the original file."])
        }
        let asset = AVURLAsset(url: url)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let preset = recipe.videoCodec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "Editor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Video export is unavailable."])
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw NSError(domain: "Editor", code: 8, userInfo: [NSLocalizedDescriptionKey: "The selected codec cannot export MP4 on this Mac."])
        }
        session.videoComposition = try await videoComposition(asset: asset, recipe: recipe)
        let assetDuration = try await asset.load(.duration).seconds
        let start = max(0, min(recipe.videoTrim.startSeconds, assetDuration))
        let end = max(0, min(recipe.videoTrim.endSeconds ?? assetDuration, assetDuration))
        guard end - start > 0.04 else {
            throw NSError(domain: "Editor", code: 7, userInfo: [NSLocalizedDescriptionKey: "Trim must leave at least one video frame."])
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
        let monitor = Task.detached {
            while !Task.isCancelled {
                progress?(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: temporary, as: .mp4)
        if Task.isCancelled { throw CancellationError() }
        let output = AVURLAsset(url: temporary)
        let outputVideo = try await output.loadTracks(withMediaType: .video)
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        guard !outputVideo.isEmpty, sourceAudio.isEmpty || !outputAudio.isEmpty else {
            throw NSError(domain: "Editor", code: 11, userInfo: [NSLocalizedDescriptionKey: "Video output is missing picture or source audio."])
        }
        try commit(temporary, destination: destination, original: url, overwrite: overwrite)
        progress?(1)
    }

    private static func commit(_ temporary: URL, destination: URL, original: URL, overwrite: Bool) throws {
        guard destination.standardizedFileURL != original.standardizedFileURL else {
            throw NSError(domain: "Editor", code: 9, userInfo: [NSLocalizedDescriptionKey: "The export destination is the original file."])
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            guard overwrite else {
                throw NSError(domain: "Editor", code: 12, userInfo: [NSLocalizedDescriptionKey: "Output already exists. Choose another name or confirm replacement."])
            }
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
}
