import RealityKit
import SwiftUI
import XCTest
@testable import XRShareCollaboration

final class SessionValueTests: XCTestCase {
    func testUserRolesRoundTripRawValuesAndCodable() throws {
        for role in [UserRole.host, .viewer, .localSession] {
            XCTAssertEqual(UserRole(rawValue: role.rawValue), role)
            XCTAssertEqual(try JSONDecoder().decode(UserRole.self, from: JSONEncoder().encode(role)), role)
        }
    }

    func testSessionIdentityUsesParticipantConsistentlyForEqualityAndHashing() {
        let first = Session(sessionID: "one", sessionName: "First", participantID: "participant")
        let second = Session(sessionID: "two", sessionName: "Second", participantID: "participant")
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
        XCTAssertEqual(first.id, "one")
    }

    func testDifferentParticipantsAreNotEqual() {
        let first = Session(sessionID: "session", sessionName: "Room", participantID: "one")
        let second = Session(sessionID: "session", sessionName: "Room", participantID: "two")
        XCTAssertNotEqual(first, second)
    }
}

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    private var cache: ThumbnailCache!

    override func setUp() {
        super.setUp()
        cache = ThumbnailCache()
    }

    override func tearDown() {
        cache.clearCache()
        super.tearDown()
    }

    func testMissingThumbnailUsesFallbackAndIsCached() async {
        let resource = "missing-\(UUID().uuidString)"
        XCTAssertFalse(cache.isCached(resource))
        let thumbnail = await cache.getCachedThumbnail(for: resource)
        XCTAssertNotNil(thumbnail)
        XCTAssertTrue(cache.isCached(resource))
        XCTAssertNotNil(cache.getCachedThumbnailSync(for: resource))
    }

    func testRemoveAndClearResetCacheState() async {
        let first = "first-\(UUID().uuidString)"
        let second = "second-\(UUID().uuidString)"
        _ = await cache.getCachedThumbnail(for: first)
        _ = await cache.getCachedThumbnail(for: second)
        cache.removeFromCache(first)
        XCTAssertFalse(cache.isCached(first))
        XCTAssertTrue(cache.isCached(second))
        cache.clearCache()
        XCTAssertFalse(cache.isCached(second))
        XCTAssertFalse(cache.preloadingComplete)
    }

    /// A manifest entry can legitimately arrive with no thumbnail — the
    /// pipeline omits the field when its render step failed. Returning nil
    /// used to leave the catalog tile spinning forever, so the cache now
    /// resolves to a neutral placeholder instead.
    func testRemoteModelWithoutThumbnailURLReturnsPlaceholder() async {
        let modelType = ModelType(rawValue: "chair-\(UUID().uuidString)")
        XCTAssertNil(modelType.remoteThumbnailURL)
        let thumbnail = await cache.getRemoteThumbnail(for: modelType)
        XCTAssertNotNil(thumbnail)
        XCTAssertTrue(cache.isCached(modelType.rawValue))
    }

    func testCacheStatusReportsCount() async {
        let resource = "status-\(UUID().uuidString)"
        _ = await cache.getCachedThumbnail(for: resource)
        XCTAssertTrue(cache.cacheStatus.hasPrefix("Cached thumbnails: 1/"))
    }
}

@MainActor
final class ModelCacheStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ModelCache.shared.clearCache()
    }

    override func tearDown() {
        ModelCache.shared.clearCache()
        super.tearDown()
    }

    func testUnknownModelFailsCleanlyWithoutCaching() async {
        let type = ModelType(rawValue: "missing-\(UUID().uuidString)")
        let entity = await ModelCache.shared.getCachedEntity(for: type)
        XCTAssertNil(entity)
        XCTAssertFalse(ModelCache.shared.isCached(type))
    }

    func testClearAndRemoveAreIdempotent() {
        let type = ModelType(rawValue: "missing")
        ModelCache.shared.removeFromCache(type)
        ModelCache.shared.clearCache()
        XCTAssertFalse(ModelCache.shared.isCached(type))
        XCTAssertFalse(ModelCache.shared.preloadingComplete)
        XCTAssertTrue(ModelCache.shared.cacheStatus.hasPrefix("Cached models: 0/"))
    }
}

