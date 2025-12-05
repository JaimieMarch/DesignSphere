//
// SurfaceSnapManager.swift
// XRShareCollaboration
//
// Main manager for surface snapping logic
//

import Foundation
import RealityKit
import ARKit

@MainActor
public class SurfaceSnapManager {
    private let surfaceDetectionManager: SurfaceDetectionManager
    private let snapPreview: SnapPreviewEntity
    private var entitySnapBehaviors: [UUID: SnapBehavior] = [:]

    public init(surfaceDetectionManager: SurfaceDetectionManager) {
        self.surfaceDetectionManager = surfaceDetectionManager
        self.snapPreview = SnapPreviewEntity()
    }

    /// Initialize snap preview (call after anchor entity is created)
    public func initializePreview(parent: Entity) {
        snapPreview.createPreview(parent: parent)
    }

    /// Update entity position with snapping for horizontal surfaces (floor, tables, shelves)
    public func updateHorizontalSnap(
        entity: Entity,
        entityID: UUID,
        modelType: ModelType,
        dragPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        let placementType = ObjectPlacementType.from(modelType: modelType)

        // Get or create snap behavior for this entity
        var snapBehavior = entitySnapBehaviors[entityID] ?? SnapBehavior()

        let horizontalPlanes = surfaceDetectionManager.getHorizontalPlanes()
        guard !horizontalPlanes.isEmpty else {
            snapPreview.hidePreview()
            entitySnapBehaviors[entityID] = snapBehavior
            return dragPosition
        }

        // Raycast downward from drag position
        let rayOrigin = SIMD3(dragPosition.x, dragPosition.y + 1.0, dragPosition.z)
        let rayDirection = SIMD3<Float>(0, -1, 0)

        let hits = RaycastUtilities.raycastToPlanes(
            from: rayOrigin,
            direction: rayDirection,
            planes: horizontalPlanes,
            maxDistance: 5.0
        )

        guard !hits.isEmpty else {
            snapPreview.hidePreview()
            snapBehavior.reset()
            entitySnapBehaviors[entityID] = snapBehavior
            return dragPosition
        }

        // Find best surface based on vertical proximity and placement validity
        let bestHit = selectBestHorizontalSurface(
            hits: hits,
            dragPosition: dragPosition,
            placementType: placementType,
            currentBehavior: snapBehavior
        )

        guard let hit = bestHit else {
            snapPreview.hidePreview()
            snapBehavior.reset()
            entitySnapBehaviors[entityID] = snapBehavior
            return dragPosition
        }

        let distanceToSurface = abs(dragPosition.y - hit.position.y)

        // Check if within snap threshold
        if distanceToSurface < placementType.snapThreshold {
            // Within snap zone - snap to surface
            let snappedPosition = SIMD3(
                dragPosition.x,
                hit.position.y,
                dragPosition.z
            )

            // Check if position is within surface bounds
            if let plane = surfaceDetectionManager.getPlane(id: hit.planeID) {
                let inBounds = plane.contains(point: SIMD2(snappedPosition.x, snappedPosition.z))

                if inBounds {
                    // Valid snap
                    snapBehavior.snapTo(
                        surfaceID: hit.planeID,
                        type: SurfaceClassification.classify(plane)
                    )

                    snapPreview.showPreview(at: snappedPosition, color: .green)
                    snapPreview.showSurfaceBounds(at: plane.center, extent: plane.extent)

                    entitySnapBehaviors[entityID] = snapBehavior

                    // Smooth interpolation to snapped position
                    return mix(dragPosition, snappedPosition, t: snapBehavior.snapStrength)
                }
            }
        }

        // Not snapping
        snapPreview.hidePreview()
        snapBehavior.reset()
        entitySnapBehaviors[entityID] = snapBehavior
        return dragPosition
    }

