import Foundation
import CoreImage
import CoreGraphics

public struct BasicGrade: Codable, Equatable, Sendable {
    public var exposure: Double
    public var saturation: Double

    public init(exposure: Double = 0, saturation: Double = 0) {
        self.exposure = exposure
        self.saturation = saturation
    }
}

public enum CoreRenderer {
    public static func render(_ source: CIImage, grade: BasicGrade) -> CIImage {
        var result = source
        if grade.exposure != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: grade.exposure])
        }
        if grade.saturation != 0 {
            result = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + grade.saturation / 100])
        }
        return result
    }
}
