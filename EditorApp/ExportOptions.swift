import Foundation
import CoreGraphics
import EditorCore

enum ExportPreset: String, CaseIterable, Identifiable, Sendable {
    case instagram = "Instagram"
    case general = "General"
    case maximum = "Maximum Quality"
    var id: String { rawValue }
}

enum ExportAspect: String, CaseIterable, Identifiable, Sendable {
    case original = "Original"
    case square = "1:1"
    case fourFive = "4:5 Feed"
    case nineSixteen = "9:16 Story/Reel"
    case sixteenNine = "16:9 Wide"
    var id: String { rawValue }
    var ratio: Double? {
        switch self {
        case .original: nil
        case .square: 1
        case .fourFive: 4.0 / 5
        case .nineSixteen: 9.0 / 16
        case .sixteenNine: 16.0 / 9
        }
    }
}

enum PhotoFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG"
    case png = "PNG"
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : "png" }
    var imageIOType: String { self == .jpeg ? "public.jpeg" : "public.png" }
}

struct ExportOptions: Equatable, Sendable {
    var preset: ExportPreset = .general
    var aspect: ExportAspect = .original
    var mode: FrameMode = .fit
    var width: Int
    var height: Int
    var photoFormat: PhotoFormat = .jpeg
    var videoCodec: VideoCodec = .h264
    var name: String
    var folder: URL

    init(recipe: EditRecipe, sourceSize: CGSize) {
        let source = URL(fileURLWithPath: recipe.sourcePath)
        name = source.deletingPathExtension().lastPathComponent + "-edited"
        let base = FileManager.default.homeDirectoryForCurrentUser
        let mediaFolder = recipe.kind == .photo ? "Pictures" : "Movies"
        folder = base.appendingPathComponent(mediaFolder).appendingPathComponent("PhotoVideoEditor/Exports")
        videoCodec = recipe.videoCodec
        let size = recipe.geometry.outputSize(for: sourceSize)
        let dimensions = Self.suggestedSize(preset: .general, aspect: .original, sourceSize: size, kind: recipe.kind)
        width = dimensions.0
        height = dimensions.1
    }

    mutating func updateSuggestedSize(sourceSize: CGSize, kind: MediaKind) {
        let size = Self.suggestedSize(preset: preset, aspect: aspect, sourceSize: sourceSize, kind: kind)
        width = size.0
        height = size.1
    }

    var outputFrame: OutputFrame { OutputFrame(width: width, height: height, mode: mode) }

    func destination(kind: MediaKind) throws -> URL {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ".", clean != "..", !clean.contains("/"), !clean.contains(":"), !clean.contains("\\") else {
            throw NSError(domain: "Editor", code: 30, userInfo: [NSLocalizedDescriptionKey: "Choose a valid file name without path separators."])
        }
        guard width > 0, height > 0, width <= 16000, height <= 16000 else {
            throw NSError(domain: "Editor", code: 31, userInfo: [NSLocalizedDescriptionKey: "Choose output dimensions between 1 and 16000 pixels."])
        }
        let suffix = kind == .photo ? photoFormat.fileExtension : "mp4"
        return folder.appendingPathComponent(clean + "." + suffix)
    }

    private static func suggestedSize(preset: ExportPreset, aspect: ExportAspect, sourceSize: CGSize, kind: MediaKind) -> (Int, Int) {
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        if aspect == .original {
            let longLimit: Double = preset == .instagram ? 1920 : preset == .general ? 3840 : 16000
            let scale = min(1, longLimit / max(sourceWidth, sourceHeight))
            return (pixel(sourceWidth * scale, kind: kind), pixel(sourceHeight * scale, kind: kind))
        }
        let base: (Double, Double)
        switch (preset, aspect) {
        case (_, .original): base = (sourceWidth, sourceHeight)
        case (.instagram, .square): base = (1080, 1080)
        case (.instagram, .fourFive): base = (1080, 1350)
        case (.instagram, .nineSixteen): base = (1080, 1920)
        case (.instagram, .sixteenNine): base = (1920, 1080)
        case (.general, .square): base = (1600, 1600)
        case (.general, .fourFive): base = (1440, 1800)
        case (.general, .nineSixteen): base = (1080, 1920)
        case (.general, .sixteenNine): base = (1920, 1080)
        case (.maximum, .square): base = (3840, 3840)
        case (.maximum, .fourFive): base = (3072, 3840)
        case (.maximum, .nineSixteen): base = (2160, 3840)
        case (.maximum, .sixteenNine): base = (3840, 2160)
        }
        let scale = preset == .maximum ? min(1, max(sourceWidth, sourceHeight) / max(base.0, base.1)) : 1
        return (pixel(base.0 * scale, kind: kind), pixel(base.1 * scale, kind: kind))
    }

    private static func pixel(_ value: Double, kind: MediaKind) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return kind == .video ? rounded - rounded % 2 : rounded
    }
}
