//
//  ARViewModel+Models.swift
//  XR Share
//
//  Model loading and synchronization functionality for ARViewModel
//

import Foundation
import RealityKit
import SwiftUI


// MARK: - Model Loading

extension ARViewModel {
    
    /// Loads all available 3D models sequentially
    func loadModels() async {
        guard models.isEmpty else {
            return
        }
        let modelTypes = ModelType.allCases()
        
        guard !modelTypes.isEmpty else {
            // No bundled or imported usdz files. This is the normal state for a
            // clean install — the catalog is served remotely — so it is not a
            // user-facing error. It used to write `alertItem`, which nothing
            // presents, so the "failure" was invisible either way.
            XRLog.verbose("loadModels: no local model files to load")
            await MainActor.run {
                self.loadingProgress = 1.0
            }
            return
        }
        
        let totalModels = modelTypes.count
        var loadedModels = 0
        var failedModels = 0
        
        for modelType in modelTypes {
            let model = Model(modelType: modelType, arViewModel: self)
            models.append(model)
            
            await model.loadModelEntity()
            
            
            switch model.loadingState {
                
                
            case .loaded:
                loadedModels += 1
                updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)
                
            case .failed(let error):
                failedModels += 1
                updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)

                // `alertItem` has no presenter anywhere in the app, so setting it
                // silently swallowed the failure. Remote models surface their own
                // failure through RemoteDownloadProgress + the cell's Retry badge.
                XRLog.verbose("Failed to load local model \(modelType.rawValue): \(error.localizedDescription)")

            default:
                break
            }
        }
        
        // Ensure progress hits 1.0
        if loadingProgress < 1.0 {
            updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)
        }
    }
    
    @MainActor
    private func updateLoadingProgress(loaded: Int, failed: Int, total: Int) {
        let processed = loaded + failed
        self.loadingProgress = min(Float(processed) / Float(total), 1.0)
    }
}
