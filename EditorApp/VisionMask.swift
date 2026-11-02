import Foundation
import Vision
import CoreImage
import ImageIO

enum VisionMask {
    static func foregroundPNG(url: URL) throws -> Data {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw NSError(domain: "Editor", code: 20, userInfo: [NSLocalizedDescriptionKey: "No suitable subject found. Use Brush to select it manually."])
        }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent) else {
            throw NSError(domain: "Editor", code: 21, userInfo: [NSLocalizedDescriptionKey: "Vision returned a mask that could not be rendered. Use Brush instead."])
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "Editor", code: 22, userInfo: [NSLocalizedDescriptionKey: "The subject mask could not be saved."])
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "Editor", code: 23, userInfo: [NSLocalizedDescriptionKey: "The subject mask could not be saved."])
        }
        return data as Data
    }
}
