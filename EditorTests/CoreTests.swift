import XCTest
import CoreImage
import EditorCore

final class CoreTests: XCTestCase {
    func testNeutralIdentity() {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let result = CoreRenderer.render(source, grade: BasicGrade())
        XCTAssertTrue(result === source)
    }

    func testGradeSerialization() throws {
        let grade = BasicGrade(exposure: 0.5, saturation: 18)
        XCTAssertEqual(try JSONDecoder().decode(BasicGrade.self, from: JSONEncoder().encode(grade)), grade)
    }
}
