#if SWIFT_PACKAGE
//
//  ModelCache.swift
//  XR Share
//
//  To provide model preloading and caching functionality
//

import Foundation
import RealityKit

@MainActor
class ModelCache {
    static let shared = ModelCache()
    
    // Cache for loaded model entities
    private var cache: [ModelType: ModelEntity] = [:]
    
    // Loading states for preload flow coordination
    private(set) var isPreloading = false
    private(set) var loadingProgress: Float = 0.0
    private(set) var currentlyLoadingModel: String = ""
    private(set) var preloadingComplete = false
    
    
    // Track which models are currently being loaded to prevent duplicate loads
    private var loadingTasks: [ModelType: Task<ModelEntity?, Never>] = [:]
    
    private init() {}
    
// MARK: - Preloading
    
    /// Preload all available models at app startup
    func preloadAllModels() async {
        guard !isPreloading && !preloadingComplete else {
            return
        }
        
        isPreloading = true
        loadingProgress = 0.0
        
        let modelTypes = ModelType.allCases()
        let totalModels = Float(modelTypes.count)
        var loadedCount: Float = 0
        
        for modelType in modelTypes {
            currentlyLoadingModel = modelType.displayName
            
            // Load the model if not already cached
            if cache[modelType] == nil {
                _ = await loadModel(modelType)
            }
            
            
            loadedCount += 1
            loadingProgress = loadedCount / totalModels
            
        }
        
        
        isPreloading = false
        preloadingComplete = true
        currentlyLoadingModel = ""
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
            return cached.clone(recursive: true)
        }
        
        
        // Load if not cached
        let entity = await loadModel(modelType)
        return entity?.clone(recursive: true)
    }
    
    
    /// Load a model and and then cache it
    private func loadModel(_ modelType: ModelType) async -> ModelEntity? {
        if let inFlight = loadingTasks[modelType] {
            return await inFlight.value
        }

        let task = Task<ModelEntity?, Never> {
            var modelEntity: ModelEntity?

            if let modelURL = Bundle.xrShareLocateUSDZ(named: modelType.rawValue) {
                do {
                    modelEntity = try await ModelEntity(contentsOf: modelURL)
                } catch {
                    #if DEBUG
                    print("ModelCache: Failed to load \(modelType.rawValue) from URL: \(error)")
                    #endif
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

            return modelEntity
        }

        loadingTasks[modelType] = task
        let modelEntity = await task.value
        loadingTasks[modelType] = nil

        if let entity = modelEntity {
            cache[modelType] = entity
            return entity
        }

        return nil
    }
    
    
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
        preloadingComplete = false
    }
    
    /// Remove specific model from cache
    func removeFromCache(_ modelType: ModelType) {
        cache.removeValue(forKey: modelType)
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

