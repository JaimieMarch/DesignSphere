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

        let manifest: CatalogManifest?
        if let fetched = await fetchManifest(from: manifestURL) {
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

    private func fetchManifest(from url: URL) async -> CatalogManifest? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
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
        guard let cacheURL, let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func cachedManifest() -> CatalogManifest? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }
}
