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
            await MainActor.run {
                self.alertItem = AlertItem(
                    title: "No Models Found",
                    message: "No 3D model files were found. Please add .usdz files to the 'models' folder."
                )
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
                
                self.alertItem = AlertItem(
                    title: "Failed to Load Model",
                    message: "\(modelType.rawValue.capitalized): \(error.localizedDescription)"
                )
                
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
