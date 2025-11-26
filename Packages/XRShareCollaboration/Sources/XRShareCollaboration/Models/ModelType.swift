#if SWIFT_PACKAGE
//
//  ModelType.swift
//  XR Anatomy
//
//  Model type definitions and categorization system for 3D models
//


import Foundation
import RealityKit


// MARK: - Placement Surface Types

/// Defines possible placement surfaces for models
public enum PlacementSurface: Sendable {
    case floor // gravity-bound items (chairs, tables, etc.)
    case wall // wall mounted items (TVs, art, etc.)
    case ceiling // for lighting/fans, other upper-mounted items
    case surface // stackable decor (vases, picture frames, etc.)
    case free // default behavior (can be placed anywhere)
}


// MARK: - Model Type Structure

/// Represents a specific type of 3D model type with metadata and loading capabilities
public struct ModelType: Hashable, Identifiable, Codable, Sendable {
    public let rawValue: String
    
    // Instead of a random UUID, use the rawValue as the basis for the ID
    public var id: String { rawValue.lowercased() }
    
    // Convert rawValue to a more humanreadable format
    public var displayName: String {
        let words = rawValue.replacingOccurrences(of: "([a-z])([A-Z0-9])", with: "$1 $2", options: .regularExpression)
        return words.capitalized
    }

    // Determines the preferred placement surface based on model type
    // current only using raw item values
    public var preferredSurface: PlacementSurface {
        switch rawValue.lowercased() {
        case "chair", "stool", "sofa", "couch", "coffee_table", "closet", "dinner_table":
            return .floor
        case "vase":
            return .surface
        case "65_in_tv":
            return .wall
        case "chandelier":
            return .ceiling
        default:
            return .free
        }
    }

    /// Models that are already at real-world scale and shouldn't be normalized
    /// Set to true for models created in Reality Composer Pro with proper measurements
    /// Use the same defintion logic as the above to achieve this
    public var preserveRealWorldScale: Bool {
        switch rawValue.lowercased() {
        // Reality Composer Pro models made to scale (measured in inches/meters)
            // There is likely a better way to do this instead of using switch statements
            // problem for another day.
        case "chair", "stool", "sofa", "couch", "coffee_table", "closet", "dinner_table":
            return true
        case "vase", "65_in_tv", "chandelier":
            return true
        default:
            return false
            // In the case we have other models, we still might need to normalize the size
            // I have no control over models downloaded/scanned
            // Editing models becomes highly important in this case
        }
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
    
    public static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        lhs.rawValue.lowercased() == rhs.rawValue.lowercased()
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.lowercased())
    }
}
#endif



