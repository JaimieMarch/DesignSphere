#if SWIFT_PACKAGE
//
//  ModelCache.swift
//  XR Share
//
//  To provide model preloading and caching functionality
//

import Foundation
import RealityKit
import Combine

@MainActor
class ModelCache: ObservableObject {
    static let shared = ModelCache()
    
    // Cache for loaded model entities
    private var cache: [ModelType: ModelEntity] = [:]
    
    // Loading states for UI feedback
    @Published var isPreloading = false
    @Published var loadingProgress: Float = 0.0
    @Published var currentlyLoadingModel: String = ""
    @Published var preloadingComplete = false
    
    
    // Track which models are currently being loaded to prevent duplicate loads
    private var loadingModels: Set<ModelType> = []
    
    private init() {}
    
// MARK: - Preloading
    
    /// Preload all available models at app startup
    func preloadAllModels() async {
        guard !isPreloading && !preloadingComplete else {
            print("ModelCache: already preloading or has arleady completed")
            return
        }
        
        isPreloading = true
        loadingProgress = 0.0
        
        let modelTypes = ModelType.allCases()
        let totalModels = Float(modelTypes.count)
        var loadedCount: Float = 0
        
        print("ModelCache: Starting preload of \(modelTypes.count) models")
        
        
        for modelType in modelTypes {
            currentlyLoadingModel = modelType.displayName
            
            // Load the model if not already cached
            if cache[modelType] == nil {
                _ = await loadModel(modelType)
            }
            
            
            loadedCount += 1
            loadingProgress = loadedCount / totalModels
            
            print("ModelCache: Loaded \(modelType.rawValue) (\(Int(loadingProgress * 100))% complete)")
        }
        
        
        isPreloading = false
        preloadingComplete = true
        currentlyLoadingModel = ""
        print("ModelCache: Preloading complete. \(cache.count) models cached.")
    }
    
    
    
    /// Preload specific models if needed
    func preloadModels(_ modelTypes: [ModelType]) async {
        for modelType in modelTypes {
            if cache[modelType] == nil {
                _ = await loadModel(modelType)
            }
        }
    }
    
// MARK: - Cache Management
    
    
    /// Get a cached model entity or load it if not cached
    func getCachedEntity(for modelType: ModelType) async -> ModelEntity? {
        
        // Return cached entity if available
        if let cached = cache[modelType] {
            print("ModelCache: Returning cached entity for \(modelType.rawValue)")
            return cached.clone(recursive: true)
        }
        
        
        // Load if not cached
        print("ModelCache: Cache miss for \(modelType.rawValue), loading...")
        let entity = await loadModel(modelType)
        return entity?.clone(recursive: true)
    }
    
    
    /// Load a model and and then cache it
    private func loadModel(_ modelType: ModelType) async -> ModelEntity? {
        // Prevent duplicate loading
        guard !loadingModels.contains(modelType) else {
            print("ModelCache: \(modelType.rawValue) is already being loaded")
            // Wait for existing load to complete
            while loadingModels.contains(modelType) {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            return cache[modelType]
        }
        
        loadingModels.insert(modelType)
        defer { loadingModels.remove(modelType) }
        
        var modelEntity: ModelEntity?

        if let modelURL = Bundle.xrShareLocateUSDZ(named: modelType.rawValue) {
            do {
                modelEntity = try await ModelEntity(contentsOf: modelURL)
            } catch {
                print("ModelCache: Failed to load \(modelType.rawValue) from URL: \(error)")
    }
        }

        if modelEntity == nil {
            let filename = "\(modelType.rawValue).usdz"
            for bundle in Bundle.xrShareResourceBundles {
                do {
                    modelEntity = try await ModelEntity(named: filename, in: bundle)
                    break
                } catch {
                    continue
                        }
                }
        }

        
        if let entity = modelEntity {
            cache[modelType] = entity
            print("ModelCache: Successfully cached \(modelType.rawValue)")
            return entity
        }

        print("ModelCache: Failed to find \(modelType.rawValue)")
        
        return nil
    }
    
    
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
        preloadingComplete = false
        print("ModelCache: Cache cleared")
    }
    
    /// Remove specific model from cache
    func removeFromCache(_ modelType: ModelType) {
        cache.removeValue(forKey: modelType)
        print("ModelCache: Removed \(modelType.rawValue) from cache")
    }
    
    
    /// Check if a model is cached
    func isCached(_ modelType: ModelType) -> Bool {
        return cache[modelType] != nil
    }
    
    
    /// Get cache status
    var cacheStatus: String {
        return "Cached models: \(cache.count)/\(ModelType.allCases().count)"
    }
}
#endif



