//
// SurfaceClassification.swift
// XRShareCollaboration
//
// Classifies detected surfaces by type and validates object placement
//

import Foundation
import ARKit

public enum SurfaceClassification {
    case floor
    case table
    case counter
    case shelf
    case wall
    case other

    /// Classify a detected plane based on its properties
    static func classify(_ plane: DetectedPlane) -> SurfaceClassification {
        // Vertical surfaces
        if plane.alignment == .vertical {
            return .wall
        }

        // Horizontal surface classification by height and area
        let height = plane.center.y
        let area = plane.extent.x * plane.extent.z

        // Use ARKit classification when available
        switch plane.classification {
        case .floor:
            return .floor
        case .table:
            return .table
        case .seat, .door, .window, .wall:
            return .other
        @unknown default:
            break
        }

        // Heuristic-based classification for horizontal surfaces
        if height < 0.3 {
            return .floor
        } else if height > 0.6 && height < 1.0 && area > 0.4 {
            return .table
        } else if height > 0.85 && height < 1.2 && area > 0.3 {
            return .counter
        } else if height > 1.2 && area < 0.6 {
            return .shelf
        }

        return .other
    }
}

public enum ObjectPlacementType {
    case furniture      // Chairs, tables, couches (floor only)
    case decorative     // Vases, decor (tables, counters, shelves)
    case lighting       // Lamps (floor, tables, counters)
    case wallMounted    // Paintings, shelves (walls only)

    /// Determine placement type from ModelType
    static func from(modelType: ModelType) -> ObjectPlacementType {
        let name = modelType.rawValue.lowercased()

        if name.contains("chair") || name.contains("table") || name.contains("couch") ||
           name.contains("sofa") || name.contains("closet") {
            return .furniture
        } else if name.contains("paint") || name.contains("poster") {
            return .wallMounted
        } else if name.contains("lamp") || name.contains("chandelier") {
            return .lighting
        } else if name.contains("vase") {
            return .decorative
        }

        return .furniture // Default
    }

    /// Check if this object type can be placed on the given surface
    func isValidPlacement(on surface: SurfaceClassification) -> Bool {
        switch (self, surface) {
        case (.furniture, .floor):
            return true
        case (.decorative, .table), (.decorative, .counter), (.decorative, .shelf):
            return true
        case (.lighting, .floor), (.lighting, .table), (.lighting, .counter):
            return true
        case (.wallMounted, .wall):
            return true
        default:
            return false
        }
    }

    /// Get snap threshold distance for this object type
    var snapThreshold: Float {
        switch self {
        case .furniture:
            return 0.3      // 30cm
        case .decorative:
            return 0.25     // 25cm
        case .lighting:
            return 0.3      // 30cm
        case .wallMounted:
            return 0.25     // 25cm
        }
    }
}
