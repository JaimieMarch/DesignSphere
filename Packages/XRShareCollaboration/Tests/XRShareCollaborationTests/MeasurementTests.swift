import XCTest
import simd
@testable import XRShareCollaboration

@available(visionOS 26.0, *)
final class MeasurementUnitTests: XCTestCase {

    func testMetersFormatting() {
        XCTAssertEqual(MeasurementManager.Unit.meters.format(distanceMeters: 1), "1.00 m")
        XCTAssertEqual(MeasurementManager.Unit.meters.format(distanceMeters: 2.5), "2.50 m")
    }

    func testCentimetersFormatting() {
        XCTAssertEqual(MeasurementManager.Unit.centimeters.format(distanceMeters: 1), "100.0 cm")
        XCTAssertEqual(MeasurementManager.Unit.centimeters.format(distanceMeters: 0.5), "50.0 cm")
    }

    func testFeetFormatting() {
        XCTAssertEqual(MeasurementManager.Unit.feet.format(distanceMeters: 1), "3.28 ft")
    }

    func testInchesFormatting() {
        XCTAssertEqual(MeasurementManager.Unit.inches.format(distanceMeters: 1), "39.4 in")
    }

    func testDimensionsAreJoinedWithCross() {
        let dims = MeasurementManager.Unit.meters.formatDimensions(SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(dims, "1.00 m × 2.00 m × 3.00 m")
    }

    func testEveryUnitHasDisplayName() {
        for unit in MeasurementManager.Unit.allCases {
            XCTAssertFalse(unit.displayName.isEmpty)
        }
    }
}

@MainActor
@available(visionOS 26.0, *)
final class MeasurementManagerTests: XCTestCase {

    func testStartingDistanceMeasurementAwaitsFirstObject() {
        let manager = MeasurementManager()
        XCTAssertFalse(manager.isAwaitingSelection)

        manager.startDistanceMeasurement()
        XCTAssertEqual(manager.selectionState, .awaitingFirstObject)
        XCTAssertTrue(manager.isAwaitingSelection)
    }

    func testCancellingDistanceMeasurementReturnsToInactive() {
        let manager = MeasurementManager()
        manager.startDistanceMeasurement()
        manager.cancelDistanceSelection()
        XCTAssertEqual(manager.selectionState, .inactive)
        XCTAssertFalse(manager.isAwaitingSelection)
    }

    func testSetUnitUpdatesStateAndStatus() {
        let manager = MeasurementManager()
        manager.setUnit(.feet)
        XCTAssertEqual(manager.unit, .feet)
        XCTAssertTrue(manager.statusText.contains("Feet"))
    }

    func testToggleShowDimensions() {
        let manager = MeasurementManager()
        XCTAssertFalse(manager.showDimensions)

        manager.setShowDimensions(true)
        XCTAssertTrue(manager.showDimensions)
        XCTAssertTrue(manager.statusText.lowercased().contains("visible"))

        manager.setShowDimensions(false)
        XCTAssertFalse(manager.showDimensions)
        XCTAssertTrue(manager.statusText.lowercased().contains("hidden"))
    }

    func testClearingDistanceMeasurementResetsState() {
        let manager = MeasurementManager()
        manager.startDistanceMeasurement()
        manager.clearDistanceMeasurement()
        XCTAssertEqual(manager.selectionState, .inactive)
        XCTAssertFalse(manager.hasActiveDistanceMeasurement)
    }
}
