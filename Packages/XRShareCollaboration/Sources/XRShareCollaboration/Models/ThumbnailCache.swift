#if SWIFT_PACKAGE
//
//  ThumbnailCache.swift
//  XR Share
//
//  Thumbnail preloading and caching system
//  Loads pre-rendered PNG thumbnails with transparent backgrounds
//

import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
class ThumbnailCache {
    static let shared = ThumbnailCache()

    // Cache for loaded thumbnails
    private var cache: [String: Image] = [:]

    // Loading states for preload flow coordination
    private(set) var isPreloading = false
    private(set) var loadingProgress: Float = 0.0
    private(set) var currentlyLoadingThumbnail: String = ""
    private(set) var preloadingComplete = false

    // Track which thumbnails are currently being loaded to prevent duplicate loads
    private var loadingTasks: [String: Task<Image, Never>] = [:]

    private init() {}

    /// Neutral stand-in shown when a model has no artwork of its own. Catalog
    /// entries legitimately ship without a thumbnail (the render step can fail
    /// for a single model), and a tile must show *something* rather than
    /// spinning forever.
    static let placeholderThumbnail = Image(systemName: "cube")


// MARK: - Preloading

    /// Preload all available model thumbnails at app startup
    func preloadAllThumbnails() async {
        guard !isPreloading && !preloadingComplete else {
            return
        }

        isPreloading = true
        loadingProgress = 0.0

        let modelTypes = ModelType.allCases()
        let totalThumbnails = Float(modelTypes.count)
        var loadedCount: Float = 0

        for modelType in modelTypes {
            currentlyLoadingThumbnail = modelType.displayName
            _ = await loadThumbnail(for: modelType)
            loadedCount += 1
            loadingProgress = loadedCount / max(totalThumbnails, 1)
            }

        isPreloading = false
        preloadingComplete = true
        currentlyLoadingThumbnail = ""
    }


    /// Preload specific thumbnails
    func preloadThumbnails(for modelTypes: [ModelType]) async {
        for modelType in modelTypes where cache[modelType.rawValue] == nil {
            _ = await loadThumbnail(for: modelType)
        }
    }

    /// Routes a model to the right thumbnail source. Remote catalog models have
    /// a pre-rendered PNG hosted alongside the usdz; only bundled/imported
    /// models have a packaged PNG to look up. Sending a remote model down the
    /// bundle path caches the generic "arkit" fallback glyph against its name
    /// and the real artwork can then never replace it.
    func loadThumbnail(for modelType: ModelType) async -> Image? {
        if modelType.isRemote {
            return await getRemoteThumbnail(for: modelType)
        }
        return await generateThumbnail(for: modelType.rawValue, size: CGSize(width: 240, height: 140))
    }


// MARK: - Cache Management

    /// Get a cached thumbnail or load it if not cached
    func getCachedThumbnail(for resource: String, size: CGSize = CGSize(width: 240, height: 140)) async -> Image? {

        // Return cached thumbnail if available
        if let cached = cache[resource] {
            return cached
        }

        return await generateThumbnail(for: resource, size: size)
    }

    /// Returns a pre-rendered thumbnail hosted alongside a remote model:
    /// memory cache → disk cache → download.
    ///
    /// Never returns nil: a manifest entry whose `thumbnail` field is absent
    /// (the pipeline omits it when thumbnail rendering failed) resolves to the
    /// neutral placeholder so the tile stops loading instead of spinning
    /// forever.
    func getRemoteThumbnail(for modelType: ModelType) async -> Image? {
        let key = modelType.rawValue
        if let cached = cache[key] { return cached }
        guard let url = modelType.remoteThumbnailURL else {
            let placeholder = Self.placeholderThumbnail
            cache[key] = placeholder
            return placeholder
        }

        let diskURL = remoteThumbnailDiskURL(for: modelType.id)
        if let image = imageFromFile(diskURL) {
            cache[key] = image
            return image
        }

        if let inFlight = loadingTasks[key] {
            return await inFlight.value
        }
        let task = Task<Image, Never> {
            await ThumbnailDownloadLimiter.shared.acquire()
            let image = await Self.downloadThumbnail(from: url, savingTo: diskURL)
            await ThumbnailDownloadLimiter.shared.release()
            return image ?? Self.placeholderThumbnail
        }
        loadingTasks[key] = task
        let image = await task.value
        loadingTasks[key] = nil
        cache[key] = image
        return image
    }

