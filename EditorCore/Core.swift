import CoreImage

public enum CoreRenderer {}

/// Immutable per-recipe rendering choices. Input color conversion belongs to the CIContext;
/// source protection and output mapping are reserved for later renderer versions.
public struct RenderPlan: Sendable {
    public enum WorkingSpace: Sendable { case legacySRGB, extendedLinearSRGB }
    public let version: Int
    public let workingSpace: WorkingSpace
    public let sourceColor: SourceColorDescriptor?
    public let color: ColorState
    public let masks: [EditMask]
    public let geometry: Geometry
    public let outputFrame: OutputFrame?

    public init(recipe: EditRecipe) {
        version = recipe.rendererVersion ?? 1
        workingSpace = version == 1 ? .legacySRGB : .extendedLinearSRGB
        sourceColor = recipe.sourceColor
        color = recipe.color
        masks = recipe.masks
        geometry = recipe.geometry
        outputFrame = recipe.outputFrame
    }

    public func grade(_ source: CIImage) -> CIImage {
        if version <= 2 { return CoreRenderer.render(source, color: color, masks: masks) }
        return CoreRenderer.renderV3(source, color: color, masks: masks)
    }

    public func applyGeometry(_ image: CIImage) -> CIImage {
        CoreRenderer.applyGeometry(image, geometry: geometry)
    }

    public func applyOutputFrame(_ image: CIImage) -> CIImage {
        CoreRenderer.applyOutputFrame(image, frame: outputFrame)
    }
}
