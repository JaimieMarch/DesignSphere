#if SWIFT_PACKAGE
//
//  ModelType.swift
//  XR Anatomy
//
//  Model type definitions and categorization system for 3D models
//


import Foundation
import RealityKit


// MARK: - Model Type Structure

/// Represents a specific type of 3D model type with metadata and loading capabilities
struct ModelType: Hashable, Identifiable, Codable, Sendable {
    let rawValue: String
    
    // Instead of a random UUID, use the rawValue as the basis for the ID
    var id: String { rawValue.lowercased() }
    
    // Convert rawValue to a more humanreadable format
    var displayName: String {
        let words = rawValue.replacingOccurrences(of: "([a-z])([A-Z0-9])", with: "$1 $2", options: .regularExpression)
        return words.capitalized
    }
    

    
    
// MARK: - Model loading
    
    /// Creates a ModelEntity instance for this model type
    func createModelEntity() -> ModelEntity? {
        if let modelURL = Bundle.xrShareLocateUSDZ(named: rawValue) {
            return try? ModelEntity.loadModel(contentsOf: modelURL)
        }

        let filename = rawValue + ".usdz"
        for bundle in Bundle.xrShareResourceBundles {
            if let entity = try? ModelEntity.loadModel(named: filename, in: bundle) {
                return entity
            }
                }

        return nil
    }
    
    /// Discovers all available model types by scanning bundle resouces
    static func allCases() -> [ModelType] {
        
        var canonicalNames: [String: String] = [:]
        for url in Bundle.xrShareUSDZResources() {
            let name = url.deletingPathExtension().lastPathComponent
            canonicalNames[name.lowercased()] = name
        }

        guard !canonicalNames.isEmpty else {
            
            // Return a default placeholder to prevent any crashes
            return [ModelType(rawValue: "placeholder")]
        }

        let sortedKeys = canonicalNames.keys.sorted()
        return sortedKeys.compactMap { key in
            canonicalNames[key].map { ModelType(rawValue: $0) }
        }
    }
    
    static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        lhs.rawValue.lowercased() == rhs.rawValue.lowercased()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.lowercased())
    }
}
#endif



