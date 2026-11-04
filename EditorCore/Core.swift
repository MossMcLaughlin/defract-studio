import CoreImage

public enum CoreRenderer {}

/// Immutable per-recipe rendering choices. Media adapters own input and output color conversion.
public struct RenderPlan: Sendable {
    public enum WorkingSpace: Sendable { case legacySRGB, extendedLinearSRGB }
    public let version: Int
    public let workingSpace: WorkingSpace
    public let sourceColor: SourceColorDescriptor?
    public let detail: TechnicalDetail
    public let noiseAnalysis: NoiseAnalysis?
    public let color: ColorState
    public let masks: [EditMask]
    public let geometry: Geometry
    public let outputFrame: OutputFrame?

    public init(recipe: EditRecipe) {
        version = recipe.rendererVersion ?? 1
        workingSpace = version == 1 ? .legacySRGB : .extendedLinearSRGB
        sourceColor = recipe.sourceColor
        detail = recipe.detail
        noiseAnalysis = recipe.noiseAnalysis?.identity.matches(recipe) == true ? recipe.noiseAnalysis : nil
        color = recipe.color
        masks = recipe.masks
        geometry = recipe.geometry
        outputFrame = recipe.outputFrame
    }

    public func grade(_ source: CIImage) -> CIImage {
        if version <= 2 { return CoreRenderer.render(source, color: color, masks: masks) }
        if version == 3 { return CoreRenderer.renderV3(source, color: color, masks: masks) }
        if version >= 5 { return CoreRenderer.renderV5(source, color: color, masks: masks,
                                                        detail: detail, analysis: noiseAnalysis) }
        let protected = CoreRenderer.protectV4(source, color: color, masks: masks,
                                               detail: detail, analysis: noiseAnalysis)
        return CoreRenderer.renderV3(protected, color: color, masks: masks)
    }

    public func applyGeometry(_ image: CIImage) -> CIImage {
        CoreRenderer.applyGeometry(image, geometry: geometry)
    }

    public func applyOutputFrame(_ image: CIImage) -> CIImage {
        applyOutputFrame(image, frame: outputFrame)
    }

    public func applyOutputFrame(_ image: CIImage, frame: OutputFrame?) -> CIImage {
        let framed = CoreRenderer.applyOutputFrame(image, frame: frame)
        return version >= 6 ? CoreRenderer.sharpenV6(framed, amount: detail.sharpening,
                                                      noise: noiseAnalysis) : framed
    }
}
