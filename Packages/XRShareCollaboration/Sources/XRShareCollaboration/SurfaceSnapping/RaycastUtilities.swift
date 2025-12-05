//
// RaycastUtilities.swift
// XRShareCollaboration
//
// Raycasting utilities for surface detection and snapping
//

import Foundation
import RealityKit
import ARKit

public struct RaycastHit {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let distance: Float
    public let planeID: UUID

    init(position: SIMD3<Float>, normal: SIMD3<Float>, distance: Float, planeID: UUID) {
        self.position = position
        self.normal = normal
        self.distance = distance
        self.planeID = planeID
    }
}

public struct RaycastUtilities {

    /// Raycast to find intersections with detected planes
    public static func raycastToPlanes(
        from origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        planes: [DetectedPlane],
        maxDistance: Float = 10.0
    ) -> [RaycastHit] {
        var hits: [RaycastHit] = []

        let normalizedDirection = normalize(direction)

        for plane in planes {
            if let hit = intersectPlane(
                rayOrigin: origin,
                rayDirection: normalizedDirection,
                plane: plane,
                maxDistance: maxDistance
            ) {
                hits.append(hit)
            }
        }

        return hits.sorted { $0.distance < $1.distance }
    }

    /// Raycast to find the closest plane intersection
    public static func raycastToClosestPlane(
        from origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        planes: [DetectedPlane],
        maxDistance: Float = 10.0
    ) -> RaycastHit? {
        let hits = raycastToPlanes(
            from: origin,
            direction: direction,
            planes: planes,
            maxDistance: maxDistance
        )
        return hits.first
    }

    /// Raycast in multiple directions to find nearby surfaces (useful for walls)
    public static func raycastMultiDirectional(
        from origin: SIMD3<Float>,
        planes: [DetectedPlane],
        maxDistance: Float = 0.5
    ) -> [RaycastHit] {
        let directions: [SIMD3<Float>] = [
            SIMD3(1, 0, 0),   // Right
            SIMD3(-1, 0, 0),  // Left
            SIMD3(0, 0, 1),   // Forward
            SIMD3(0, 0, -1),  // Back
            SIMD3(0, -1, 0)   // Down
        ]

        var allHits: [RaycastHit] = []

        for direction in directions {
            let hits = raycastToPlanes(
                from: origin,
                direction: direction,
                planes: planes,
                maxDistance: maxDistance
            )
            allHits.append(contentsOf: hits)
        }

        return allHits.sorted { $0.distance < $1.distance }
    }

    /// Intersect a ray with a plane
    private static func intersectPlane(
        rayOrigin: SIMD3<Float>,
        rayDirection: SIMD3<Float>,
        plane: DetectedPlane,
        maxDistance: Float
    ) -> RaycastHit? {
        let planeNormal = plane.normal
        let planePoint = plane.center

        // Check if ray is parallel to plane
        let denominator = dot(rayDirection, planeNormal)
        if abs(denominator) < 1e-6 {
            return nil // Parallel, no intersection
        }

        // Calculate intersection distance
        let t = dot(planePoint - rayOrigin, planeNormal) / denominator

        // Check if intersection is behind ray origin or too far
        if t < 0 || t > maxDistance {
            return nil
        }

        let intersectionPoint = rayOrigin + rayDirection * t

        // Check if intersection is within plane bounds
        let localX = intersectionPoint.x - plane.center.x
        let localZ = intersectionPoint.z - plane.center.z

        let halfExtentX = plane.extent.x / 2
        let halfExtentZ = plane.extent.z / 2

        if abs(localX) > halfExtentX || abs(localZ) > halfExtentZ {
            return nil // Outside plane bounds
        }

        return RaycastHit(
            position: intersectionPoint,
            normal: planeNormal,
            distance: t,
            planeID: plane.id
        )
    }

    /// Find all horizontal planes within vertical range of a position
    public static func findHorizontalPlanesNear(
        position: SIMD3<Float>,
        planes: [DetectedPlane],
        verticalRange: Float = 0.5
    ) -> [DetectedPlane] {
        return planes.filter { plane in
            plane.alignment == .horizontal &&
            abs(plane.center.y - position.y) < verticalRange
        }
    }

    /// Find all vertical planes (walls) near a position
    public static func findVerticalPlanesNear(
        position: SIMD3<Float>,
        planes: [DetectedPlane],
        maxDistance: Float = 0.5
    ) -> [DetectedPlane] {
        return planes.filter { plane in
            plane.alignment == .vertical &&
            distance(SIMD2(plane.center.x, plane.center.z),
                    SIMD2(position.x, position.z)) < maxDistance
        }
    }

    /// Calculate angle between two normals
    public static func angleBetween(_ normal1: SIMD3<Float>, _ normal2: SIMD3<Float>) -> Float {
        let dot = simd_dot(normalize(normal1), normalize(normal2))
        return acos(max(-1, min(1, dot)))
    }
}
