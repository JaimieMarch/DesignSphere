//
// DetectedPlane.swift
// XRShareCollaboration
//
// Represents a detected surface plane from ARKit
//

import Foundation
import ARKit
import RealityKit

public struct DetectedPlane: Identifiable {
    public let id: UUID
    public let transform: simd_float4x4
    public let center: SIMD3<Float>
    public let extent: SIMD3<Float>
    public let alignment: PlaneAnchor.Alignment
    public let classification: PlaneAnchor.Classification
    public let normal: SIMD3<Float>

    init(from anchor: PlaneAnchor) {
        self.id = anchor.id
        self.transform = anchor.originFromAnchorTransform

        // Extract center from transform
        self.center = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )

        self.extent = SIMD3<Float>(
            anchor.geometry.extent.width,
            0,
            anchor.geometry.extent.height
        )

        self.alignment = anchor.alignment
        self.classification = anchor.classification

        // Calculate normal from transform
        switch alignment {
        case .horizontal:
            self.normal = SIMD3<Float>(0, 1, 0)
        case .vertical:
            // Extract forward vector from transform
            let forward = SIMD3<Float>(
                transform.columns.2.x,
                transform.columns.2.y,
                transform.columns.2.z
            )
            self.normal = normalize(forward)
        @unknown default:
            self.normal = SIMD3<Float>(0, 1, 0)
        }
    }

    /// Check if a 2D point (x,z) is within this plane's bounds
    func contains(point: SIMD2<Float>) -> Bool {
        let localX = point.x - center.x
        let localZ = point.y - center.z

        return abs(localX) <= extent.x / 2 && abs(localZ) <= extent.z / 2
    }

    /// Get the height (y-coordinate) of this plane
    var height: Float {
        return center.y
    }
}
