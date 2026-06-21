import RealityKit
import XCTest
import simd
@testable import XRShareCollaboration

@MainActor
final class ModelBehaviorTests: XCTestCase {
    func testInitialStateAndMetadataForwarding() {
        let type = ModelType(rawValue: "chair", classification: .floor, plane: .horizontal, needsPhysics: true, canStack: true)
        let model = Model(modelType: type)
        XCTAssertTrue(model.isLoading() == false)
        XCTAssertFalse(model.isLoaded())
        XCTAssertFalse(model.didFail())
        XCTAssertNil(model.errorMessage())
        XCTAssertEqual(model.classification, .floor)
        XCTAssertEqual(model.plane, .horizontal)
        XCTAssertTrue(model.canStack)
    }

    func testLoadingStateHelpers() {
        let model = Model(modelType: ModelType(rawValue: "placeholder"))
        model.loadingState = .loading
        XCTAssertTrue(model.isLoading())
        model.loadingState = .loaded
        XCTAssertTrue(model.isLoaded())
        model.loadingState = .failed(TestError.expected)
        XCTAssertTrue(model.didFail())
        XCTAssertEqual(model.errorMessage(), "Expected test error")
    }

    func testNormalizationForBoxUsesLargestDimension() throws {
        let entity = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(2, 4, 3)))
        let result = try XCTUnwrap(Model.calculateNormalization(for: entity, targetSize: 2))
        XCTAssertEqual(result.intrinsicMaxDimension, 4, accuracy: 0.001)
        XCTAssertEqual(result.scale, 0.5, accuracy: 0.001)
    }

    func testNormalizationIgnoresExistingRootScale() throws {
        let entity = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(1, 2, 1)))
        entity.scale = SIMD3<Float>(repeating: 10)
        let result = try XCTUnwrap(Model.calculateNormalization(for: entity, targetSize: 1))
        XCTAssertEqual(result.intrinsicMaxDimension, 2, accuracy: 0.001)
        XCTAssertEqual(result.scale, 0.5, accuracy: 0.001)
    }

    func testNormalizationIncludesChildTransform() throws {
        let root = ModelEntity()
        let child = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)))
        child.scale = SIMD3<Float>(3, 1, 1)
        child.position = SIMD3<Float>(2, 0, 0)
        root.addChild(child)
        let result = try XCTUnwrap(Model.calculateNormalization(for: root, targetSize: 1.5))
        XCTAssertEqual(result.intrinsicMaxDimension, 3, accuracy: 0.001)
        XCTAssertEqual(result.scale, 0.5, accuracy: 0.001)
    }

    func testNormalizationRejectsInvalidInput() {
        XCTAssertNil(Model.calculateNormalization(for: ModelEntity(), targetSize: 1))
        let entity = ModelEntity(mesh: .generateBox(size: 1))
        XCTAssertNil(Model.calculateNormalization(for: entity, targetSize: 0))
        XCTAssertNil(Model.calculateNormalization(for: entity, targetSize: -.infinity))
    }

    private enum TestError: LocalizedError {
        case expected
        var errorDescription: String? { "Expected test error" }
    }
}

@MainActor
final class ModelManagerTests: XCTestCase {
    func testSelectionByInstanceAndDeselection() {
        let manager = ModelManager()
        let first = Model(modelType: ModelType(rawValue: "chair"))
        let second = Model(modelType: ModelType(rawValue: "table"))
        manager.placedModels = [first, second]
        manager.modelDict = [first.id: first, second.id: second]

        manager.selectModel(instanceID: second.id)
        XCTAssertEqual(manager.selectedModelInstanceID, second.id)
        XCTAssertEqual(manager.selectedModelID, second.modelType)
        XCTAssertTrue(manager.getSelectedModel() === second)

        manager.deselectModel()
        XCTAssertNil(manager.selectedModelInstanceID)
        XCTAssertNil(manager.selectedModelID)
        XCTAssertNil(manager.getSelectedModel())
    }

    func testRemoveModelUpdatesCollectionsAndCallback() {
        let manager = ModelManager()
        let model = Model(modelType: ModelType(rawValue: "chair"))
        model.modelEntity = ModelEntity()
        manager.placedModels = [model]
        manager.modelDict = [model.id: model]
        manager.selectModel(instanceID: model.id)
        var removed: Model?
        manager.onModelWillRemove = { removed = $0 }

        manager.removeModel(model, broadcast: false)
        XCTAssertTrue(removed === model)
        XCTAssertTrue(manager.placedModels.isEmpty)
        XCTAssertNil(manager.modelDict[model.id])
        XCTAssertNil(manager.selectedModelInstanceID)
    }

    func testResetClearsAllState() {
        let manager = ModelManager()
        let model = Model(modelType: ModelType(rawValue: "chair"))
        manager.placedModels = [model]
        manager.modelDict = [model.id: model]
        manager.selectModel(instanceID: model.id)
        manager.reset(broadcast: false)
        XCTAssertTrue(manager.placedModels.isEmpty)
        XCTAssertTrue(manager.modelDict.isEmpty)
        XCTAssertNil(manager.selectedModelID)
        XCTAssertNil(manager.selectedModelInstanceID)
    }
}

@MainActor
@available(visionOS 26.0, *)
final class FocusModeManagerTests: XCTestCase {
    func testThemeMetadataIsCompleteAndUnique() {
        XCTAssertEqual(Set(FocusModeManager.FocusModeTheme.allCases.map(\.id)).count, FocusModeManager.FocusModeTheme.allCases.count)
        for theme in FocusModeManager.FocusModeTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty)
            XCTAssertFalse(theme.subtitle.isEmpty)
            XCTAssertFalse(theme.symbolName.isEmpty)
        }
    }

    func testDimensionsClampToSupportedRange() {
        let manager = FocusModeManager()
        manager.updateFocusRoomDimensions(width: 1, depth: 20, height: 8)
        XCTAssertEqual(manager.focusRoomDimensions, .init(width: 4, depth: 10, height: 5))
        XCTAssertEqual(manager.statusText, "Room size updated")
    }

    func testChangingThemeUpdatesStatus() {
        let manager = FocusModeManager()
        manager.setFocusTheme(.nightGallery)
        XCTAssertEqual(manager.activeTheme, .nightGallery)
        XCTAssertTrue(manager.statusText.contains("Night Gallery"))
    }

    func testFocusModeRequiresSharedAnchor() {
        let manager = FocusModeManager()
        manager.enterFocusMode()
        XCTAssertFalse(manager.isFocusModeActive)
        XCTAssertTrue(manager.statusText.contains("live shared anchor"))
    }

    func testRecenterRequiresActiveMode() {
        let manager = FocusModeManager()
        manager.recenterFocusMode()
        XCTAssertEqual(manager.statusText, "Enter focus mode first")
    }
}
