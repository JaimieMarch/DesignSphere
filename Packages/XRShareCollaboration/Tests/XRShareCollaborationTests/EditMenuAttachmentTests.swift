import RealityKit
import XCTest
import simd
@testable import XRShareCollaboration

/// Guards the floating edit panel's attachment lifecycle. The panel is a
/// RealityView attachment adopted by `syncEditMenuAttachment`; a legacy
/// points-to-meters scale factor (0.0012) once shrank it to under a
/// millimeter, which read as "the panel doesn't render". These tests pin the
/// adoption contract: natural scale, shared-anchor parenting, billboard, and
/// enable/disable driven by the expanded-model state.
@available(visionOS 26.0, *)
@MainActor
final class EditMenuAttachmentTests: XCTestCase {

    private func makePlacedModel(
        in controller: CollaborativeSessionController,
        size: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) -> Model {
        let model = Model(modelType: ModelType(rawValue: "test-sofa"))
        let entity = ModelEntity(mesh: .generateBox(size: size))
        controller.sharedAnchorEntity.addChild(entity)
        model.modelEntity = entity
        model.loadingState = .loaded
        controller.modelManager.placedModels = [model]
        controller.modelManager.modelDict = [model.id: model]
        return model
    }

    // Regression for the invisible edit panel: RealityView attachment
    // entities are already physically sized, so adoption must leave them at
    // scale 1 — never the 0.0012 ViewAttachmentComponent-era factor.
    func testSyncAdoptsAttachmentAtNaturalScaleUnderSharedAnchor() {
        let controller = CollaborativeSessionController()
        let panel = Entity()
        panel.scale = SIMD3<Float>(repeating: 0.0012)

        controller.syncEditMenuAttachment(panel)

        XCTAssertEqual(panel.scale, SIMD3<Float>(repeating: 1),
                       "attachment must keep its natural (meter-based) size")
        XCTAssertTrue(panel.parent === controller.sharedAnchorEntity)
        XCTAssertNotNil(panel.components[BillboardComponent.self])
    }

    func testPanelIsDisabledWhenNoModelIsExpanded() {
        let controller = CollaborativeSessionController()
        let panel = Entity()

        controller.syncEditMenuAttachment(panel)

        XCTAssertNil(controller.expandedEditModelID)
        XCTAssertFalse(panel.isEnabled)
    }

    func testPanelIsEnabledAndOffsetBesideExpandedModel() {
        let controller = CollaborativeSessionController()
        let model = makePlacedModel(in: controller)

        controller.requestEditModel(instanceID: model.id)
        let panel = Entity()
        controller.syncEditMenuAttachment(panel)

        XCTAssertEqual(controller.expandedEditModelID, model.id)
        XCTAssertTrue(panel.isEnabled)
        // Simulator/no-head-tracking placement: beside the model at its own
        // height (extents.x * 0.5 + 0.32 for a unit box ⇒ x ≈ 0.82).
        let position = panel.position(relativeTo: controller.sharedAnchorEntity)
        XCTAssertEqual(position.x, 0.82, accuracy: 0.05)
        XCTAssertEqual(position.y, 0, accuracy: 0.05)
    }

    func testRequestEditModelTogglesAndCollapseDisablesPanel() {
        let controller = CollaborativeSessionController()
        let model = makePlacedModel(in: controller)
        let panel = Entity()

        controller.requestEditModel(instanceID: model.id)
        controller.syncEditMenuAttachment(panel)
        XCTAssertTrue(panel.isEnabled)

        // Same model again toggles the panel closed.
        controller.requestEditModel(instanceID: model.id)
        XCTAssertNil(controller.expandedEditModelID)
        XCTAssertFalse(panel.isEnabled)

        controller.requestEditModel(instanceID: model.id)
        XCTAssertEqual(controller.expandedEditModelID, model.id)
        controller.collapseEditMenu()
        XCTAssertNil(controller.expandedEditModelID)
        XCTAssertFalse(panel.isEnabled)
    }

    func testRequestEditModelIgnoresUnknownInstance() {
        let controller = CollaborativeSessionController()
        controller.requestEditModel(instanceID: UUID())
        XCTAssertNil(controller.expandedEditModelID)
    }

