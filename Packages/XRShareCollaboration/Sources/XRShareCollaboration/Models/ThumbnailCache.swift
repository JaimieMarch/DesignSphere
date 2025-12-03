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

#if os(iOS)
import UIKit
#endif

@MainActor
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    
    // Cache for loaded thumbnails
    private var cache: [String: Image] = [:]
    
    // Loading states for UI feedback
    @Published var isPreloading = false
    @Published var loadingProgress: Float = 0.0
    @Published var currentlyLoadingThumbnail: String = ""
    @Published var preloadingComplete = false
    
    // Track which thumbnails are currently being loaded to prevent duplicate loads
    private var loadingThumbnails: Set<String> = []
    
    private init() {}
    

// MARK: - Preloading
    
    /// Preload all available model thumbnails at app startup
    func preloadAllThumbnails() async {
        guard !isPreloading && !preloadingComplete else {
            print("ThumbnailCache: Already preloading or completed")
            return
        }
        
        isPreloading = true
        loadingProgress = 0.0
        
        let modelTypes = ModelType.allCases()
        let totalThumbnails = Float(modelTypes.count)
        var loadedCount: Float = 0
        
        print("ThumbnailCache: Starting preload of \(modelTypes.count) pre-rendered thumbnails")

        // Load thumbnails concurrently for better performance
        await withTaskGroup(of: Void.self) { group in
            for modelType in modelTypes {
                group.addTask {
                    _ = await self.generateThumbnail(for: modelType.rawValue, size: CGSize(width: 240, height: 140))
                }
            }
            
            // Track progress as tasks complete
            for await _ in group {
                loadedCount += 1
                loadingProgress = loadedCount / totalThumbnails
                
                let currentModel = modelTypes[Int(loadedCount) - 1]
                currentlyLoadingThumbnail = currentModel.displayName
                
                print("ThumbnailCache:  Loaded thumbnail for \(currentModel.rawValue) (\(Int(loadingProgress * 100))% complete)")
            }
                }
        
        isPreloading = false
        preloadingComplete = true
        currentlyLoadingThumbnail = ""
        print("ThumbnailCache: Preloading complete. \(cache.count) thumbnails cached.")
    }
    
    
    /// Preload specific thumbnails
    func preloadThumbnails(for modelTypes: [ModelType]) async {
        for modelType in modelTypes {
            if cache[modelType.rawValue] == nil {
                _ = await generateThumbnail(for: modelType.rawValue, size: CGSize(width: 240, height: 140))
            }
            }
    }
    

// MARK: - Cache Management
    
    /// Get a cached thumbnail or load it if not cached
    func getCachedThumbnail(for resource: String, size: CGSize = CGSize(width: 240, height: 140)) async -> Image? {

        // Return cached thumbnail if available
        if let cached = cache[resource] {
            print("ThumbnailCache: Returning cached thumbnail for \(resource)")
            return cached
        }

        // Load if not cached
        print("ThumbnailCache: Cache miss for \(resource), loading...")
        return await generateThumbnail(for: resource, size: size)
    }
    
    
    /// Load a pre-rendered thumbnail PNG and cache it
    private func generateThumbnail(for resource: String, size: CGSize) async -> Image? {

        // Prevent duplicate loading
        guard !loadingThumbnails.contains(resource) else {
            print("ThumbnailCache: \(resource) is already being loaded")

            // Wait for existing load to complete
            while loadingThumbnails.contains(resource) {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }

            return cache[resource]
        }

        loadingThumbnails.insert(resource)
        defer { loadingThumbnails.remove(resource) }

        // Try to locate pre-rendered PNG thumbnail
        let thumbnailImage = locateThumbnailPNG(named: resource)

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
                            print("ThumbnailCache: Successfully loaded PNG thumbnail for \(name) at \(url.path)")
                            return Image(uiImage: uiImage)
                        }
                        #elseif os(macOS)
                        if let nsImage = NSImage(contentsOf: url) {
                            print("ThumbnailCache: Successfully loaded PNG thumbnail for \(name)")
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
                        print("ThumbnailCache: Successfully loaded PNG thumbnail for \(name) at \(url.path)")
                        return Image(uiImage: uiImage)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOf: url) {
                        print("ThumbnailCache: Successfully loaded PNG thumbnail for \(name)")
                        return Image(nsImage: nsImage)
                    }
                    #endif
                }
            }
        }

        // Fallback to SF Symbol
        print("ThumbnailCache: No PNG found for '\(name)' (tried variations), using fallback icon")
        return Image(systemName: "arkit")
    }
    
    
    
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
        preloadingComplete = false
        print("ThumbnailCache: Cache cleared")
    }
    
    /// Remove specific thumbnail from cache
    func removeFromCache(_ resource: String) {
        cache.removeValue(forKey: resource)
        print("ThumbnailCache: Removed \(resource) from cache")
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
#endif
