#if SWIFT_PACKAGE
//
//  ThumbnailCache.swift
//  XR Share
//
//  Thumbnail preloading and caching system
//

import SwiftUI
import QuickLookThumbnailing
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
        
        print("ThumbnailCache: Starting  preload of \(modelTypes.count) thumbnails")
        
        // Generate thumbnails concurrently for better performance
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
    
    /// Get a cached thumbnail or generate it if not cached
    func getCachedThumbnail(for resource: String, size: CGSize = CGSize(width: 240, height: 140)) async -> Image? {
        
        // Return cached thumbnail if available
        if let cached = cache[resource] {
            print("ThumbnailCache: Returning cached thumbnail for \(resource)")
            return cached
        }
        
        // Generate if not cached
        print("ThumbnailCache: Cache miss for \(resource), generating...")
        return await generateThumbnail(for: resource, size: size)
    }
    
    
    /// Generate a thumbnail and cache it
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
        
        guard let url = Bundle.xrShareLocateUSDZ(named: resource) else {
            let fallbackImage = Image(systemName: "arkit")
            cache[resource] = fallbackImage
            print("ThumbnailCache: No file found for \(resource), using fallback")
            return fallbackImage
        }
        
        
        let scale: CGFloat = 2.0
        
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        
        
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, _, _ in
                Task { @MainActor in
                    let generatedImage: Image
                    
                    if let thumbnail = thumbnail {
                        
//                        #if os(iOS)
//                        generatedImage = Image(uiImage: thumbnail.uiImage)
                        
                   
                        generatedImage = Image(thumbnail.cgImage, scale: scale, label: Text(resource))
                        
                        print("ThumbnailCache: Successfully generated thumbnail for \(resource)")
                        
                    } else {
                        
                        
                        generatedImage = Image(systemName: "arkit")
                        
                        print("ThumbnailCache: Failed to generate thumbnail for \(resource), using fallback")
                    }
                    
                    self.cache[resource] = generatedImage
                    continuation.resume(returning: generatedImage)
                }
            }
        }
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
