import ARKit
import RealityKit
import simd

struct SurfacePlacement {
    enum Source {
        case plane(UUID)
    }

    let localPosition: SIMD3<Float>
    let source: Source
}

enum SurfaceSnappingEngine {
    struct Options {
        var maxSnapDistance: Float
        var preferredSpawnDistance: Float

        static let initialPlacement = Options(maxSnapDistance: 3.0, preferredSpawnDistance: 1.2)
        static let manipulation = Options(maxSnapDistance: 0.6, preferredSpawnDistance: 0)
    }

    static func placementForSpawn(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        deviceTransform: simd_float4x4,
        planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?,
        options: Options = .initialPlacement
    ) -> SurfacePlacement? {
        let targetPoint = deviceTargetPoint(
            from: deviceTransform,
            preferredDistance: options.preferredSpawnDistance
        )

        return resolvePlacement(
            entity: entity,
            modelType: modelType,
            sharedAnchor: sharedAnchor,
            preferredWorldPoint: targetPoint,
            deviceWorldPosition: deviceTransform.translation,
            planeAnchors: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs,
            maxSnapDistance: options.maxSnapDistance
        )
    }

    static func placementForManipulation(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?,
        options: Options = .manipulation
    ) -> SurfacePlacement? {
        let referencePoint = snapReferencePoint(for: entity, modelType: modelType, relativeTo: nil)
        let devicePosition = entity.position(relativeTo: nil)

        return resolvePlacement(
            entity: entity,
            modelType: modelType,
            sharedAnchor: sharedAnchor,
            preferredWorldPoint: referencePoint,
            deviceWorldPosition: devicePosition,
            planeAnchors: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs,
            maxSnapDistance: options.maxSnapDistance
        )
    }

    private static func resolvePlacement(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        preferredWorldPoint: SIMD3<Float>,
        deviceWorldPosition: SIMD3<Float>,
        planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?,
        maxSnapDistance: Float
    ) -> SurfacePlacement? {
        let candidates = filteredPlanes(
            for: modelType,
            from: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs
        )

        guard !candidates.isEmpty else { return nil }

        let bounds = entity.components[ModelBoundsComponent.self]
        var bestCandidate: (planeID: UUID, worldPosition: SIMD3<Float>, distance: Float)?

        for plane in candidates {
            guard let snappedPoint = closestPoint(
                on: plane,
                to: preferredWorldPoint
            ) else { continue }

            let distance = simd_distance(snappedPoint, preferredWorldPoint)
            guard distance <= maxSnapDistance else { continue }

            let worldPosition = resolvedWorldPosition(
                for: entity,
                bounds: bounds,
                modelType: modelType,
                snappedPoint: snappedPoint,
                plane: plane,
                deviceWorldPosition: deviceWorldPosition
            )

            if let currentBest = bestCandidate {
                if distance < currentBest.distance {
                    bestCandidate = (plane.id, worldPosition, distance)
                }
            } else {
                bestCandidate = (plane.id, worldPosition, distance)
            }
        }

        guard let bestCandidate else { return nil }
        return SurfacePlacement(
            localPosition: worldToLocal(bestCandidate.worldPosition, relativeTo: sharedAnchor),
            source: .plane(bestCandidate.planeID)
        )
    }

    private static func filteredPlanes(
        for modelType: ModelType,
        from planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?
    ) -> [PlaneAnchor] {
        planeAnchors.filter { plane in
            if let allowedPlaneIDs, !allowedPlaneIDs.contains(plane.id) {
                return false
            }

            if !alignmentMatches(modelType.plane, plane.alignment) {
                return false
            }

            return classificationMatches(modelType.classification, plane.classification)
        }
    }

    private static func alignmentMatches(
        _ preferred: AnchoringComponent.Target.Alignment,
        _ actual: PlaneAnchor.Alignment
    ) -> Bool {
        if preferred == .any {
            return true
        }
        if preferred == .horizontal {
            return actual == .horizontal
        }
        if preferred == .vertical {
            return actual == .vertical
        }
        return true
    }