    func testSyncReplacesAndDetachesPreviousAttachment() {
        let controller = CollaborativeSessionController()
        let first = Entity()
        let second = Entity()

        controller.syncEditMenuAttachment(first)
        XCTAssertTrue(first.parent === controller.sharedAnchorEntity)

        controller.syncEditMenuAttachment(second)
        XCTAssertNil(first.parent, "stale attachment must be detached")
        XCTAssertTrue(second.parent === controller.sharedAnchorEntity)

        controller.syncEditMenuAttachment(nil)
        XCTAssertNil(second.parent, "attachment must detach when the panel closes")
    }

    func testPanelDisablesWhenExpandedModelIsRemoved() {
        let controller = CollaborativeSessionController()
        let model = makePlacedModel(in: controller)
        let panel = Entity()

        controller.requestEditModel(instanceID: model.id)
        controller.syncEditMenuAttachment(panel)
        XCTAssertTrue(panel.isEnabled)

        controller.removeModelById(withInstanceID: model.id)
        XCTAssertNil(controller.expandedEditModelID)
        XCTAssertFalse(panel.isEnabled)
    }
}

/// Routing of immersive-space spatial taps: edit affordances open the panel,
/// model taps select, empty taps deselect and close the panel.
@available(visionOS 26.0, *)
@MainActor
final class SpatialTapRoutingTests: XCTestCase {

    private func makePlacedModel(
        in controller: CollaborativeSessionController
    ) -> (model: Model, entity: ModelEntity) {
        let model = Model(modelType: ModelType(rawValue: "test-chair"))
        let entity = ModelEntity(mesh: .generateBox(size: 1))
        entity.components.set(InstanceIDComponent(id: model.id.uuidString))
        controller.sharedAnchorEntity.addChild(entity)
        model.modelEntity = entity
        model.loadingState = .loaded
        controller.modelManager.placedModels = [model]
        controller.modelManager.modelDict = [model.id: model]
        return (model, entity)
    }

    func testTapOnEditAffordanceOpensPanelAndTogglesClosed() {
        let controller = CollaborativeSessionController()
        let (model, _) = makePlacedModel(in: controller)
        let affordance = Entity()
        affordance.components.set(EditAffordanceComponent(instanceID: model.id))

        controller.handleSpatialTap(on: affordance)
        XCTAssertEqual(controller.expandedEditModelID, model.id)
        XCTAssertEqual(controller.modelManager.selectedModelInstanceID, model.id)

        controller.handleSpatialTap(on: affordance)
        XCTAssertNil(controller.expandedEditModelID)
    }

    func testTapOnAffordanceChildResolvesThroughAncestor() {
        let controller = CollaborativeSessionController()
        let (model, _) = makePlacedModel(in: controller)
        let affordance = Entity()
        affordance.components.set(EditAffordanceComponent(instanceID: model.id))
        let glyph = Entity()
        affordance.addChild(glyph)

        controller.handleSpatialTap(on: glyph)
        XCTAssertEqual(controller.expandedEditModelID, model.id)
    }

    func testTapOnModelSelectsItAndClosesPanel() {
        let controller = CollaborativeSessionController()
        let (model, entity) = makePlacedModel(in: controller)

        controller.requestEditModel(instanceID: model.id)
        XCTAssertEqual(controller.expandedEditModelID, model.id)

        controller.handleSpatialTap(on: entity)
        XCTAssertEqual(controller.modelManager.selectedModelInstanceID, model.id)
        XCTAssertNil(controller.expandedEditModelID, "model tap closes the panel")
    }

    func testEmptyTapDeselectsAndClosesPanel() {
        let controller = CollaborativeSessionController()
        let (model, _) = makePlacedModel(in: controller)

        controller.requestEditModel(instanceID: model.id)
        controller.handleEmptySpatialTap()

        XCTAssertNil(controller.modelManager.selectedModelInstanceID)
        XCTAssertNil(controller.expandedEditModelID)
    }

    func testTapOnUnmanagedEntityChangesNothing() {
        let controller = CollaborativeSessionController()
        let (model, _) = makePlacedModel(in: controller)
        controller.modelManager.selectModel(instanceID: model.id)

        controller.handleSpatialTap(on: Entity())

        XCTAssertEqual(controller.modelManager.selectedModelInstanceID, model.id)
    }
}
