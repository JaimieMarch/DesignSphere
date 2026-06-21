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

    // MARK: - Live integration (requires network + the R2 bucket)

    @MainActor
    func testLiveCatalogLoadsAndDownloadsModel() async throws {
        let base = URL(string: "https://pub-efd589f26cb24d3db0c409b9416b4ecd.r2.dev")!
        RemoteCatalogService.shared.configure(baseURL: base, enabled: true)

        let types = await RemoteCatalogService.shared.loadCatalog()
        XCTAssertGreaterThan(types.count, 100, "expected the full remote catalog")

        let first = try XCTUnwrap(types.first { $0.isRemote })
        XCTAssertNotNil(first.remoteURL)
        XCTAssertNotNil(RemoteCatalogService.shared.manifestCategory(forID: first.id))

        let url = try await ModelFileStore.shared.localURL(for: first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let cached = await ModelFileStore.shared.isCached(first)
        XCTAssertTrue(cached)
    }
}
