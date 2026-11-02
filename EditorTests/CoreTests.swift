import XCTest
import CoreImage
import AppKit
import EditorCore

final class CoreTests: XCTestCase {
    func testNeutralIdentity() {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let result = CoreRenderer.render(source, adjustment: AdjustmentVector())
        XCTAssertTrue(result === source)
    }

    func testGradeSerialization() throws {
        var adjustment = AdjustmentVector()
        adjustment[.exposure] = 0.5
        adjustment[.saturation] = 18
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentVector.self, from: JSONEncoder().encode(adjustment)), adjustment)
    }

    func testEasyBaseManualDeltaAndRoundTrip() throws {
        var state = ColorState()
        state.setEasy { $0.waterColor = 50; $0.colorRecovery = 50 }
        XCTAssertEqual(state.base[.temperature], 7)
        XCTAssertEqual(state.base[.redSaturation], 7)
        state.setEffective(.temperature, to: 15)
        XCTAssertEqual(state.manualDelta[.temperature], 8)
        state.setEasy { $0.waterColor = 100 }
        XCTAssertEqual(state.base[.temperature], 14)
        XCTAssertEqual(state.effective[.temperature], 22)
        XCTAssertEqual(state.effective[.redSaturation], 7)
        let reopened = try JSONDecoder().decode(ColorState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reopened, state)
        XCTAssertFalse(reopened.base.isNeutral)
    }

    func testWaterCurveAndHueDirection() {
        var state = ColorState()
        state.setEasy { $0.waterColor = -50 }
        XCTAssertEqual(state.base[.aquaHue], 6)
        XCTAssertEqual(state.base[.temperature], 0)
        state.setEasy { $0.waterColor = 25 }
        XCTAssertEqual(state.base[.greenHue], 12.5)
        var vector = AdjustmentVector()
        vector[.greenHue] = 100
        let shifted = ColorMath.applyLinearRGB(0, 0.5, 0, adjustment: vector)
        XCTAssertGreaterThan(shifted.2, 0.01)
        XCTAssertTrue(shifted.0.isFinite && shifted.1.isFinite && shifted.2.isFinite)
    }

    func testHistoryAndAtomicStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        var history = EditHistory(EditRecipe(sourcePath: "/tmp/source.jpg", kind: .photo))
        history.apply { $0.color.setEasy { $0.waterColor = 50 } }
        history.apply { $0.color.setEffective(.aquaHue, to: 20) }
        history.undo()
        XCTAssertEqual(history.current.color.effective[.aquaHue], 15)
        history.redo()
        XCTAssertEqual(history.current.color.effective[.aquaHue], 20)
        history.undo()
        history.apply { $0.color.setEffective(.aquaHue, to: 23) }
        XCTAssertTrue(history.redoStack.isEmpty)
        try store.save(history)
        let reopened = try store.load(id: history.current.id)
        XCTAssertEqual(reopened.current.color.effective[.aquaHue], 23)
        XCTAssertEqual(reopened.undoStack.count, 2)
        XCTAssertEqual(try store.loadAll().count, 1)
    }

    func testCropGeometryAcrossOrientations() {
        var geometry = Geometry()
        geometry.aspect = .fourFive
        let portrait = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1536, height: 2048))
        XCTAssertEqual(portrait.width, 1536)
        XCTAssertEqual(portrait.height, 1920)
        geometry.aspect = .nineSixteen
        let landscape = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(landscape.height, 1080)
        XCTAssertEqual(landscape.width, 607.5)
        geometry.centerX = 0
        XCTAssertEqual(geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1920, height: 1080)).minX, 0)
    }

    func testEveryMathControlHasEffect() {
        let hues: [Double] = [0, 30, 60, 120, 180, 240, 275, 320]
        func linear(_ encoded: Double) -> Double {
            encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        for (index, parameter) in Parameter.allCases.enumerated() where parameter != .temperature && parameter != .tint {
            let sample: (Double, Double, Double)
            if index >= 10 {
                let hue = hues[(index - 10) / 3] / 60
                let x = 0.8 * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
                let encoded: (Double, Double, Double)
                switch hue {
                case ..<1: encoded = (0.9, 0.1 + x, 0.1)
                case ..<2: encoded = (0.1 + x, 0.9, 0.1)
                case ..<3: encoded = (0.1, 0.9, 0.1 + x)
                case ..<4: encoded = (0.1, 0.1 + x, 0.9)
                case ..<5: encoded = (0.1 + x, 0.1, 0.9)
                default: encoded = (0.9, 0.1, 0.1 + x)
                }
                sample = (linear(encoded.0), linear(encoded.1), linear(encoded.2))
            } else if parameter == .highlights || parameter == .whites { sample = (0.8, 0.7, 0.6) }
            else if parameter == .shadows || parameter == .blacks { sample = (0.2, 0.15, 0.1) }
            else { sample = (0.4, 0.2, 0.1) }
            var adjustment = AdjustmentVector()
            adjustment[parameter] = parameter == .exposure ? 0.5 : 30
            let changed = ColorMath.applyLinearRGB(sample.0, sample.1, sample.2, adjustment: adjustment)
            let difference = abs(changed.0 - sample.0) + abs(changed.1 - sample.1) + abs(changed.2 - sample.2)
            XCTAssertGreaterThan(difference, 0.0001, "\(parameter) did not change its test color")
        }
    }

    func testMaskMathBrushPersistenceAndLocalBlend() throws {
        var mask = EditMask(name: "Subject", kind: .brush)
        mask.strokes = [
            BrushStroke(operation: .add, points: [NormalizedPoint(0.5, 0.5)], size: 0.4, feather: 0.5),
            BrushStroke(operation: .erase, points: [NormalizedPoint(0.5, 0.5)], size: 0.1, feather: 0.5)
        ]
        XCTAssertEqual(MaskMath.alpha(at: NormalizedPoint(0.5, 0.5), mask: mask), 0, accuracy: 0.001)
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.6, 0.5), mask: mask), 0.5)
        let restored = try JSONDecoder().decode(EditMask.self, from: JSONEncoder().encode(mask))
        XCTAssertEqual(restored, mask)
        var radial = EditMask(name: "Center", kind: .radial)
        radial.adjustment[.exposure] = 1
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let rendered = CoreRenderer.render(source, color: ColorState(), masks: [radial])
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(rendered, from: source.extent))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let center = try XCTUnwrap(bitmap.colorAt(x: 32, y: 32))
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertGreaterThan(center.redComponent, corner.redComponent + 0.05)
        XCTAssertEqual(corner.redComponent, 0.2, accuracy: 0.03)
    }

    func testRotateAndStraightenGeometry() {
        var geometry = Geometry()
        geometry.rotateQuarterTurns = 1
        XCTAssertEqual(geometry.outputSize(for: CGSize(width: 100, height: 200)), CGSize(width: 200, height: 100))
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let rotated = CoreRenderer.applyGeometry(source, geometry: geometry)
        XCTAssertEqual(rotated.extent.size.width, 200, accuracy: 0.001)
        XCTAssertEqual(rotated.extent.size.height, 100, accuracy: 0.001)
        geometry.rotateQuarterTurns = 0
        geometry.straightenDegrees = 10
        let straightened = CoreRenderer.applyGeometry(source, geometry: geometry)
        XCTAssertLessThan(straightened.extent.width, 100)
        XCTAssertLessThan(straightened.extent.height, 200)
        XCTAssertEqual(straightened.extent.width / straightened.extent.height, 0.5, accuracy: 0.001)
    }

    func testFreeCropAndLinearMaskInversion() {
        var geometry = Geometry()
        geometry.aspect = .free
        geometry.freeWidth = 0.5
        geometry.freeHeight = 0.75
        geometry.centerX = 1
        let crop = geometry.cropRect(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(crop, CGRect(x: 500, y: 100, width: 500, height: 600))
        var mask = EditMask(name: "Sky", kind: .linear)
        XCTAssertLessThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.1), mask: mask), 0.01)
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.9), mask: mask), 0.99)
        mask.inverted = true
        XCTAssertGreaterThan(MaskMath.alpha(at: NormalizedPoint(0.5, 0.1), mask: mask), 0.99)
    }

    func testSourcePointMappingSurvivesCropAndRotation() {
        let size = CGSize(width: 1536, height: 2048)
        for turn in [-1, 0, 1, 2] {
            var geometry = Geometry()
            geometry.aspect = .fourFive
            geometry.cropScale = 0.8
            geometry.centerX = 0.7
            geometry.centerY = 0.3
            geometry.straightenDegrees = 7
            geometry.rotateQuarterTurns = turn
            let source = NormalizedPoint(0.5, 0.5)
            let displayed = geometry.outputPoint(fromSourceNormalized: source, sourceSize: size)
            let restored = geometry.sourcePoint(fromOutputNormalized: displayed, sourceSize: size)
            XCTAssertEqual(restored.x, source.x, accuracy: 0.000001)
            XCTAssertEqual(restored.y, source.y, accuracy: 0.000001)
        }
    }

    func testFitAndFillFrameWithoutStretching() throws {
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let context = CIContext()
        let fit = CoreRenderer.applyOutputFrame(source, frame: OutputFrame(width: 200, height: 200, mode: .fit))
        let fill = CoreRenderer.applyOutputFrame(source, frame: OutputFrame(width: 200, height: 200, mode: .fill))
        XCTAssertEqual(fit.extent.size, CGSize(width: 200, height: 200))
        XCTAssertEqual(fill.extent.size, CGSize(width: 200, height: 200))
        let fitBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.createCGImage(fit, from: fit.extent)))
        let fillBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.createCGImage(fill, from: fill.extent)))
        XCTAssertLessThan(try XCTUnwrap(fitBitmap.colorAt(x: 10, y: 100)).redComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(fitBitmap.colorAt(x: 100, y: 100)).redComponent, 0.95)
        XCTAssertGreaterThan(try XCTUnwrap(fillBitmap.colorAt(x: 10, y: 100)).redComponent, 0.95)
        for mode in [FrameMode.fit, .fill] {
            let frame = OutputFrame(width: 1080, height: 1920, mode: mode)
            let input = NormalizedPoint(0.3, 0.7)
            let shown = frame.outputPoint(fromInputNormalized: input, inputSize: CGSize(width: 800, height: 1000))
            let restored = frame.inputPoint(fromOutputNormalized: shown, inputSize: CGSize(width: 800, height: 1000))
            XCTAssertEqual(restored.x, input.x, accuracy: 0.000001)
            XCTAssertEqual(restored.y, input.y, accuracy: 0.000001)
        }
    }
}