@MainActor
final class EntityMaterialUtilitiesTests: XCTestCase {
    func testRestoreRecoversOriginalArrayAfterMaterialSlotsChange() {
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial(), SimpleMaterial()])
        entity.replaceAndStoreOldMaterials(material: UnlitMaterial())
        entity.model?.materials = []
        entity.restoreOriginalMaterials()
        XCTAssertEqual(entity.model?.materials.count, 2)
        XCTAssertTrue(entity.model?.materials.allSatisfy { $0 is SimpleMaterial } == true)
    }

    func testCopyPBRInputsPreservesNestedRoughnessAndHandlesOtherMaterialTypes() {
        let root = Entity()
        var original = PhysicallyBasedMaterial()
        original.roughness = .init(floatLiteral: 0.83)
        let child = ModelEntity(mesh: .generateBox(size: 1), materials: [original, SimpleMaterial()])
        root.addChild(child)
        root.replaceAndStoreOldMaterials(material: PhysicallyBasedMaterial(), copyPBRInputs: true)
        XCTAssertEqual(child.model?.materials.count, 2)
        XCTAssertEqual(child.physicallyBasedMaterial?.roughness.scale, 0.83)
        XCTAssertTrue(child.model?.materials.last is PhysicallyBasedMaterial)
        root.restoreOriginalMaterials()
        XCTAssertTrue(child.model?.materials.last is SimpleMaterial)
    }

    func testReplaceStoresAndRestoreRecoversMaterialCountRecursively() throws {
        let root = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial(), SimpleMaterial()])
        let child = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [SimpleMaterial()])
        root.addChild(child)

        root.replaceAndStoreOldMaterials(material: UnlitMaterial())
        XCTAssertEqual(root.modelComponent?.materials.count, 2)
        XCTAssertTrue(root.modelComponent?.materials.allSatisfy { $0 is UnlitMaterial } == true)
        XCTAssertEqual(child.modelComponent?.materials.count, 1)
        XCTAssertTrue(child.modelComponent?.materials.first is UnlitMaterial)
        XCTAssertNotNil(root.components[SaveOriginalMaterialComponent.self])
        XCTAssertNotNil(child.components[SaveOriginalMaterialComponent.self])

        root.restoreOriginalMaterials()
        XCTAssertEqual(root.modelComponent?.materials.count, 2)
        XCTAssertTrue(root.modelComponent?.materials.allSatisfy { $0 is SimpleMaterial } == true)
        XCTAssertTrue(child.modelComponent?.materials.first is SimpleMaterial)
        XCTAssertNil(root.components[SaveOriginalMaterialComponent.self])
        XCTAssertNil(child.components[SaveOriginalMaterialComponent.self])
    }

    func testReplacementOnlyCapturesOriginalMaterialsOnce() throws {
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
        entity.replaceAndStoreOldMaterials(material: UnlitMaterial())
        entity.replaceAndStoreOldMaterials(material: PhysicallyBasedMaterial())
        entity.restoreOriginalMaterials()
        XCTAssertTrue(entity.modelComponent?.materials.first is SimpleMaterial)
    }

    func testTypedMaterialAccessorsReflectFirstMaterial() {
        let pbr = ModelEntity(mesh: .generateBox(size: 1), materials: [PhysicallyBasedMaterial()])
        XCTAssertNotNil(pbr.physicallyBasedMaterial)
        XCTAssertNil(pbr.shaderGraphMaterial)
        let empty = Entity()
        XCTAssertNil(empty.modelComponent)
        XCTAssertNil(empty.physicallyBasedMaterial)
    }
}

@MainActor
@available(visionOS 26.0, *)
final class MeasurementInteractionTests: XCTestCase {
    func testInactiveSpatialTapIsNotConsumed() {
        XCTAssertFalse(MeasurementManager().handleSpatialTap(on: Entity(), modelsByID: [:]))
    }

    func testInvalidFirstTapIsConsumedAndKeepsWaiting() {
        let manager = MeasurementManager()
        manager.startDistanceMeasurement()
        XCTAssertTrue(manager.handleSpatialTap(on: Entity(), modelsByID: [:]))
        XCTAssertEqual(manager.selectionState, .awaitingFirstObject)
        XCTAssertTrue(manager.statusText.contains("placed object"))
    }

    func testFirstModelCanBeSelectedThroughChildEntity() {
        let manager = MeasurementManager()
        let model = Model(modelType: ModelType(rawValue: "chair"))
        let root = Entity()
        root.components.set(InstanceIDComponent(id: model.id.uuidString))
        let child = Entity()
        root.addChild(child)
        manager.startDistanceMeasurement()
        XCTAssertTrue(manager.handleSpatialTap(on: child, modelsByID: [model.id: model]))
        XCTAssertEqual(manager.selectionState, .awaitingSecondObject(model.id))
        XCTAssertTrue(manager.statusText.contains("Chair"))
    }

    func testSelectingSameModelTwiceKeepsWaitingForSecond() {
        let manager = MeasurementManager()
        let model = Model(modelType: ModelType(rawValue: "chair"))
        let entity = Entity()
        entity.components.set(InstanceIDComponent(id: model.id.uuidString))
        manager.startDistanceMeasurement()
        _ = manager.handleSpatialTap(on: entity, modelsByID: [model.id: model])
        _ = manager.handleSpatialTap(on: entity, modelsByID: [model.id: model])
        XCTAssertEqual(manager.selectionState, .awaitingSecondObject(model.id))
        XCTAssertTrue(manager.statusText.contains("different"))
    }

    func testVirtualRulerRequiresAnchorAndResetRestoresDefaults() {
        let manager = MeasurementManager()
        manager.spawnVirtualRuler(deviceTransform: nil)
        XCTAssertFalse(manager.hasVirtualRuler)
        XCTAssertTrue(manager.statusText.contains("live scene anchor"))
        manager.setShowDimensions(true)
        manager.startDistanceMeasurement()
        manager.reset()
        XCTAssertFalse(manager.hasVirtualRuler)
        XCTAssertFalse(manager.hasActiveDistanceMeasurement)
        XCTAssertEqual(manager.selectionState, .inactive)
        XCTAssertEqual(manager.statusText, "Ready")
    }
}
