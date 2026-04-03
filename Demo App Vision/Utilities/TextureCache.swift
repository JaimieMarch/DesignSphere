// TextureCache.swift
// Provides memoized texture loading to avoid repeated disk access

import RealityKit
import Foundation

/// Thread-safe cache for TextureResource objects to avoid repeated disk loads
@MainActor
final class TextureCache {
    /// Shared singleton instance
    static let shared = TextureCache()

    /// Cache storage mapping texture names to loaded resources
    private var cache: [String: TextureResource] = [:]

    /// Private initializer to enforce singleton pattern
    private init() {}

    /// Retrieves a texture from cache or loads it if not cached
    /// - Parameter named: The texture resource name (without extension)
    /// - Returns: The cached or newly loaded TextureResource, or nil if loading fails
    func texture(named name: String) -> TextureResource? {
        // Return cached texture if available
        if let cached = cache[name] {
            return cached
        }

        // Attempt to load and cache the texture
        do {
            let texture = try TextureResource.load(named: name)
            cache[name] = texture
            #if DEBUG
            print("TextureCache: Loaded and cached texture '\(name)'")
            #endif
            return texture
        } catch {
            #if DEBUG
            print("TextureCache: Failed to load texture '\(name)': \(error)")
            #endif
            return nil
        }
    }

    /// Preloads a set of textures into the cache
    /// - Parameter names: Array of texture resource names to preload
    func preload(_ names: [String]) {
        for name in names {
            _ = texture(named: name)
        }
    }

    /// Clears all cached textures (useful for memory pressure handling)
    func clearCache() {
        let count = cache.count
        cache.removeAll()
        #if DEBUG
        print("TextureCache: Cleared \(count) cached textures")
        #endif
    }

    /// Returns the number of currently cached textures
    var cacheCount: Int {
        cache.count
    }
}
