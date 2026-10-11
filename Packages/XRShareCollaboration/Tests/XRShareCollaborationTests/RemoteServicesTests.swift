import CryptoKit
import Foundation
import RealityKit
import XCTest
@testable import XRShareCollaboration

private final class MockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let data: Data
    }

    static var handler: ((URLRequest) throws -> Response)?
    static var requestCount = 0
    private static let lock = NSLock()

    static func reset(handler: @escaping (URLRequest) throws -> Response) {
        lock.lock()
        self.handler = handler
        requestCount = 0
        lock.unlock()
    }

    static func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.requestCount += 1
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(result.data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Hand-wound clock so backoff windows can be tested without sleeping.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        current += interval
        lock.unlock()
    }
}

@MainActor
final class RemoteCatalogServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteCatalogServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        MockURLProtocol.handler = nil
    }

    func testManifestWaitsLessWhenACachedCatalogCanStandIn() async {
        let data = manifestData()
        var observedTimeouts: [TimeInterval] = []
        MockURLProtocol.reset { request in
            observedTimeouts.append(request.timeoutInterval)
            return .init(statusCode: 200, data: data)
        }
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: true)

        // First launch: nothing on disk, so the request gets the full budget.
        _ = await service.loadCatalog()
        // Later launches: the cache written above can stand in for a slow network.
        _ = await service.loadCatalog()

        XCTAssertEqual(observedTimeouts, [
            RemoteCatalogService.coldManifestTimeout,
            RemoteCatalogService.warmManifestTimeout
        ])
        XCTAssertLessThan(RemoteCatalogService.warmManifestTimeout, RemoteCatalogService.coldManifestTimeout)
    }

    func testDisabledCatalogReturnsEmptyWithoutRequest() async {
        MockURLProtocol.reset { _ in XCTFail("Unexpected request"); throw URLError(.badURL) }
        let service = makeService()
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: false)
        let models = await service.loadCatalog()
        XCTAssertTrue(models.isEmpty)
        XCTAssertEqual(MockURLProtocol.count(), 0)
    }

    func testSuccessfulManifestMapsEveryModelFieldAndCachesResponse() async throws {
        let data = manifestData()
        MockURLProtocol.reset { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/base/catalog.json")
            return .init(statusCode: 200, data: data)
        }
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://example.test/base")!, enabled: true)

        let models = await service.loadCatalog()
        XCTAssertEqual(models.count, 2)
        let chair = try XCTUnwrap(models.first { $0.id == "chair_01" })
        XCTAssertEqual(chair.classification, .floor)
        XCTAssertEqual(chair.plane, .horizontal)
        XCTAssertTrue(chair.canStack)
        XCTAssertTrue(chair.needsPhysics)
        XCTAssertFalse(chair.preserveRealWorldScale)
        XCTAssertEqual(chair.remoteURL?.absoluteString, "https://example.test/base/models/chair.usdz")
        XCTAssertEqual(chair.remoteThumbnailURL?.absoluteString, "https://example.test/base/thumbs/chair.png")
        XCTAssertEqual(chair.remoteSHA256, "ABC")
        XCTAssertEqual(chair.remoteFileBytes, 12)
        XCTAssertNotNil(chair.remoteDownloadSizeLabel)
        XCTAssertFalse(chair.hasBakedMaterials)
        XCTAssertEqual(service.manifestCategory(forID: "CHAIR_01"), "seating")

        let unknown = try XCTUnwrap(models.first { $0.id == "future" })
        XCTAssertEqual(unknown.classification, .any)
        XCTAssertEqual(unknown.plane, .any)
        XCTAssertTrue(unknown.hasBakedMaterials, "missing textured defaults to true")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testHTTPFailureFallsBackToCachedManifest() async throws {
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        try manifestData().write(to: cacheURL)
        MockURLProtocol.reset { _ in .init(statusCode: 503, data: Data()) }
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://offline.test")!, enabled: true)
        let models = await service.loadCatalog()
        XCTAssertEqual(models.map(\.id), ["chair_01", "future"])
        XCTAssertEqual(MockURLProtocol.count(), 1)
    }

    func testInvalidNetworkAndInvalidCacheReturnEmpty() async throws {
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        try Data("invalid".utf8).write(to: cacheURL)
        MockURLProtocol.reset { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://offline.test")!, enabled: true)
        let models = await service.loadCatalog()
        XCTAssertTrue(models.isEmpty)
    }

    func testManifestRequestRevalidatesRatherThanIgnoringTheCache() async {
        let data = manifestData()
        MockURLProtocol.reset { request in
            XCTAssertEqual(
                request.cachePolicy, .reloadRevalidatingCacheData,
                "revalidation lets R2 answer an unchanged catalog with a 304"
            )
            return .init(statusCode: 200, data: data)
        }
        let service = makeService(cacheURL: temporaryDirectory.appendingPathComponent("catalog.json"))
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: true)

        let models = await service.loadCatalog()
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(MockURLProtocol.count(), 1)
    }

    func testEmptyResponseBodyKeepsTheCachedCatalog() async throws {
        // If the stored body behind a revalidation is gone, we can be handed a
        // success with nothing in it. That must not blank the catalog or
        // overwrite a good cache with emptiness.
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        let good = manifestData()
        try good.write(to: cacheURL)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: Data()) }
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: true)

        let models = await service.loadCatalog()
        XCTAssertEqual(models.map(\.id), ["chair_01", "future"], "served from the disk cache")
        XCTAssertEqual(try Data(contentsOf: cacheURL), good, "and the cache is untouched")
    }

    func testMalformedEntryDoesNotBlankTheWholeCatalog() async throws {
        let data = Data(
            """
            {
              "version": 1,
              "models": [
                {
                  "id": "chair_01", "displayName": "Chair", "category": "seating",
                  "file": { "url": "models/chair.usdz", "bytes": 12 },
                  "placement": {
                    "classification": "floor", "plane": "horizontal", "canStack": true,
                    "needsPhysics": true, "preserveRealWorldScale": false
                  }
                },
                { "id": "broken", "displayName": "Broken", "category": "seating" }
              ]
            }
            """.utf8
        )
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: data) }
        let service = makeService(cacheURL: temporaryDirectory.appendingPathComponent("catalog.json"))
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: true)

        let models = await service.loadCatalog()
        XCTAssertEqual(models.map(\.id), ["chair_01"], "the bad row drops, the good one survives")
    }

    func testManifestWithNoUsableEntriesFallsBackToTheCache() async throws {
        // Every row malformed decodes to an empty catalog. Serving that would
        // show "Catalog unavailable" and invite another full fetch.
        let cacheURL = temporaryDirectory.appendingPathComponent("catalog.json")
        let good = manifestData()
        try good.write(to: cacheURL)
        let empty = Data(#"{"version": 1, "models": [{"id": "broken"}]}"#.utf8)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: empty) }
        let service = makeService(cacheURL: cacheURL)
        service.configure(baseURL: URL(string: "https://example.test")!, enabled: true)

        let models = await service.loadCatalog()
        XCTAssertEqual(models.map(\.id), ["chair_01", "future"])
        XCTAssertEqual(try Data(contentsOf: cacheURL), good, "a bad fetch never replaces a good cache")
    }

    private func makeService(cacheURL: URL? = nil) -> RemoteCatalogService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return RemoteCatalogService(session: URLSession(configuration: configuration), cacheURL: cacheURL)
    }

    private func manifestData() -> Data {
        Data(
            """
            {
              "version": 1,
              "models": [
                {
                  "id": "Chair_01", "displayName": "Chair", "category": "seating", "textured": false,
                  "file": { "url": "models/chair.usdz", "bytes": 12, "sha256": "ABC" },
                  "thumbnail": { "url": "thumbs/chair.png" },
                  "placement": {
                    "classification": "FLOOR", "plane": "HORIZONTAL", "canStack": true,
                    "needsPhysics": true, "preserveRealWorldScale": false
                  }
                },
                {
                  "id": "future", "displayName": "Future", "category": "unknown",
                  "file": { "url": "models/future.usdz" },
                  "placement": {
                    "classification": "future", "plane": "future", "canStack": false,
                    "needsPhysics": false, "preserveRealWorldScale": true
                  }
                }
              ]
            }
            """.utf8
        )
    }
}

