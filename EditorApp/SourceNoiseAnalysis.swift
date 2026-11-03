import Foundation
import CoreImage
import AVFoundation
import EditorCore

enum SourceNoiseAnalysis {
    static func identity(recipe: EditRecipe, url: URL) throws -> NoiseAnalysisIdentity {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            throw CocoaError(.fileReadUnknown)
        }
        return NoiseAnalysisIdentity(recipe: recipe, fileSize: Int64(size),
                                     modificationTime: modified.timeIntervalSince1970)
    }

    static func analyze(url: URL, recipe: EditRecipe, identity: NoiseAnalysisIdentity) async throws -> NoiseAnalysis {
        var tiles: [NoiseEstimator.Tile] = []
        var frameCount = 0
        if recipe.kind == .photo {
            try Task.checkCancellation()
            let source = try MediaIO.photoImage(url: url)
            tiles += try analyzeFrame(source)
            frameCount = 1
        } else {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let start = max(0, min(recipe.videoTrim.startSeconds, duration))
            let end = max(start, min(recipe.videoTrim.endSeconds ?? duration, duration))
            guard end - start > 0.04 else { throw CocoaError(.fileReadCorruptFile) }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            for fraction in [0.15, 0.5, 0.85] {
                try Task.checkCancellation()
                let second = start + (end - start) * fraction
                let image = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image
                tiles += try analyzeFrame(CIImage(cgImage: image))
                frameCount += 1
            }
        }
        try Task.checkCancellation()
        return NoiseEstimator.summarize(tiles, identity: identity, frameCount: frameCount)
    }

    private static func analyzeFrame(_ source: CIImage) throws -> [NoiseEstimator.Tile] {
        let extent = source.extent.integral
        guard extent.width >= 128, extent.height >= 128 else { return [] }
        let scale = min(1, 1024 / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let upright = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let overview = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let context = MediaIO.v2Context
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        pixels.withUnsafeMutableBytes { bytes in
            context.render(overview, toBitmap: bytes.baseAddress!, rowBytes: width * 16,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           format: .RGBAf, colorSpace: space)
        }
        func sample(_ x: Int, _ y: Int) -> (Double, Double) {
            let offset = (min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))) * 4
            let alpha = Double(pixels[offset + 3])
            let luma = 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])
            return (luma, alpha)
        }
        var candidates: [(Double, Double, Double)] = []
        for row in 0..<4 {
            for column in 0..<6 {
                let u = (Double(column) + 0.5) / 6
                let v = (Double(row) + 0.5) / 4
                let x = Int(u * Double(width)), y = Int(v * Double(height))
                let center = sample(x, y)
                let neighbors = [sample(x - 4, y), sample(x + 4, y), sample(x, y - 4), sample(x, y + 4)]
                let score = center.1 < 0.98 || center.0 < 0.002 || center.0 > 0.98 ? Double.infinity
                    : neighbors.reduce(0) { $0 + abs($1.0 - center.0) } / 4
                candidates.append((score, u, v))
            }
        }
        var estimates: [NoiseEstimator.Tile] = []
        for (_, u, v) in candidates.sorted(by: { $0.0 < $1.0 }).prefix(12) {
            try Task.checkCancellation()
            let x = extent.minX + min(max(0, (u * extent.width - 64).rounded()), extent.width - 128)
            let y = extent.minY + min(max(0, (v * extent.height - 64).rounded()), extent.height - 128)
            var tile = [Float](repeating: 0, count: 128 * 128 * 4)
            tile.withUnsafeMutableBytes { bytes in
                context.render(source, toBitmap: bytes.baseAddress!, rowBytes: 128 * 16,
                               bounds: CGRect(x: x, y: y, width: 128, height: 128),
                               format: .RGBAf, colorSpace: space)
            }
            if let estimate = NoiseEstimator.tile(tile, width: 128, height: 128) { estimates.append(estimate) }
        }
        return estimates
    }
}
