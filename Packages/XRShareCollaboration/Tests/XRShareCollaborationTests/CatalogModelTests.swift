import XCTest
@testable import XRShareCollaboration

@available(visionOS 26.0, *)
final class CatalogModelTests: XCTestCase {

    /// The pipeline writes these category strings into catalog.json; the app
    /// maps them back with ModelCategory(rawValue:). This guards that contract.
    func testManifestCategoryStringsRoundTrip() {
        let pipelineCategories = ["seating", "beds", "storage", "lighting",
                                  "decor", "media", "tables", "unknown"]
        for raw in pipelineCategories {
            XCTAssertNotNil(
                CollaborativeSessionController.ModelCategory(rawValue: raw),
                "ModelCategory is missing a case for manifest category '\(raw)'"
            )
        }
    }

    func testEveryCategoryHasANonEmptyLabel() {
        for category in CollaborativeSessionController.ModelCategory.allCases {
            XCTAssertFalse(category.label.isEmpty, "\(category) has no label")
        }
    }

    func testEverySourceHasANonEmptyLabel() {
        for source in CollaborativeSessionController.ModelSource.allCases {
            XCTAssertFalse(source.label.isEmpty, "\(source) has no label")
        }
    }

    func testUnknownCategoryFallsBackForUnmappedString() {
        XCTAssertNil(CollaborativeSessionController.ModelCategory(rawValue: "spaceship"))
    }

    // MARK: - Catalog membership
    //
    // A successful remote catalog load replaces `modelManager.modelTypes`
    // wholesale, and local models are only scanned once (in ModelManager.init).
    // The browsable catalog therefore has to be the *union* of the two, or a
    // model imported during the session is reported as "Import Successful" and
    // then never appears — leaving Source → Imports permanently empty.

    @MainActor
    func testCatalogMergeUnionsRemoteAndLocalTypes() {
        let merged = CollaborativeSessionController.mergedCatalogTypes(
            remote: [makeRemote(id: "armchair_01"), makeRemote(id: "floor_lamp")],
            local: [ModelType(rawValue: "my_scan")]
        )
        XCTAssertEqual(merged.map(\.id), ["armchair_01", "floor_lamp", "my_scan"])
    }

    @MainActor
    func testCatalogMergeDedupesCaseInsensitivelyAndPrefersTheCatalogEntry() {
        let merged = CollaborativeSessionController.mergedCatalogTypes(
            remote: [makeRemote(id: "armchair_01")],
            local: [ModelType(rawValue: "Armchair_01")]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(
            merged[0].isRemote,
            "the manifest entry carries download + scale metadata a local scan can't infer"
        )
    }

    @MainActor
    func testCatalogMergeWithNoLocalModelsIsJustTheCatalog() {
        let remote = [makeRemote(id: "armchair_01")]
        XCTAssertEqual(
            CollaborativeSessionController.mergedCatalogTypes(remote: remote, local: []).map(\.id),
            ["armchair_01"]
        )
    }

    @MainActor
    func testRefreshAvailableModelsExposesRemoteCatalogPlusLocalTypes() {
        let controller = CollaborativeSessionController()
        controller.modelManager.modelTypes = [makeRemote(id: "armchair_01"), makeRemote(id: "floor_lamp")]

        controller.refreshAvailableModels()

        let ids = controller.availableModels.map(\.id)
        XCTAssertEqual(Array(ids.prefix(2)), ["armchair_01", "floor_lamp"])
        XCTAssertEqual(Set(ids).count, ids.count, "the union must be deduped")
        XCTAssertFalse(ids.contains("placeholder"))
        XCTAssertEqual(
            Set(ids).subtracting(["armchair_01", "floor_lamp"]),
            Set(ModelType.allCases().map(\.id)),
            "everything beyond the manifest must be a locally discoverable model"
        )
    }

    @MainActor
    func testRemoteCatalogEntriesAreReportedAsPresets() {
        let controller = CollaborativeSessionController()
        controller.modelManager.modelTypes = [makeRemote(id: "armchair_01")]

        controller.refreshAvailableModels()

        XCTAssertEqual(controller.availableModels.first?.source, .presets)
    }

    private func makeRemote(id: String) -> ModelType {
        ModelType(
            remoteID: id,
            classification: .floor,
            plane: .horizontal,
            canStack: false,
            needsPhysics: false,
            preserveRealWorldScale: true,
            url: URL(string: "https://cdn.example.com/models/\(id).usdz")!,
            sha256: nil
        )
    }
}
