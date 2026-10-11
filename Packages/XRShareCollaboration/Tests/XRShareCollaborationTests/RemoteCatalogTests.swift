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
        XCTAssertEqual(entry.file.bytes, 123)
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

    func testMalformedEntryIsDroppedInsteadOfFailingTheDocument() throws {
        // The middle entry is missing `placement.canStack`. Before lenient
        // decoding this threw, `fetchManifest` returned nil, and every user
        // without a disk cache saw "Catalog unavailable" - then retried, which
        // cost another full manifest fetch.
        let json = """
        {
          "version": 1,
          "models": [
            {
              "id": "good_01", "displayName": "Good 01", "category": "seating",
              "file": { "url": "models/good_01.usdz", "bytes": 10 },
              "placement": {
                "classification": "floor", "plane": "horizontal",
                "canStack": true, "needsPhysics": false, "preserveRealWorldScale": true
              }
            },
            {
              "id": "broken", "displayName": "Broken", "category": "seating",
              "file": { "url": "models/broken.usdz", "bytes": 10 },
              "placement": {
                "classification": "floor", "plane": "horizontal",
                "needsPhysics": false, "preserveRealWorldScale": true
              }
            },
            {
              "id": "good_02", "displayName": "Good 02", "category": "decor",
              "file": { "url": "models/good_02.usdz", "bytes": 10 },
              "placement": {
                "classification": "table", "plane": "horizontal",
                "canStack": false, "needsPhysics": false, "preserveRealWorldScale": true
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.models.map(\.id), ["good_01", "good_02"])
    }

    func testMissingVersionStillFailsTheWholeDocument() {
        // `version` stays strict: a document without it is not a catalog.
        let json = """
        { "models": [] }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8)))
    }

    func testManifestSurvivesTheDiskCacheRoundTrip() throws {
        // The offline fallback re-encodes what it decoded, so `encode(to:)` must
        // still work alongside the custom `init(from:)`.
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-06-20T00:00:00+00:00",
          "models": [
            {
              "id": "lamp_01", "displayName": "Lamp 01", "category": "lighting", "textured": false,
              "file": { "url": "models/lamp_01.usdz", "bytes": 9, "sha256": "def" },
              "thumbnail": { "url": "thumbs/lamp_01.png", "bytes": null, "sha256": null },
              "placement": {
                "classification": "table", "plane": "horizontal",
                "canStack": false, "needsPhysics": true, "preserveRealWorldScale": false
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        let restored = try JSONDecoder().decode(
            CatalogManifest.self, from: JSONEncoder().encode(manifest)
        )
        XCTAssertEqual(restored.version, 1)
        XCTAssertEqual(restored.generatedAt, manifest.generatedAt)
        XCTAssertEqual(restored.models.map(\.id), ["lamp_01"])
        XCTAssertEqual(restored.models[0].thumbnail?.url, "thumbs/lamp_01.png")
        XCTAssertEqual(restored.models[0].textured, false)
        XCTAssertTrue(restored.models[0].placement.needsPhysics)
    }

    func testRemoteModelTypeCarriesManifestMetadata() {
        let type = ModelType(
            remoteID: "armchair_01",
            classification: .floor, plane: .horizontal,
            canStack: true, needsPhysics: false, preserveRealWorldScale: true,
            url: URL(string: "https://example.com/models/armchair_01.usdz")!,
            sha256: "abc",
            fileBytes: 12_345_678
        )
        XCTAssertTrue(type.isRemote)
        XCTAssertEqual(type.remoteSHA256, "abc")
        XCTAssertEqual(type.remoteFileBytes, 12_345_678)
        XCTAssertNotNil(type.remoteDownloadSizeLabel)
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

    @MainActor
    func testPermanentFailureSurvivesALaterPlainFailureUntilRetried() {
        let progress = RemoteDownloadProgress.shared
        let id = "unit_test_model_\(UUID().uuidString)"

        progress.begin(id)
        progress.fail(id, permanent: true)
        XCTAssertTrue(progress.isPermanentlyFailed(id.uppercased()))

        // The model manager re-raises a failure the store already classified.
        progress.fail(id)
        XCTAssertTrue(progress.isPermanentlyFailed(id), "a plain failure must not downgrade it")
        XCTAssertTrue(progress.isFailed(id))

        // A fresh attempt starts from a clean slate.
        progress.begin(id)
        XCTAssertFalse(progress.isPermanentlyFailed(id))
        progress.fail(id, permanent: true)
        progress.clearFailure(id)
        XCTAssertFalse(progress.isFailed(id))
        XCTAssertFalse(progress.isPermanentlyFailed(id))
    }

    @MainActor
    func testProgressUpdateAfterCompletionDoesNotStrandTheTile() {
        // Progress hops to the main actor on its own Task, separately from
        // finish/fail, so a trailing update can land after the download ends.
        // It must not leave the cell under a permanent 100% overlay.
        let progress = RemoteDownloadProgress.shared
        let id = "unit_test_model_\(UUID().uuidString)"

        progress.begin(id)
        ModelFileStore.reportProgress(id, 0.5)
        XCTAssertEqual(progress.fraction(for: id), 0.5, "in-flight progress still shows")

        progress.finish(id)
        ModelFileStore.reportProgress(id, 1.0)
        XCTAssertNil(progress.fraction(for: id), "a late update after finish is ignored")

        progress.begin(id)
        progress.fail(id)
        ModelFileStore.reportProgress(id, 1.0)
        XCTAssertNil(progress.fraction(for: id), "a late update after failure is ignored")
        XCTAssertTrue(progress.isFailed(id), "and it does not hide the retry affordance")
        progress.clearFailure(id)
    }

    // MARK: - Background catalog load

    @available(visionOS 26.0, *)
    @MainActor
    func testBackgroundPreloadShowsLoadingAtOnceAndCanBeAwaited() async {
        // Nothing listens on port 1, so the manifest request fails fast and the
        // load settles on whatever the disk cache holds (ready or unavailable).
        let service = RemoteCatalogService.shared
        let previousURL = service.baseURL
        let previousEnabled = service.isEnabled
        service.configure(baseURL: URL(string: "https://127.0.0.1:1")!, enabled: true)
        defer { service.configure(baseURL: previousURL, enabled: previousEnabled) }

        let controller = CollaborativeSessionController()
        controller.startPreload()
        XCTAssertEqual(controller.remoteCatalogState, .loading,
                       "the grid must never flash an empty result before the load starts")

        await controller.waitForCatalog()
        XCTAssertNotEqual(controller.remoteCatalogState, .loading)
    }

    @available(visionOS 26.0, *)
    @MainActor
    func testWaitingWithoutABackgroundLoadReturnsImmediately() async {
        let controller = CollaborativeSessionController()
        await controller.waitForCatalog()
        XCTAssertEqual(controller.remoteCatalogState, .ready)
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