    private static func classificationMatches(
        _ preferred: AnchoringComponent.Target.Classification,
        _ actual: PlaneAnchor.Classification
    ) -> Bool {
        if preferred == .any {
            return true
        }
        if preferred == .floor {
            return actual == .floor
        }
        if preferred == .wall {
            return actual == .wall
        }
        if preferred == .ceiling {
            return actual == .ceiling
        }
        if preferred == .table {
            return actual == .table
        }
        if preferred == .seat {
            return actual == .seat
        }
        return true
    }

    private static func deviceTargetPoint(
        from deviceTransform: simd_float4x4,
        preferredDistance: Float
    ) -> SIMD3<Float> {
        let position = deviceTransform.translation
        let forward = normalize(-deviceTransform.forward)
        return position + (forward * preferredDistance)
    }

    private static func snapReferencePoint(
        for entity: Entity,
        modelType: ModelType,
        relativeTo reference: Entity?
    ) -> SIMD3<Float> {
        guard let bounds = entity.components[ModelBoundsComponent.self] else {
            return entity.position(relativeTo: reference)
        }

        let localReference: SIMD3<Float>
        switch modelType.plane {
        case .vertical:
            localReference = bounds.center
        default:
            localReference = bounds.placementOffset
        }

        return entity.convert(position: localReference, to: reference)
    }

    private static func resolvedWorldPosition(
        for entity: Entity,
        bounds: ModelBoundsComponent?,
        modelType: ModelType,
        snappedPoint: SIMD3<Float>,
        plane: PlaneAnchor,
        deviceWorldPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        if plane.alignment == .vertical {
            let modelCenter = bounds?.center ?? .zero
            let depth = bounds?.extents.z ?? 0
            var normal = normalize(plane.normal)
            if simd_dot(normal, deviceWorldPosition - snappedPoint) < 0 {
                normal *= -1
            }
            let wallPadding = max(depth * 0.5, 0.01)
            return snappedPoint - modelCenter + (normal * wallPadding)
        }

        let placementOffset = bounds?.placementOffset ?? .zero
        return snappedPoint - placementOffset
    }

    private static func closestPoint(on plane: PlaneAnchor, to worldPoint: SIMD3<Float>) -> SIMD3<Float>? {
        let planeTransform = plane.originFromAnchorTransform
        let localPoint = planeTransform.inverse.transformPoint(worldPoint)
        let extent = plane.geometry.extent

        switch plane.alignment {
        case .vertical:
            let halfWidth = extent.width * 0.5
            let halfHeight = extent.height * 0.5
            let clampedX = clamp(localPoint.x, min: -halfWidth, max: halfWidth)
            let clampedY = clamp(localPoint.y, min: -halfHeight, max: halfHeight)
            let localSnap = SIMD3<Float>(clampedX, clampedY, 0)
            return planeTransform.transformPoint(localSnap)
        case .horizontal:
            let halfWidth = extent.width * 0.5
            let halfDepth = extent.height * 0.5
            let clampedX = clamp(localPoint.x, min: -halfWidth, max: halfWidth)
            let clampedZ = clamp(localPoint.z, min: -halfDepth, max: halfDepth)
            let localSnap = SIMD3<Float>(clampedX, 0, clampedZ)
            return planeTransform.transformPoint(localSnap)
        @unknown default:
            return nil
        }
    }

    private static func worldToLocal(_ worldPoint: SIMD3<Float>, relativeTo anchor: AnchorEntity) -> SIMD3<Float> {
        anchor.transform.matrix.inverse.transformPoint(worldPoint)
    }

    private static func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    var forward: SIMD3<Float> {
        SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
    }

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let transformed = self * SIMD4<Float>(point.x, point.y, point.z, 1)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }
}

private extension PlaneAnchor {
    var normal: SIMD3<Float> {
        switch alignment {
        case .horizontal:
            return SIMD3<Float>(
                originFromAnchorTransform.columns.1.x,
                originFromAnchorTransform.columns.1.y,
                originFromAnchorTransform.columns.1.z
            )
        case .vertical:
            return SIMD3<Float>(
                originFromAnchorTransform.columns.2.x,
                originFromAnchorTransform.columns.2.y,
                originFromAnchorTransform.columns.2.z
            )
        @unknown default:
            return SIMD3<Float>(0, 1, 0)
        }
    }
}
