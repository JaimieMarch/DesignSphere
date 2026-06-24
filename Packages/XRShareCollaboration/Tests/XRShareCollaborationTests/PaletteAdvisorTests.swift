import XCTest
@testable import XRShareCollaboration

final class PaletteAdvisorTests: XCTestCase {

    func testPalettesExist() {
        XCTAssertGreaterThanOrEqual(PaletteAdvisor.palettes.count, 4)
    }

    func testPaletteIDsAreUnique() {
        let ids = PaletteAdvisor.palettes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryPaletteHasNamedColors() {
        for palette in PaletteAdvisor.palettes {
            XCTAssertFalse(palette.name.isEmpty)
            XCTAssertGreaterThanOrEqual(palette.colors.count, 3, "\(palette.name) is too small")
            XCTAssertTrue(palette.colors.allSatisfy { !$0.name.isEmpty })
        }
    }

    func testColorComponentsAreInRange() {
        for color in PaletteAdvisor.palettes.flatMap(\.colors) {
            for component in [color.red, color.green, color.blue] {
                XCTAssertTrue((0...1).contains(component), "\(color.name) component out of range: \(component)")
            }
        }
    }
}
