import Foundation

public enum Parameter: String, CaseIterable, Codable, Hashable, Sendable {
    case exposure, contrast, highlights, shadows, whites, blacks
    case temperature, tint, saturation, vibrance
    case redHue, redSaturation, redLuminance
    case orangeHue, orangeSaturation, orangeLuminance
    case yellowHue, yellowSaturation, yellowLuminance
    case greenHue, greenSaturation, greenLuminance
    case aquaHue, aquaSaturation, aquaLuminance
    case blueHue, blueSaturation, blueLuminance
    case purpleHue, purpleSaturation, purpleLuminance
    case magentaHue, magentaSaturation, magentaLuminance

    public var limits: ClosedRange<Double> { self == .exposure ? -3...3 : -100...100 }
    public var title: String {
        rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }
}

public struct AdjustmentVector: Codable, Equatable, Sendable {
    private var values: [Parameter: Double] = [:]

    public init() {}

    public subscript(_ parameter: Parameter) -> Double {
        get { values[parameter] ?? 0 }
        set { values[parameter] = newValue }
    }

    public var isNeutral: Bool { Parameter.allCases.allSatisfy { self[$0] == 0 } }

    public func adding(_ other: AdjustmentVector, clamp: Bool = false) -> AdjustmentVector {
        var result = AdjustmentVector()
        for parameter in Parameter.allCases {
            let value = self[parameter] + other[parameter]
            result[parameter] = clamp ? min(parameter.limits.upperBound, max(parameter.limits.lowerBound, value)) : value
        }
        return result
    }
}

public struct EasySettings: Codable, Equatable, Sendable {
    public var waterColor = 0.0
    public var colorRecovery = 0.0
    public var light = 0.0
    public var visibility = 0.0
    public init() {}
}

public struct ColorState: Codable, Equatable, Sendable {
    public private(set) var easy = EasySettings()
    public private(set) var base = AdjustmentVector()
    public private(set) var manualDelta = AdjustmentVector()
    public private(set) var effective = AdjustmentVector()
    public var underwaterMappingVersion = 1

    public init() {}

    public mutating func setEasy(_ update: (inout EasySettings) -> Void) {
        update(&easy)
        base = EasyMapping.evaluate(easy)
        effective = base.adding(manualDelta, clamp: true)
    }

    public mutating func setEffective(_ parameter: Parameter, to value: Double) {
        manualDelta[parameter] = min(parameter.limits.upperBound, max(parameter.limits.lowerBound, value)) - base[parameter]
        effective = base.adding(manualDelta, clamp: true)
    }

    public mutating func resetManual() {
        manualDelta = AdjustmentVector()
        effective = base
    }

    public mutating func resetManual(_ parameters: [Parameter]) {
        for parameter in parameters { manualDelta[parameter] = 0 }
        effective = base.adding(manualDelta, clamp: true)
    }

    public mutating func resetEasy() {
        easy = EasySettings()
        base = AdjustmentVector()
        effective = base.adding(manualDelta, clamp: true)
    }
}

public enum EasyMapping {
    private typealias Knot = (Double, [Parameter: Double])

    private static let water: [Knot] = [
        (-100, [.aquaHue: 12, .aquaSaturation: -10, .blueSaturation: 5, .blueLuminance: -5]),
        (-50, [.aquaHue: 6, .aquaSaturation: -5, .blueSaturation: 2, .blueLuminance: -2]),
        (0, [:]),
        (50, [.temperature: 7, .tint: 7, .greenHue: 25, .aquaHue: 15, .greenSaturation: -10, .aquaSaturation: 2, .blueSaturation: 4, .blueLuminance: 1, .whites: 2]),
        (100, [.temperature: 14, .tint: 14, .greenHue: 50, .aquaHue: 30, .greenSaturation: -22, .aquaSaturation: 4, .blueSaturation: 8, .blueLuminance: 2, .whites: 4])
    ]
    private static let recovery: [Knot] = [
        (0, [:]),
        (50, [.saturation: 5, .vibrance: 8, .redSaturation: 7, .orangeSaturation: 9, .yellowSaturation: 3, .redLuminance: -2, .orangeLuminance: 2, .yellowLuminance: 2, .greenLuminance: 1, .aquaLuminance: 1, .blueLuminance: -2, .shadows: 2]),
        (100, [.saturation: 10, .vibrance: 16, .redSaturation: 14, .orangeSaturation: 18, .yellowSaturation: 6, .redLuminance: -4, .orangeLuminance: 4, .yellowLuminance: 4, .greenLuminance: 2, .aquaLuminance: 2, .blueLuminance: -4, .shadows: 4])
    ]
    private static let light: [Knot] = [
        (-100, [.exposure: -0.8, .contrast: 5, .highlights: -8, .shadows: -20, .blacks: -10]),
        (-50, [.exposure: -0.35, .contrast: 2, .highlights: -4, .shadows: -8, .blacks: -4]),
        (0, [:]),
        (50, [.exposure: 0.35, .contrast: 2, .highlights: -5, .shadows: 9, .whites: 1]),
        (100, [.exposure: 0.8, .contrast: 4, .highlights: -12, .shadows: 18, .whites: 2])
    ]
    private static let visibility: [Knot] = [
        (0, [:]), (50, [.contrast: 6, .blacks: -4, .highlights: -2]),
        (100, [.contrast: 12, .blacks: -8, .highlights: -4])
    ]

