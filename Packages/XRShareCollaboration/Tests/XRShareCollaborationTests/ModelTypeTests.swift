import XCTest
import RealityKit
@testable import XRShareCollaboration

final class ModelTypeTests: XCTestCase {

    // MARK: - Identity

    func testIDIsLowercasedRawValue() {
        XCTAssertEqual(ModelType(rawValue: "Coffee_Table").id, "coffee_table")
    }

    func testEqualityIsCaseInsensitive() {
        XCTAssertEqual(ModelType(rawValue: "Chair"), ModelType(rawValue: "chair"))
    }

    func testHashingIsCaseInsensitive() {
        let set: Set<ModelType> = [ModelType(rawValue: "Chair"), ModelType(rawValue: "chair")]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Display name

    func testDisplayNameSplitsCamelCase() {
        XCTAssertEqual(ModelType(rawValue: "coffeeTable").displayName, "Coffee Table")
    }

    func testDisplayNameHumanizesSnakeCase() {
        XCTAssertEqual(ModelType(rawValue: "modern_arm_chair_01").displayName, "Modern Arm Chair 01")
    }

    // MARK: - preserveRealWorldScale

    func testBundledPreserveRealWorldScaleTable() {
        XCTAssertTrue(ModelType(rawValue: "chair").preserveRealWorldScale)
        XCTAssertTrue(ModelType(rawValue: "vase").preserveRealWorldScale)
        XCTAssertFalse(ModelType(rawValue: "chandelier").preserveRealWorldScale)
        XCTAssertFalse(ModelType(rawValue: "unknown_widget").preserveRealWorldScale)
    }

    func testManifestOverridesPreserveRealWorldScale() {
        // "chandelier" is false in the hard-coded table, but the manifest says true.
        let type = makeRemote(id: "chandelier", preserve: true)
        XCTAssertTrue(type.preserveRealWorldScale)
    }

    // MARK: - Remote metadata

    func testBundledModelIsNotRemote() {
        let type = ModelType(rawValue: "chair")
        XCTAssertFalse(type.isRemote)
        XCTAssertNil(type.remoteURL)
        XCTAssertTrue(type.hasBakedMaterials, "defaults to textured")
    }

    func testRemoteModelCarriesMetadata() {
        let type = ModelType(
            remoteID: "armchair_01",
            classification: .floor, plane: .horizontal,
            canStack: true, needsPhysics: false, preserveRealWorldScale: true,
            url: URL(string: "https://cdn.example.com/models/armchair_01.usdz")!,
            sha256: "abc123",
            thumbnailURL: URL(string: "https://cdn.example.com/thumbnails/armchair_01.png")!,
            hasBakedMaterials: false
        )
        XCTAssertTrue(type.isRemote)
        XCTAssertEqual(type.classification, .floor)
        XCTAssertEqual(type.plane, .horizontal)
        XCTAssertTrue(type.canStack)
        XCTAssertEqual(type.remoteSHA256, "abc123")
        XCTAssertNotNil(type.remoteThumbnailURL)
        XCTAssertFalse(type.hasBakedMaterials, "untextured models are flagged for grey override")
    }

    func testStandardInitDefaults() {
        let type = ModelType(rawValue: "chair", classification: .floor, plane: .horizontal, canStack: true)
        XCTAssertEqual(type.canStack, true)
        XCTAssertFalse(type.isRemote)
    }

    // MARK: - allCases (local discovery)

    /// `allCases()` used to synthesise `ModelType(rawValue: "placeholder")`
    /// whenever the bundle scan came up empty — which is the *normal* state for
    /// the shipping app, since it bundles no .usdz files and serves the catalog
    /// remotely. That sentinel surfaced as a dead "Placeholder" tile, inflated
    /// every model count, and made saved-project restore look up real models in
    /// a one-entry table.
    func testAllCasesNeverSynthesisesAPlaceholderSentinel() {
        XCTAssertFalse(
            ModelType.allCases().contains { $0.id == "placeholder" },
            "allCases() must report only models that actually exist on disk"
        )
    }

    func testAllCasesReportsExactlyTheDiscoverableUSDZFiles() {
        let discovered = Bundle.xrShareUSDZResources()
        XCTAssertEqual(
            ModelType.allCases().count,
            discovered.count,
            "allCases() must neither drop nor invent entries relative to the file scan"
        )
        if discovered.isEmpty {
            XCTAssertTrue(
                ModelType.allCases().isEmpty,
                "an empty bundle must yield an empty catalog, not a sentinel"
            )
        }
    }

    func testAllCasesEntriesAllResolveToADiscoverableFile() {
        let discoveredIDs = Set(
            Bundle.xrShareUSDZResources().map {
                $0.deletingPathExtension().lastPathComponent.lowercased()
            }
        )
        for modelType in ModelType.allCases() {
            XCTAssertTrue(
                discoveredIDs.contains(modelType.id),
                "\(modelType.rawValue) is listed but has no file behind it"
            )
        }
    }

    // MARK: - Helpers

    private func makeRemote(id: String, preserve: Bool) -> ModelType {
        ModelType(
            remoteID: id, classification: .any, plane: .any,
            canStack: false, needsPhysics: false, preserveRealWorldScale: preserve,
            url: URL(string: "https://example.com/\(id).usdz")!, sha256: nil
        )
    }
}
