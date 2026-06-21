import XCTest
@testable import XRShareCollaboration

final class RemoteCatalogTests: XCTestCase {

    // MARK: - Manifest decoding (offline, deterministic)

    func testManifestDecodes() throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-06-20T00:00:00+00:00",
          "models": [
            {
              "id": "armchair_01",
              "displayName": "Armchair 01",
              "category": "seating",
              "file": { "url": "models/armchair_01.usdz", "bytes": 123, "sha256": "abc" },
              "placement": {
                "classification": "floor", "plane": "horizontal",
                "canStack": true, "needsPhysics": false, "preserveRealWorldScale": true
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.models.count, 1)
        let entry = manifest.models[0]
        XCTAssertEqual(entry.id, "armchair_01")
        XCTAssertEqual(entry.category, "seating")
        XCTAssertEqual(entry.file.url, "models/armchair_01.usdz")
        XCTAssertEqual(entry.placement.classification, "floor")
        XCTAssertTrue(entry.placement.preserveRealWorldScale)
    }

    func testManifestDecodesWithoutOptionalFields() throws {
        // Older manifests may omit `thumbnail` and `textured`.
        let json = """
        {
          "version": 1,
          "models": [
            {
              "id": "vase_01", "displayName": "Vase 01", "category": "decor",
              "file": { "url": "models/vase_01.usdz", "bytes": 1, "sha256": null },
              "placement": {
                "classification": "table", "plane": "horizontal",
                "canStack": false, "needsPhysics": false, "preserveRealWorldScale": true
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        let entry = manifest.models[0]
        XCTAssertNil(entry.thumbnail)
        XCTAssertNil(entry.textured)
        XCTAssertNil(entry.file.sha256)
        XCTAssertNil(manifest.generatedAt)
    }

    func testRemoteModelTypeCarriesManifestMetadata() {
        let type = ModelType(
            remoteID: "armchair_01",
            classification: .floor, plane: .horizontal,
            canStack: true, needsPhysics: false, preserveRealWorldScale: true,
            url: URL(string: "https://example.com/models/armchair_01.usdz")!,
            sha256: "abc"
        )
        XCTAssertTrue(type.isRemote)
        XCTAssertEqual(type.remoteSHA256, "abc")
        XCTAssertTrue(type.canStack)
        XCTAssertTrue(type.preserveRealWorldScale)  // override beats the hard-coded table
    }

    // MARK: - Download progress / failure state

    @MainActor
    func testDownloadFailureTrackingIsCaseInsensitive() {
        let progress = RemoteDownloadProgress.shared
        let id = "unit_test_model_\(UUID().uuidString)"

        progress.begin(id)
        XCTAssertEqual(progress.fraction(for: id), 0)
        XCTAssertFalse(progress.isFailed(id))

        progress.fail(id)
        XCTAssertNil(progress.fraction(for: id), "failure clears in-progress state")
        XCTAssertTrue(progress.isFailed(id.uppercased()), "lookup is case-insensitive")

        // begin (a retry) clears the failure
        progress.begin(id)
        XCTAssertFalse(progress.isFailed(id))
        progress.finish(id)
    }

    // MARK: - Live integration (requires network + the R2 bucket)

    @MainActor
    func testLiveCatalogLoadsAndDownloadsModel() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_CATALOG_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_CATALOG_TESTS=1 to run the R2 integration test")
        }
        let base = URL(string: "https://pub-efd589f26cb24d3db0c409b9416b4ecd.r2.dev")!
        RemoteCatalogService.shared.configure(baseURL: base, enabled: true)

        let types = await RemoteCatalogService.shared.loadCatalog()
        XCTAssertGreaterThan(types.count, 100, "expected the full remote catalog")

        let first = try XCTUnwrap(types.first { $0.isRemote })
        XCTAssertNotNil(first.remoteURL)
        XCTAssertNotNil(first.remoteThumbnailURL, "manifest should map a thumbnail URL")
        XCTAssertNotNil(RemoteCatalogService.shared.manifestCategory(forID: first.id))

        let url = try await ModelFileStore.shared.localURL(for: first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let cached = await ModelFileStore.shared.isCached(first)
        XCTAssertTrue(cached)
    }
}
