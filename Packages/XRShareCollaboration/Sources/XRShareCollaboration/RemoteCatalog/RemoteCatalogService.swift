//
//  RemoteCatalogService.swift
//  XRShareCollaboration
//
//  Fetches and caches the remote catalog manifest, then maps it into the
//  ModelTypes the rest of the app already understands. Network/decoding happen
//  off the main actor; the catalog is cached to disk so the app opens offline.
//

import Foundation
import RealityKit

@MainActor
public final class RemoteCatalogService {
    public static let shared = RemoteCatalogService()

    private let session: URLSession
    private let cacheURLOverride: URL?

    public private(set) var baseURL: URL?
    public private(set) var isEnabled: Bool = false

    /// How long a launch waits for the manifest when there is nothing to fall
    /// back on. A first launch has no catalog without the network, so a slow
    /// connection deserves the full budget.
    static let coldManifestTimeout: TimeInterval = 20

    /// How long a launch waits when a cached manifest is already on disk. The
    /// cache is a complete, working catalog, so making a user on a poor
    /// connection stare at the loading screen for the full cold budget before
    /// using it is pure dead air.
    static let warmManifestTimeout: TimeInterval = 6

    /// manifest id -> category rawValue (e.g. "seating"), for the catalog UI.
    private var categoryByID: [String: String] = [:]

    init(session: URLSession = .shared, cacheURL: URL? = nil) {
        self.session = session
        self.cacheURLOverride = cacheURL
    }

    /// Configure from the app at launch (base URL of the public bucket).
    public func configure(baseURL: URL?, enabled: Bool) {
        self.baseURL = baseURL
        self.isEnabled = enabled
    }

    public func manifestCategory(forID id: String) -> String? {
        categoryByID[id.lowercased()]
    }

    /// Loads the catalog and returns the remote ModelTypes. Tries the network
    /// first, falls back to the last cached manifest, and returns [] on failure.
    public func loadCatalog() async -> [ModelType] {
        guard isEnabled, let baseURL else { return [] }
        let manifestURL = baseURL.appendingPathComponent("catalog.json")

        // A fetch that yields no usable entries (empty document, every row
        // malformed) must not overwrite a good disk cache or blank the catalog,
        // because "Catalog unavailable" invites a Retry tap and another fetch.
        let timeout = hasCachedManifest ? Self.warmManifestTimeout : Self.coldManifestTimeout
        let manifest: CatalogManifest?
        if let fetched = await fetchManifest(from: manifestURL, timeout: timeout), !fetched.models.isEmpty {
            cacheManifest(fetched)
            manifest = fetched
        } else {
            manifest = cachedManifest()
        }
        guard let manifest else { return [] }

        categoryByID = Dictionary(
            manifest.models.map { ($0.id.lowercased(), $0.category) },
            uniquingKeysWith: { first, _ in first }
        )
        return manifest.models.map { modelType(from: $0, baseURL: baseURL) }
    }

    // MARK: - Mapping

    private func modelType(from entry: CatalogManifest.Entry, baseURL: URL) -> ModelType {
        ModelType(
            remoteID: entry.id,
            classification: classification(entry.placement.classification),
            plane: alignment(entry.placement.plane),
            canStack: entry.placement.canStack,
            needsPhysics: entry.placement.needsPhysics,
            preserveRealWorldScale: entry.placement.preserveRealWorldScale,
            url: baseURL.appendingPathComponent(entry.file.url),
            sha256: entry.file.sha256,
            fileBytes: entry.file.bytes,
            thumbnailURL: entry.thumbnail.map { baseURL.appendingPathComponent($0.url) },
            hasBakedMaterials: entry.textured ?? true
        )
    }

    private func classification(_ value: String) -> AnchoringComponent.Target.Classification {
        switch value.lowercased() {
        case "floor": return .floor
        case "wall": return .wall
        case "ceiling": return .ceiling
        case "table": return .table
        default: return .any
        }
    }

    private func alignment(_ value: String) -> AnchoringComponent.Target.Alignment {
        switch value.lowercased() {
        case "horizontal": return .horizontal
        case "vertical": return .vertical
        default: return .any
        }
    }

    // MARK: - Networking

    private func fetchManifest(from url: URL, timeout: TimeInterval) async -> CatalogManifest? {
        var request = URLRequest(url: url)
        // Revalidate rather than ignore the cache: the manifest carries an ETag
        // and Last-Modified, so an unchanged catalog costs a 304 with no body
        // instead of re-downloading all 182 entries on every launch and every
        // Retry tap. URLSession serves the stored body on a 304, so the decode
        // below sees the same JSON it would have downloaded.
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            // No stored body to revalidate against (or a truncated response):
            // fall through to the disk cache instead of decoding nothing.
            guard !data.isEmpty else { return nil }
            return try JSONDecoder().decode(CatalogManifest.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Disk cache (offline fallback)

    private var cacheURL: URL? {
        if let cacheURLOverride {
            return cacheURLOverride
        }
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("catalog.json")
    }

    private func cacheManifest(_ manifest: CatalogManifest) {
        guard var cacheURL, let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: cacheURL, options: .atomic)

        // Application Support is backed up to iCloud, but this file is a
        // re-downloadable copy of the catalog, not user data. Apple's storage
        // guidance is that regenerable content must not consume a user's
        // backup quota.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? cacheURL.setResourceValues(values)
    }

    private var hasCachedManifest: Bool {
        guard let cacheURL else { return false }
        return FileManager.default.fileExists(atPath: cacheURL.path)
    }

    private func cachedManifest() -> CatalogManifest? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }
}
