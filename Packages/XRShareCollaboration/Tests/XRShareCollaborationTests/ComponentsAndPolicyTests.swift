import ARKit
import RealityKit
import XCTest
import simd
@testable import XRShareCollaboration

final class ComponentTests: XCTestCase {
    func testInstanceIDComponentCodableRoundTrip() throws {
        let original = InstanceIDComponent(id: "known-id")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InstanceIDComponent.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testDefaultInstanceIDsAreUniqueUUIDs() {
        let first = InstanceIDComponent()
        let second = InstanceIDComponent()
        XCTAssertNotNil(UUID(uuidString: first.id))
        XCTAssertNotEqual(first.id, second.id)
    }

    func testSnapStatePreservesSupportMetadata() {
        let id = UUID()
        let state = SnapStateComponent(
            source: .roomMesh,
            surfaceID: id,
            classification: "table",
            score: 0.75,
            supportRegionID: "region",
            supportPosition: SIMD3<Float>(1, 2, 3),
            supportNormal: SIMD3<Float>(0, 1, 0)
        )
        XCTAssertEqual(state.source, .roomMesh)
        XCTAssertEqual(state.surfaceID, id)
        XCTAssertEqual(state.classification, "table")
        XCTAssertEqual(state.score, 0.75)
        XCTAssertEqual(state.supportRegionID, "region")
        XCTAssertEqual(state.supportPosition, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(state.supportNormal, SIMD3<Float>(0, 1, 0))
    }

    func testSnapSourceKindsRoundTripThroughRawValues() {
        for source in [SnapStateComponent.SourceKind.plane, .roomMesh] {
            XCTAssertEqual(SnapStateComponent.SourceKind(rawValue: source.rawValue), source)
        }
    }

    func testCollisionModesExposeCompleteUIContent() {
        XCTAssertEqual(FurnitureCollisionMode.allCases.map(\.id), ["off", "warn", "prevent"])
        for mode in FurnitureCollisionMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
            XCTAssertFalse(mode.symbolName.isEmpty)
        }
    }

    func testSimpleComponentsRetainValues() {
        let instanceID = UUID()
        XCTAssertEqual(EditAffordanceComponent(instanceID: instanceID).instanceID, instanceID)
        XCTAssertEqual(OriginalBoundsComponent(originalSize: SIMD3<Float>(1, 2, 3)).originalSize, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(MaterialTypeComponent(materialType: "wood").materialType, "wood")

        let orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let collision = CollisionStateComponent(lastValidPosition: SIMD3<Float>(4, 5, 6), lastValidOrientation: orientation)
        XCTAssertEqual(collision.lastValidPosition, SIMD3<Float>(4, 5, 6))
        XCTAssertEqual(collision.lastValidOrientation.vector, orientation.vector)
    }
}

final class SupportSurfacePolicyTests: XCTestCase {
    func testDriftLimitsReflectSupportType() {
        XCTAssertEqual(SupportSurfacePolicy.driftLimit(for: type(.ceiling, .horizontal)), 0.14)
        XCTAssertEqual(SupportSurfacePolicy.driftLimit(for: type(.wall, .vertical)), 0.18)
        XCTAssertEqual(SupportSurfacePolicy.driftLimit(for: type(.floor, .horizontal)), 0.35)
        XCTAssertEqual(SupportSurfacePolicy.driftLimit(for: type(.table, .horizontal)), 0.20)
        XCTAssertEqual(SupportSurfacePolicy.driftLimit(for: type(.any, .any)), 0.25)
    }

    func testModelNormalThresholdsReflectSupportType() {
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: type(.ceiling, .horizontal)), 0.985)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: type(.wall, .vertical)), 0.98)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: type(.floor, .horizontal)), 0.95)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: type(.table, .horizontal)), 0.97)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: type(.any, .any)), 0.95)
    }

    @available(visionOS 2.0, *)
    func testMeshClassificationThresholds() {
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: .ceiling), 0.985)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: .wall), 0.98)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: .table), 0.97)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: .floor), 0.95)
        XCTAssertEqual(SupportSurfacePolicy.normalAlignmentThreshold(for: nil), 0.95)
    }

    private func type(
        _ classification: AnchoringComponent.Target.Classification,
        _ plane: AnchoringComponent.Target.Alignment
    ) -> ModelType {
        ModelType(rawValue: UUID().uuidString, classification: classification, plane: plane)
    }
}

@MainActor
final class DownloadProgressTests: XCTestCase {
    func testProgressIsClampedAndCaseInsensitive() {
        let id = "progress-\(UUID().uuidString)"
        let progress = RemoteDownloadProgress.shared
        progress.begin(id)
        progress.update(id.uppercased(), 2)
        XCTAssertEqual(progress.fraction(for: id), 1)
        progress.update(id, -1)
        XCTAssertEqual(progress.fraction(for: id), 0)
        progress.finish(id)
        XCTAssertNil(progress.fraction(for: id))
    }

    func testFailureCanBeClearedExplicitly() {
        let id = "failure-\(UUID().uuidString)"
        let progress = RemoteDownloadProgress.shared
        progress.fail(id)
        XCTAssertTrue(progress.isFailed(id))
        progress.clearFailure(id.uppercased())
        XCTAssertFalse(progress.isFailed(id))
    }
}
