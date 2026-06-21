import RealityKit
import XCTest
import simd
@testable import XRShareCollaboration

@MainActor
final class FurnitureCollisionTests: XCTestCase {
    func testSeparatedFloorModelsDoNotOverlap() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let placed = makeModel(position: SIMD3<Float>(2, 0, 0), anchor: anchor)
        XCTAssertFalse(
            FurnitureCollisionEngine.hasOverlap(
                entity: moving,
                instanceID: UUID(),
                modelType: floorType(),
                relativeTo: anchor,
                among: [placed]
            )
        )
    }

    func testIntersectingFloorModelsReportInstanceID() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let placed = makeModel(position: SIMD3<Float>(0.2, 0, 0), anchor: anchor)
        let ids = FurnitureCollisionEngine.overlappingIDs(
            entity: moving,
            instanceID: UUID(),
            modelType: floorType(),
            relativeTo: anchor,
            among: [placed]
        )
        XCTAssertEqual(ids, [placed.id])
    }

    func testMovingModelIsExcludedFromItsOwnCollisionSet() {
        let anchor = Entity()
        let model = makeModel(position: .zero, anchor: anchor)
        XCTAssertFalse(
            FurnitureCollisionEngine.hasOverlap(
                entity: model.modelEntity!,
                instanceID: model.id,
                modelType: model.modelType,
                relativeTo: anchor,
                among: [model]
            )
        )
    }

    func testUnsupportedClassificationDoesNotParticipate() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let tableType = ModelType(rawValue: "vase", classification: .table, plane: .horizontal)
        let placed = makeModel(position: .zero, anchor: anchor)
        XCTAssertTrue(
            FurnitureCollisionEngine.overlappingIDs(
                entity: moving,
                instanceID: UUID(),
                modelType: tableType,
                relativeTo: anchor,
                among: [placed]
            ).isEmpty
        )
    }

    func testDifferentSupportFamiliesDoNotCollide() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let wall = makeModel(
            position: .zero,
            anchor: anchor,
            type: ModelType(rawValue: "painting", classification: .wall, plane: .vertical)
        )
        XCTAssertFalse(
            FurnitureCollisionEngine.hasOverlap(
                entity: moving,
                instanceID: UUID(),
                modelType: floorType(),
                relativeTo: anchor,
                among: [wall]
            )
        )
    }

    func testFloorModelsOnDifferentLevelsDoNotCollide() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let raised = makeModel(position: SIMD3<Float>(0, 1, 0), anchor: anchor)
        XCTAssertFalse(
            FurnitureCollisionEngine.hasOverlap(
                entity: moving,
                instanceID: UUID(),
                modelType: floorType(),
                relativeTo: anchor,
                among: [raised]
            )
        )
    }

    func testWarnModeReportsOverlapWithoutChangingPosition() {
        let anchor = Entity()
        let moving = makeEntity(position: SIMD3<Float>(0.1, 0, 0), anchor: anchor)
        let placed = makeModel(position: .zero, anchor: anchor)
        let result = FurnitureCollisionEngine.resolve(
            entity: moving,
            instanceID: UUID(),
            modelType: floorType(),
            relativeTo: anchor,
            among: [placed],
            mode: .warn
        )
        XCTAssertTrue(result.hasOverlap)
        XCTAssertEqual(result.overlaps, [placed.id])
        XCTAssertEqual(result.resolvedPosition, SIMD3<Float>(0.1, 0, 0))
    }

    func testPreventModeCanUseLastValidPosition() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let placed = makeModel(position: .zero, anchor: anchor)
        let result = FurnitureCollisionEngine.resolve(
            entity: moving,
            instanceID: UUID(),
            modelType: floorType(),
            relativeTo: anchor,
            among: [placed],
            mode: .prevent,
            lastValidPosition: SIMD3<Float>(2, 0, 0),
            allowSearch: false
        )
        XCTAssertTrue(result.hasOverlap)
        XCTAssertEqual(result.resolvedPosition, SIMD3<Float>(2, 0, 0))
    }

    func testPreventModeHonorsPositionValidator() {
        let anchor = Entity()
        let moving = makeEntity(position: .zero, anchor: anchor)
        let placed = makeModel(position: .zero, anchor: anchor)
        let result = FurnitureCollisionEngine.resolve(
            entity: moving,
            instanceID: UUID(),
            modelType: floorType(),
            relativeTo: anchor,
            among: [placed],
            mode: .prevent,
            lastValidPosition: SIMD3<Float>(2, 0, 0),
            positionValidator: { _ in false },
            allowSearch: false
        )
        XCTAssertTrue(result.hasOverlap)
        XCTAssertNil(result.resolvedPosition)
    }

    private func floorType() -> ModelType {
        ModelType(rawValue: "chair", classification: .floor, plane: .horizontal)
    }

    private func makeEntity(
        position: SIMD3<Float>,
        anchor: Entity,
        extents: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) -> ModelEntity {
        let entity = ModelEntity()
        entity.components.set(
            ModelBoundsComponent(
                center: .zero,
                extents: extents,
                placementOffset: SIMD3<Float>(0, -extents.y * 0.5, 0)
            )
        )
        entity.position = position
        anchor.addChild(entity)
        return entity
    }

    private func makeModel(
        position: SIMD3<Float>,
        anchor: Entity,
        type: ModelType? = nil
    ) -> Model {
        let model = Model(modelType: type ?? floorType())
        model.modelEntity = makeEntity(position: position, anchor: anchor)
        return model
    }
}