    private static func downloadThumbnail(from url: URL, savingTo diskURL: URL) async -> Image? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            try? data.write(to: diskURL, options: .atomic)
            return imageFromData(data)
        } catch {
            return nil
        }
    }

    private func remoteThumbnailDiskURL(for id: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RemoteThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(id + ".png")
    }

    private func imageFromFile(_ url: URL) -> Image? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.imageFromData(data)
    }

    private static func imageFromData(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }


    /// Load a pre-rendered thumbnail PNG and cache it
    private func generateThumbnail(for resource: String, size: CGSize) async -> Image? {
        if let cached = cache[resource] {
            return cached
        }

        if let inFlight = loadingTasks[resource] {
            return await inFlight.value
        }

        let task = Task<Image, Never> {
            locateThumbnailPNG(named: resource)
        }
        loadingTasks[resource] = task
        let thumbnailImage = await task.value
        loadingTasks[resource] = nil
        cache[resource] = thumbnailImage
        return thumbnailImage
    }

    /// Locates a pre-rendered PNG thumbnail in the bundle
    private func locateThumbnailPNG(named name: String) -> Image {
        let searchDirectories = ["Thumbnails", "Resources/Thumbnails"]

        // Try multiple case variations (e.g., "Couch" vs "couch")
        let nameVariations = [
            name,
            name.lowercased(),
            name.capitalized
        ]

        // Search all bundles for the PNG file
        for bundle in Bundle.xrShareResourceBundles {
            for subdirectory in searchDirectories {
                for variation in nameVariations {
                    if let url = bundle.url(forResource: variation, withExtension: "png", subdirectory: subdirectory) {
                        #if os(iOS) || os(visionOS)
                        if let uiImage = UIImage(contentsOfFile: url.path) {
                            return Image(uiImage: uiImage)
                        }
                        #elseif os(macOS)
                        if let nsImage = NSImage(contentsOf: url) {
                            return Image(nsImage: nsImage)
                        }
                        #endif
                    }
                }
            }

            // Try without subdirectory
            for variation in nameVariations {
                if let url = bundle.url(forResource: variation, withExtension: "png") {
                    #if os(iOS) || os(visionOS)
                    if let uiImage = UIImage(contentsOfFile: url.path) {
                        return Image(uiImage: uiImage)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOf: url) {
                        return Image(nsImage: nsImage)
                    }
                    #endif
                }
            }
        }

        // Fallback to SF Symbol
        return Image(systemName: "arkit")
    }




    /// Clear the cache
    func clearCache() {
        cache.removeAll()
        preloadingComplete = false
    }

    /// Remove specific thumbnail from cache
    func removeFromCache(_ resource: String) {
        cache.removeValue(forKey: resource)
    }


    /// Check if a thumbnail is cached
    func isCached(_ resource: String) -> Bool {
        return cache[resource] != nil
    }


    /// Get cache status
    var cacheStatus: String {
        return "Cached thumbnails: \(cache.count)/\(ModelType.allCases().count)"
    }


    /// Get cached thumbnail synchronously (for use in SwiftUI views)
    func getCachedThumbnailSync(for resource: String) -> Image? {
        return cache[resource]
    }
}

/// Caps how many thumbnail downloads run at once.
///
/// Catalog cells request their artwork as they scroll into view, so without a
/// ceiling the app can open a connection per visible cell against a catalog of
/// 182 models. Beyond being wasteful, a burst of parallel requests is the
/// pattern most likely to trip rate limiting on the `r2.dev` endpoint — which
/// would make the catalog look broken to a reviewer.
actor ThumbnailDownloadLimiter {
    static let shared = ThumbnailDownloadLimiter(limit: 4)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        guard active >= limit else {
            active += 1
            return
        }
        // Resumed by `release()`, which hands over its permit rather than
        // decrementing, so `active` is already correct on wake.
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(active - 1, 0)
        } else {
            waiters.removeFirst().resume()
        }
    }
}
#endif