final class ModelFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        MockURLProtocol.handler = nil
    }

    func testBundledModelIsRejectedAndNeverCached() async {
        let store = makeStore()
        let bundled = ModelType(rawValue: "chair")
        let initiallyCached = await store.isCached(bundled)
        XCTAssertFalse(initiallyCached)
        do {
            _ = try await store.localURL(for: bundled)
            XCTFail("Expected notRemote")
        } catch ModelFileStore.StoreError.notRemote {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClearingDownloadsFreesTheSpaceAndTheModelDownloadsAgain() async throws {
        let payload = Data("clear-me".utf8)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: payload) }
        let model = remoteModel(data: payload)
        let store = makeStore()

        _ = try await store.localURL(for: model)
        let used = await store.downloadedBytes()
        XCTAssertEqual(used, Int64(payload.count))

        let removed = await store.removeAllDownloads()
        XCTAssertEqual(removed, 1)
        let usedAfter = await store.downloadedBytes()
        XCTAssertEqual(usedAfter, 0)
        let cached = await store.isCached(model)
        XCTAssertFalse(cached)

        _ = try await store.localURL(for: model)
        XCTAssertEqual(MockURLProtocol.count(), 2, "a cleared model is fetched again on next use")
    }

    func testClearingDownloadsAlsoForgetsPastFailures() async throws {
        MockURLProtocol.reset { _ in .init(statusCode: 503, data: Data()) }
        let payload = Data("recovers".utf8)
        let model = remoteModel(data: payload)
        let store = makeStore()
        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }

        // Without the reset this would still be inside its 60 s backoff.
        _ = await store.removeAllDownloads()
        MockURLProtocol.handler = { _ in .init(statusCode: 200, data: payload) }
        _ = try await store.localURL(for: model)
    }

    func testDownloadVerifiesChecksumCachesAndReusesFile() async throws {
        let payload = Data("valid-usdz".utf8)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: payload) }
        let model = remoteModel(data: payload)
        let store = makeStore()

        let first = try await store.localURL(for: model)
        XCTAssertEqual(try Data(contentsOf: first), payload)
        let cached = await store.isCached(model)
        XCTAssertTrue(cached)
        XCTAssertEqual(MockURLProtocol.count(), 1)
        let second = try await store.localURL(for: model)
        XCTAssertEqual(first, second)
        XCTAssertEqual(MockURLProtocol.count(), 1)
        let failed = await MainActor.run { RemoteDownloadProgress.shared.isFailed(model.id) }
        XCTAssertFalse(failed)
    }

    func testChecksumMismatchDoesNotCacheAndMarksFailure() async {
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: Data("wrong".utf8)) }
        let model = remoteModel(data: Data("expected".utf8))
        let store = makeStore()
        do {
            _ = try await store.localURL(for: model)
            XCTFail("Expected checksumMismatch")
        } catch ModelFileStore.StoreError.checksumMismatch {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let cached = await store.isCached(model)
        XCTAssertFalse(cached)
        let failed = await MainActor.run { RemoteDownloadProgress.shared.isFailed(model.id) }
        XCTAssertTrue(failed)
        let permanent = await MainActor.run { RemoteDownloadProgress.shared.isPermanentlyFailed(model.id) }
        XCTAssertTrue(permanent, "retrying cannot fix bytes that fail their checksum")
    }

    func testHTTPErrorIsReportedAsDownloadFailure() async {
        MockURLProtocol.reset { _ in .init(statusCode: 404, data: Data()) }
        let model = remoteModel(data: Data("expected".utf8))
        do {
            _ = try await makeStore().localURL(for: model)
            XCTFail("Expected downloadFailed")
        } catch ModelFileStore.StoreError.downloadFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let permanent = await MainActor.run { RemoteDownloadProgress.shared.isPermanentlyFailed(model.id) }
        XCTAssertFalse(permanent, "a server error may clear up, so the cell keeps offering Retry")
    }

    func testConcurrentRequestsAreCoalesced() async throws {
        let payload = Data("coalesced".utf8)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: payload) }
        let model = remoteModel(data: payload)
        let store = makeStore()
        async let first = store.localURL(for: model)
        async let second = store.localURL(for: model)
        let urls = try await [first, second]
        XCTAssertEqual(urls[0], urls[1])
        XCTAssertEqual(MockURLProtocol.count(), 1)
    }

    func testBudgetEvictsOlderFilesButKeepsRequestedModel() async throws {
        let old = temporaryDirectory.appendingPathComponent("old.usdz")
        try Data(repeating: 1, count: 20).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: old.path)
        let payload = Data(repeating: 2, count: 20)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: payload) }
        let model = remoteModel(data: payload)
        let store = makeStore(budget: 20)
        let kept = try await store.localURL(for: model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testChecksumMismatchIsNeverRetried() async {
        // A stale manifest sha means the bytes at that URL can never verify.
        // Re-downloading the whole usdz on every tap is pure waste.
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: Data("wrong".utf8)) }
        let model = remoteModel(data: Data("expected".utf8))
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await assertThrows(.checksumMismatch) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 1)

        await assertThrows(.retrySuppressed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 1, "no second download of the same bad bytes")

        clock.advance(30 * 24 * 3600)
        await assertThrows(.retrySuppressed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 1, "an integrity failure never becomes retryable")
        let delay = await store.retryDelay(for: model)
        XCTAssertEqual(delay, Double.infinity)
    }

    func testTransientFailureBacksOffAndTheWindowGrows() async {
        MockURLProtocol.reset { _ in .init(statusCode: 503, data: Data()) }
        let model = remoteModel(data: Data("payload".utf8))
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 1)

        clock.advance(59)
        await assertThrows(.retrySuppressed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 1, "tapping again inside the window costs nothing")

        clock.advance(2)
        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 2, "past the window, one more attempt is allowed")

        clock.advance(61)
        await assertThrows(.retrySuppressed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 2, "the second failure waits 120s, not 60s")

        clock.advance(60)
        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }
        XCTAssertEqual(MockURLProtocol.count(), 3)
    }

    func testCatalogIsToldWhenATransientFailureCanBeRetried() async {
        MockURLProtocol.reset { _ in .init(statusCode: 503, data: Data()) }
        let model = remoteModel(data: Data("payload".utf8))
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let firstFailure = clock.now

        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }
        var retryDate = await MainActor.run { RemoteDownloadProgress.shared.retryDate(for: model.id) }
        XCTAssertEqual(retryDate, firstFailure.addingTimeInterval(60))

        // A tap inside the window is refused and reports the same moment.
        clock.advance(30)
        await assertThrows(.retrySuppressed) { try await store.localURL(for: model) }
        retryDate = await MainActor.run { RemoteDownloadProgress.shared.retryDate(for: model.id) }
        XCTAssertEqual(retryDate, firstFailure.addingTimeInterval(60))
    }

    func testIntegrityFailureHasNoRetryDate() async {
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: Data("wrong".utf8)) }
        let model = remoteModel(data: Data("expected".utf8))
        let store = makeStore()

        await assertThrows(.checksumMismatch) { try await store.localURL(for: model) }
        let retryDate = await MainActor.run { RemoteDownloadProgress.shared.retryDate(for: model.id) }
        XCTAssertNil(retryDate, "waiting cannot fix a damaged file, so there is no countdown")
    }

    func testBackoffDoublesPerFailureAndIsCapped() {
        XCTAssertEqual(ModelFileStore.backoff(forAttempt: 1), 60)
        XCTAssertEqual(ModelFileStore.backoff(forAttempt: 2), 120)
        XCTAssertEqual(ModelFileStore.backoff(forAttempt: 3), 240)
        XCTAssertEqual(ModelFileStore.backoff(forAttempt: 7), 3600)
        XCTAssertEqual(ModelFileStore.backoff(forAttempt: 500), 3600, "capped, never unbounded")
    }

    func testSuccessClearsTheFailureMemo() async throws {
        let payload = Data("recovered".utf8)
        let model = remoteModel(data: payload)
        let clock = TestClock()
        let store = makeStore(clock: clock)

        MockURLProtocol.reset { _ in .init(statusCode: 500, data: Data()) }
        await assertThrows(.downloadFailed) { try await store.localURL(for: model) }

        MockURLProtocol.handler = { _ in .init(statusCode: 200, data: payload) }
        clock.advance(61)
        let url = try await store.localURL(for: model)
        let remaining = await store.retryDelay(for: model)
        XCTAssertNil(remaining, "a success forgets the earlier failure")

        // Caches/ is OS-purgeable: after a purge the model must be fetchable
        // again immediately, not held off by a stale backoff.
        try FileManager.default.removeItem(at: url)
        _ = try await store.localURL(for: model)
        XCTAssertEqual(MockURLProtocol.count(), 3)
    }

    func testDefaultCacheBudgetLimitsWhatAPurgeCanCost() {
        XCTAssertLessThanOrEqual(
            ModelFileStore.defaultCacheBudgetBytes, 500_000_000,
            "Caches/ is purged without notice; a bigger budget is a bigger re-download"
        )
    }

    func testEvictionStopsAsSoonAsItIsUnderBudget() async throws {
        let older = temporaryDirectory.appendingPathComponent("older.usdz")
        let newer = temporaryDirectory.appendingPathComponent("newer.usdz")
        try Data(repeating: 1, count: 20).write(to: older)
        try Data(repeating: 2, count: 20).write(to: newer)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: newer.path
        )

        let payload = Data(repeating: 3, count: 20)
        MockURLProtocol.reset { _ in .init(statusCode: 200, data: payload) }
        let model = remoteModel(data: payload)
        let kept = try await makeStore(budget: 45).localURL(for: model)

        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path), "least recently used goes first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.path), "and nothing more is evicted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    private func assertThrows(
        _ expected: ModelFileStore.StoreError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> URL
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ModelFileStore.StoreError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeStore(budget: Int = 1_000_000, clock: TestClock = TestClock()) -> ModelFileStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return ModelFileStore(
            cacheDirectory: temporaryDirectory,
            cacheBudgetBytes: budget,
            sessionConfiguration: configuration,
            now: { clock.now }
        )
    }

    private func remoteModel(data: Data) -> ModelType {
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ModelType(
            remoteID: "test-\(UUID().uuidString)",
            classification: .floor,
            plane: .horizontal,
            canStack: false,
            needsPhysics: false,
            preserveRealWorldScale: true,
            url: URL(string: "https://models.test/model.usdz")!,
            sha256: sha
        )
    }
}
