import Foundation
import AppKit
import CoreImage
import ImageIO
import AVFoundation
import EditorCore

enum MediaIO {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    static let thumbnailCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 6
        return cache
    }()

    static func photoImage(url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw NSError(domain: "Editor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image could not be decoded."])
        }
        return image
    }

    static func photoPreview(url: URL, adjustment: AdjustmentVector, geometry: Geometry = Geometry()) throws -> NSImage {
        let cg = try photoPreviewCGImage(url: url, adjustment: adjustment, geometry: geometry)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func photoPreviewCGImage(url: URL, adjustment: AdjustmentVector, geometry: Geometry = Geometry()) throws -> CGImage {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path):\(modified)" as NSString
        let sourceImage: CIImage
        if let cached = thumbnailCache.object(forKey: key) {
            sourceImage = cached
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800
                  ] as CFDictionary) else {
                throw NSError(domain: "Editor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image preview could not be decoded."])
            }
            sourceImage = CIImage(cgImage: thumbnail)
            thumbnailCache.setObject(sourceImage, forKey: key)
        }
        let rendered = CoreRenderer.applyGeometry(CoreRenderer.render(sourceImage, adjustment: adjustment), geometry: geometry)
        guard let cg = context.createCGImage(rendered, from: rendered.extent) else {
            throw NSError(domain: "Editor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Image could not be rendered."])
        }
        return cg
    }

    static func exportPhoto(url: URL, to destination: URL, adjustment: AdjustmentVector, geometry: Geometry = Geometry()) throws {
        let rendered = CoreRenderer.applyGeometry(CoreRenderer.render(try photoImage(url: url), adjustment: adjustment), geometry: geometry)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = context.createCGImage(rendered, from: rendered.extent, format: .RGBA8, colorSpace: colorSpace),
              let output = CGImageDestinationCreateWithURL(temporary as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "Editor", code: 3, userInfo: [NSLocalizedDescriptionKey: "JPEG export could not start."])
        }
        CGImageDestinationAddImage(output, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw NSError(domain: "Editor", code: 4, userInfo: [NSLocalizedDescriptionKey: "JPEG export failed."])
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func videoComposition(asset: AVURLAsset, adjustment: AdjustmentVector) async throws -> AVVideoComposition {
        try await withCheckedThrowingContinuation { continuation in
            AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                request.finish(with: CoreRenderer.render(request.sourceImage, adjustment: adjustment), context: context)
            }, completionHandler: { composition, error in
                if let composition { continuation.resume(returning: composition) }
                else { continuation.resume(throwing: error ?? NSError(domain: "Editor", code: 5)) }
            })
        }
    }

    @MainActor static func videoItem(url: URL, adjustment: AdjustmentVector) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = try await videoComposition(asset: asset, adjustment: adjustment)
        return item
    }

    static func exportVideo(url: URL, to destination: URL, adjustment: AdjustmentVector) async throws {
        let asset = AVURLAsset(url: url)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Editor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Video export is unavailable."])
        }
        session.videoComposition = try await videoComposition(asset: asset, adjustment: adjustment)
        try await session.export(to: temporary, as: .mp4)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