    private static func interpolate(_ value: Double, knots: [Knot]) -> AdjustmentVector {
        let bounded = min(knots.last!.0, max(knots.first!.0, value))
        let upper = knots.firstIndex { $0.0 >= bounded } ?? knots.count - 1
        let lower = max(0, upper - 1)
        let span = knots[upper].0 - knots[lower].0
        let fraction = span == 0 ? 0 : (bounded - knots[lower].0) / span
        var vector = AdjustmentVector()
        for parameter in Parameter.allCases {
            let a = knots[lower].1[parameter] ?? 0
            let b = knots[upper].1[parameter] ?? 0
            vector[parameter] = a + (b - a) * fraction
        }
        return vector
    }

    public static func evaluate(_ easy: EasySettings) -> AdjustmentVector {
        interpolate(easy.waterColor, knots: water)
            .adding(interpolate(easy.colorRecovery, knots: recovery))
            .adding(interpolate(easy.light, knots: light))
            .adding(interpolate(easy.visibility, knots: visibility))
    }
}

public enum MediaKind: String, Codable, Sendable { case photo, video }

public struct SourceColorDescriptor: Codable, Equatable, Sendable {
    public enum DynamicRange: String, Codable, Sendable { case sdr, hlg, pq, unknown }
    public var sourceBitDepth: Int?
    public var primaries: String?
    public var transfer: String?
    public var matrix: String?
    public var fullRange: Bool?
    public var profile: String?
    public var dynamicRange: DynamicRange
    public var orientation: Int?
    public var evidence: String

    public init(sourceBitDepth: Int? = nil, primaries: String? = nil, transfer: String? = nil,
                matrix: String? = nil, fullRange: Bool? = nil, profile: String? = nil,
                dynamicRange: DynamicRange = .unknown, orientation: Int? = nil, evidence: String) {
        self.sourceBitDepth = sourceBitDepth
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
        self.fullRange = fullRange
        self.profile = profile
        self.dynamicRange = dynamicRange
        self.orientation = orientation
        self.evidence = evidence
    }
}

public struct VideoTrim: Codable, Equatable, Sendable {
    public var startSeconds = 0.0
    public var endSeconds: Double?
    public init() {}
}

public enum VideoCodec: String, Codable, Sendable { case h264, hevc }

public struct EditRecipe: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var rendererVersion: Int?
    public var sourceColor: SourceColorDescriptor?
    public var id = UUID()
    public var sourcePath: String
    public var kind: MediaKind
    public var color = ColorState()
    public var geometry = Geometry()
    public var masks: [EditMask] = []
    public var videoTrim = VideoTrim()
    public var videoCodec: VideoCodec = .h264
    public var outputFrame: OutputFrame?
    public var sourceFileSize: Int64?
    public var lastExportedAt: Date?
    public var lastModified = Date()

    public init(sourcePath: String, kind: MediaKind) {
        self.sourcePath = sourcePath
        self.kind = kind
        self.schemaVersion = 2
        self.rendererVersion = 2
    }

    public var hasUnexportedEdits: Bool {
        let edited = easyIsEdited || !color.manualDelta.isNeutral || !masks.isEmpty
            || geometry != Geometry() || videoTrim != VideoTrim() || outputFrame != nil
        guard edited else { return false }
        guard let lastExportedAt else { return true }
        return lastModified > lastExportedAt
    }

    private var easyIsEdited: Bool { color.easy != EasySettings() }
}

public struct EditHistory: Codable, Sendable {
    public private(set) var current: EditRecipe
    public private(set) var undoStack: [EditRecipe] = []
    public private(set) var redoStack: [EditRecipe] = []

    public init(_ recipe: EditRecipe) { current = recipe }

    public mutating func setSourceColor(_ descriptor: SourceColorDescriptor) {
        current.sourceColor = descriptor
        for index in undoStack.indices where undoStack[index].sourcePath == current.sourcePath {
            undoStack[index].sourceColor = descriptor
        }
        for index in redoStack.indices where redoStack[index].sourcePath == current.sourcePath {
            redoStack[index].sourceColor = descriptor
        }
    }

    public mutating func apply(_ update: (inout EditRecipe) -> Void) {
        var next = current
        update(&next)
        guard next != current else { return }
        undoStack.append(current)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        next.lastModified = Date()
        current = next
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        current = previous
        current.lastModified = Date()
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        current = next
        current.lastModified = Date()
    }

    public mutating func markExported() {
        current.lastExportedAt = Date()
    }
}