    /// Update entity position with snapping for vertical surfaces (walls)
    public func updateVerticalSnap(
        entity: Entity,
        entityID: UUID,
        modelType: ModelType,
        dragPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        let placementType = ObjectPlacementType.from(modelType: modelType)

        guard placementType == .wallMounted else {
            return dragPosition
        }

        var snapBehavior = entitySnapBehaviors[entityID] ?? SnapBehavior()

        let verticalPlanes = surfaceDetectionManager.getVerticalPlanes()
        guard !verticalPlanes.isEmpty else {
            snapPreview.hidePreview()
            entitySnapBehaviors[entityID] = snapBehavior
            return dragPosition
        }

        // Raycast in multiple directions to find nearby walls
        let hits = RaycastUtilities.raycastMultiDirectional(
            from: dragPosition,
            planes: verticalPlanes,
            maxDistance: 0.5
        )

        guard let bestHit = hits.first else {
            snapPreview.hidePreview()
            snapBehavior.reset()
            entitySnapBehaviors[entityID] = snapBehavior
            return dragPosition
        }

        // Check if within snap threshold
        if bestHit.distance < placementType.snapThreshold {
            guard let plane = surfaceDetectionManager.getPlane(id: bestHit.planeID) else {
                return dragPosition
            }

            // Handle corner transitions
            if let currentSurface = snapBehavior.snappedSurfaceID,
               currentSurface != bestHit.planeID {
                handleWallTransition(
                    from: currentSurface,
                    to: bestHit.planeID,
                    entity: entity
                )
            }

            // Snap to wall with offset
            let wallOffset: Float = 0.02  // 2cm from wall
            let snappedPosition = bestHit.position + (bestHit.normal * wallOffset)

            snapBehavior.snapTo(
                surfaceID: bestHit.planeID,
                type: .wall
            )

            // Align entity to wall
            alignEntityToWall(entity: entity, wallNormal: bestHit.normal)

            snapPreview.showPreview(at: snappedPosition, color: .cyan)

            entitySnapBehaviors[entityID] = snapBehavior

            return snappedPosition
        }

        // Not snapping
        snapPreview.hidePreview()
        snapBehavior.reset()
        entitySnapBehaviors[entityID] = snapBehavior
        return dragPosition
    }

    /// Select best horizontal surface based on criteria
    private func selectBestHorizontalSurface(
        hits: [RaycastHit],
        dragPosition: SIMD3<Float>,
        placementType: ObjectPlacementType,
        currentBehavior: SnapBehavior
    ) -> RaycastHit? {
        // Sort by vertical proximity
        let sortedHits = hits.sorted { hit1, hit2 in
            let dist1 = abs(hit1.position.y - dragPosition.y)
            let dist2 = abs(hit2.position.y - dragPosition.y)
            return dist1 < dist2
        }

        // Apply hysteresis if already snapped
        if let currentSurface = currentBehavior.snappedSurfaceID,
           currentBehavior.currentState == .snapped {
            // Check if current surface is still valid
            if let currentHit = sortedHits.first(where: { $0.planeID == currentSurface }) {
                let currentDist = abs(currentHit.position.y - dragPosition.y)

                // Check if another surface is significantly better
                for hit in sortedHits where hit.planeID != currentSurface {
                    let newDist = abs(hit.position.y - dragPosition.y)
                    if newDist < (currentDist - currentBehavior.surfaceSwitchThreshold) {
                        // New surface is significantly better
                        return hit
                    }
                }

                // Stick with current surface
                return currentHit
            }
        }

        // Find first valid surface for this placement type
        for hit in sortedHits {
            if let plane = surfaceDetectionManager.getPlane(id: hit.planeID) {
                let classification = SurfaceClassification.classify(plane)
                if placementType.isValidPlacement(on: classification) {
                    return hit
                }
            }
        }

        return sortedHits.first
    }

    /// Handle transition between walls
    private func handleWallTransition(from oldWallID: UUID, to newWallID: UUID, entity: Entity) {
        guard let oldPlane = surfaceDetectionManager.getPlane(id: oldWallID),
              let newPlane = surfaceDetectionManager.getPlane(id: newWallID) else {
            return
        }

        // Calculate angle between walls
        let angle = RaycastUtilities.angleBetween(oldPlane.normal, newPlane.normal)

        // Check if it's a corner (near 90 degrees)
        let isCorner = abs(angle - .pi/2) < 0.3 || abs(angle - 3 * .pi / 2) < 0.3

        if isCorner {
            print("Corner transition detected: \(angle * 180 / .pi) degrees")
            snapPreview.animatePreview()
        }
    }

    /// Align entity to face away from wall
    private func alignEntityToWall(entity: Entity, wallNormal: SIMD3<Float>) {
        let forward = -wallNormal  // Face away from wall
        let up = SIMD3<Float>(0, 1, 0)

        // Calculate rotation
        let rotation = simd_quatf(from: SIMD3(0, 0, -1), to: forward)
        entity.orientation = rotation
    }

    /// Get snap behavior for entity
    public func getSnapBehavior(for entityID: UUID) -> SnapBehavior? {
        return entitySnapBehaviors[entityID]
    }

    /// Clear snap behavior for entity
    public func clearSnapBehavior(for entityID: UUID) {
        entitySnapBehaviors.removeValue(forKey: entityID)
        snapPreview.hidePreview()
    }

    /// Clear all snap behaviors
    public func clearAllSnapBehaviors() {
        entitySnapBehaviors.removeAll()
        snapPreview.hidePreview()
    }
}
