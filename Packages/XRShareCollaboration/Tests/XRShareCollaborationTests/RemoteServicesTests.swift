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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

    private func makeStore(budget: Int = 1_000_000) -> ModelFileStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return ModelFileStore(
            cacheDirectory: temporaryDirectory,
            cacheBudgetBytes: budget,
            sessionConfiguration: configuration
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
