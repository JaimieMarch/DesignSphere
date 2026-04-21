import ARKit
import RealityKit
import simd

struct SurfacePlacement {
    enum Source {
        case plane(UUID)
        case roomMesh(UUID)

        var kind: SnapStateComponent.SourceKind {
            switch self {
            case .plane:
                return .plane
            case .roomMesh:
                return .roomMesh
            }
        }

        var surfaceID: UUID {
            switch self {
            case .plane(let id), .roomMesh(let id):
                return id
            }
        }

        var label: String {
            switch self {
            case .plane:
                return "plane"
            case .roomMesh:
                return "roomMesh"
            }
        }
    }

    let localPosition: SIMD3<Float>
    let worldOrientation: simd_quatf?
    let source: Source
    let classification: String?
    let score: Float
    let supportRegionID: String?
    let supportWorldPosition: SIMD3<Float>
    let supportWorldNormal: SIMD3<Float>
}

enum SurfaceSnappingEngine {
    struct Options {
        var maxSnapDistance: Float
        var maxPerpendicularDistance: Float
        var maxEdgeOverflowDistance: Float
        var maxSupportDistance: Float
        var preferredSpawnDistance: Float

        static let initialPlacement = Options(
            maxSnapDistance: 0.5,
            maxPerpendicularDistance: 0.28,
            maxEdgeOverflowDistance: 0.12,
            maxSupportDistance: 0.08,
            preferredSpawnDistance: 1.2
        )
        static let manipulation = Options(
            maxSnapDistance: 0.12,
            maxPerpendicularDistance: 0.06,
            maxEdgeOverflowDistance: 0.03,
            maxSupportDistance: 0.035,
            preferredSpawnDistance: 0
        )

        func withHysteresis() -> Options {
            Options(
                maxSnapDistance: maxSnapDistance + 0.04,
                maxPerpendicularDistance: maxPerpendicularDistance + 0.02,
                maxEdgeOverflowDistance: maxEdgeOverflowDistance + 0.02,
                maxSupportDistance: maxSupportDistance + 0.015,
                preferredSpawnDistance: preferredSpawnDistance
            )
        }
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
            viewerWorldPosition: deviceTransform.translation,
            planeAnchors: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs,
            options: options
        )
    }

    static func placementForManipulation(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?,
        viewerWorldPosition: SIMD3<Float>,
        options: Options = .manipulation
    ) -> SurfacePlacement? {
        let referencePoint = snapReferencePoint(for: entity, modelType: modelType, relativeTo: nil)

        return resolvePlacement(
            entity: entity,
            modelType: modelType,
            sharedAnchor: sharedAnchor,
            preferredWorldPoint: referencePoint,
            viewerWorldPosition: viewerWorldPosition,
            planeAnchors: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs,
            options: options
        )
    }

    static func supportsPosition(
        entity: Entity,
        modelType: ModelType,
        worldPosition: SIMD3<Float>,
        worldOrientation: simd_quatf,
        planeAnchors: [PlaneAnchor],
        requiredPlaneID: UUID,
        requiredClassification: String?,
        referenceSupportPoint: SIMD3<Float>? = nil,
        referenceSupportNormal: SIMD3<Float>? = nil,
        maxSupportDistance: Float = Options.manipulation.withHysteresis().maxSupportDistance
    ) -> Bool {
        guard let plane = planeAnchors.first(where: { $0.id == requiredPlaneID }) else {
            return false
        }

        if let requiredClassification,
           classificationDescription(for: plane.classification) != requiredClassification {
            return false
        }

        if !alignmentMatches(modelType.plane, plane.alignment) {
            return false
        }

        if let allowedClassifications = allowedPlaneClassifications(for: modelType),
           !allowedClassifications.contains(plane.classification) {
            return false
        }

        if let referenceSupportNormal {
            let planeNormal = simd_normalize(plane.normal)
            if abs(simd_dot(planeNormal, simd_normalize(referenceSupportNormal))) < SupportSurfacePolicy.normalAlignmentThreshold(for: modelType) {
                return false
            }
        }

        if let referenceSupportPoint,
           let supportedPoint = supportReferenceWorldPoint(
                for: entity,
                modelType: modelType,
                worldPosition: worldPosition,
                worldOrientation: worldOrientation
           ),
           simd_distance(supportedPoint, referenceSupportPoint) > SupportSurfacePolicy.driftLimit(for: modelType) {
            return false
        }

        let supportOverflow = supportFitOverflow(
            for: entity,
            bounds: entity.components[ModelBoundsComponent.self],
            modelType: modelType,
            worldPosition: worldPosition,
            worldOrientation: worldOrientation,
            plane: plane
        )

        return supportOverflow <= maxSupportDistance
    }

    private static func resolvePlacement(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        preferredWorldPoint: SIMD3<Float>,
        viewerWorldPosition: SIMD3<Float>,
        planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?,
        options: Options
    ) -> SurfacePlacement? {
        let candidates = filteredPlanes(
            for: modelType,
            from: planeAnchors,
            allowedPlaneIDs: allowedPlaneIDs
        )

        guard !candidates.isEmpty else { return nil }

        let bounds = entity.components[ModelBoundsComponent.self]
        let existingSnapState = entity.components[SnapStateComponent.self]
        var bestCandidate: (
            planeID: UUID,
            worldPosition: SIMD3<Float>,
            worldOrientation: simd_quatf?,
            classification: String?,
            score: Float,
            supportWorldPosition: SIMD3<Float>,
            supportWorldNormal: SIMD3<Float>
        )?

        for plane in candidates {
            guard let snappedPoint = closestPoint(on: plane, to: preferredWorldPoint) else { continue }
            guard snappedPoint.correctionDistance <= options.maxSnapDistance else { continue }
            guard snappedPoint.perpendicularDistance <= options.maxPerpendicularDistance else { continue }
            guard snappedPoint.edgeOverflowDistance <= options.maxEdgeOverflowDistance else { continue }

            let worldPosition = resolvedWorldPosition(
                bounds: bounds,
                snappedPoint: snappedPoint.worldPoint,
                plane: plane,
                viewerWorldPosition: viewerWorldPosition
            )
            let worldOrientation = resolvedWorldOrientation(
                for: entity,
                plane: plane,
                viewerWorldPosition: viewerWorldPosition
            )
            let supportOverflow = supportFitOverflow(
                for: entity,
                bounds: bounds,
                modelType: modelType,
                worldPosition: worldPosition,
                worldOrientation: worldOrientation ?? entity.orientation(relativeTo: nil),
                plane: plane
            )
            guard supportOverflow <= options.maxSupportDistance else { continue }

            let score = snappedPoint.correctionDistance
                + (snappedPoint.perpendicularDistance * 0.35)
                + (snappedPoint.edgeOverflowDistance * 0.2)
                + (supportOverflow * 0.45)
                + surfacePenalty(for: modelType, classification: plane.classification)
                + orientationPenalty(
                    for: entity,
                    plane: plane,
                    viewerWorldPosition: viewerWorldPosition
                )
                + sameSurfacePenalty(
                    existingSnapState,
                    source: .plane(plane.id),
                    classification: classificationDescription(for: plane.classification)
                )

            if let currentBest = bestCandidate {
                if score < currentBest.score {
                    bestCandidate = (
                        plane.id,
                        worldPosition,
                        worldOrientation,
                        classificationDescription(for: plane.classification),
                        score,
                        snappedPoint.worldPoint,
                        simd_normalize(plane.normal)
                    )
                }
            } else {
                bestCandidate = (
                    plane.id,
                    worldPosition,
                    worldOrientation,
                    classificationDescription(for: plane.classification),
                    score,
                    snappedPoint.worldPoint,
                    simd_normalize(plane.normal)
                )
            }
        }

        guard let bestCandidate else { return nil }
        return SurfacePlacement(
            localPosition: worldToLocal(bestCandidate.worldPosition, relativeTo: sharedAnchor),
            worldOrientation: bestCandidate.worldOrientation,
            source: .plane(bestCandidate.planeID),
            classification: bestCandidate.classification,
            score: bestCandidate.score,
            supportRegionID: nil,
            supportWorldPosition: bestCandidate.supportWorldPosition,
            supportWorldNormal: bestCandidate.supportWorldNormal
        )
    }

    private static func filteredPlanes(
        for modelType: ModelType,
        from planeAnchors: [PlaneAnchor],
        allowedPlaneIDs: Set<UUID>?
    ) -> [PlaneAnchor] {
        let allowedClassifications = allowedPlaneClassifications(for: modelType)

        return planeAnchors.filter { plane in
            if let allowedPlaneIDs, !allowedPlaneIDs.contains(plane.id) {
                return false
            }

            if !alignmentMatches(modelType.plane, plane.alignment) {
                return false
            }

            guard let allowedClassifications else {
                return true
            }

            return allowedClassifications.contains(plane.classification)
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

    private static func allowedPlaneClassifications(
        for modelType: ModelType
    ) -> Set<PlaneAnchor.Classification>? {
        switch modelType.classification {
        case .floor:
            return [.floor]
        case .wall:
            return [.wall]
        case .ceiling:
            return [.ceiling]
        case .table:
            return [.table]
        case .seat:
            return [.seat]
        default:
            switch modelType.plane {
            case .vertical:
                return [.wall]
            case .horizontal:
                return [.floor, .table]
            case .any:
                return nil
            default:
                return nil
            }
        }
    }

    private static func surfacePenalty(
        for modelType: ModelType,
        classification: PlaneAnchor.Classification
    ) -> Float {
        switch modelType.classification {
        case .any:
            if modelType.plane == .vertical {
                switch classification {
                case .wall:
                    return 0
                case .window:
                    return 0.04
                case .door:
                    return 0.07
                default:
                    return 0.03
                }
            }

            if modelType.plane == .horizontal {
                switch classification {
                case .floor:
                    return 0
                case .table:
                    return 0.015
                case .seat:
                    return 0.05
                default:
                    return 0.03
                }
            }

            return 0.02
        default:
            return 0
        }
    }

    private static func orientationPenalty(
        for entity: Entity,
        plane: PlaneAnchor,
        viewerWorldPosition: SIMD3<Float>
    ) -> Float {
        guard plane.alignment == .vertical else { return 0 }
        let worldTransform = entity.transformMatrix(relativeTo: nil)
        let worldUp = SIMD3<Float>(0, 1, 0)
        guard let currentForward = horizontalForwardVector(from: worldTransform, up: worldUp) else {
            return 0
        }

        var targetForward = normalize(plane.normal)
        let planeOrigin = plane.originFromAnchorTransform.translation
        if simd_dot(targetForward, viewerWorldPosition - planeOrigin) < 0 {
            targetForward *= -1
        }

        let alignment = max(simd_dot(currentForward, targetForward), 0)
        return (1 - alignment) * 0.025
    }

    private static func sameSurfacePenalty(
        _ snapState: SnapStateComponent?,
        source: SurfacePlacement.Source,
        classification: String?
    ) -> Float {
        guard let snapState else { return 0 }
        guard snapState.source == source.kind else { return 0 }
        guard snapState.surfaceID == source.surfaceID else { return 0 }

        if snapState.classification == classification {
            return -0.03
        }
        return -0.015
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
        bounds: ModelBoundsComponent?,
        snappedPoint: SIMD3<Float>,
        plane: PlaneAnchor,
        viewerWorldPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        if plane.alignment == .vertical {
            let modelCenter = bounds?.center ?? .zero
            let depth = bounds?.extents.z ?? 0
            var normal = normalize(plane.normal)
            if simd_dot(normal, viewerWorldPosition - snappedPoint) < 0 {
                normal *= -1
            }
            let wallPadding = max(depth * 0.5, 0.01)
            return snappedPoint - modelCenter + (normal * wallPadding)
        }

        let placementOffset = bounds?.placementOffset ?? .zero
        return snappedPoint - placementOffset
    }

    private static func resolvedWorldOrientation(
        for entity: Entity,
        plane: PlaneAnchor,
        viewerWorldPosition: SIMD3<Float>
    ) -> simd_quatf? {
        let worldTransform = entity.transformMatrix(relativeTo: nil)
        let worldUp = SIMD3<Float>(0, 1, 0)

        if plane.alignment == .vertical {
            var outward = normalize(plane.normal)
            let planeOrigin = plane.originFromAnchorTransform.translation
            if simd_dot(outward, viewerWorldPosition - planeOrigin) < 0 {
                outward *= -1
            }
            return makeOrientation(forward: outward, up: worldUp)
        }

        guard let forward = horizontalForwardVector(from: worldTransform, up: worldUp) else {
            return nil
        }
        return makeOrientation(forward: forward, up: worldUp)
    }

    private static func closestPoint(on plane: PlaneAnchor, to worldPoint: SIMD3<Float>) -> ClosestPlanePoint? {
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
            let edgeOverflow = simd_length(SIMD2<Float>(localPoint.x - clampedX, localPoint.y - clampedY))
            return ClosestPlanePoint(
                worldPoint: planeTransform.transformPoint(localSnap),
                correctionDistance: simd_distance(localPoint, localSnap),
                perpendicularDistance: abs(localPoint.z),
                edgeOverflowDistance: edgeOverflow
            )
        case .horizontal:
            let halfWidth = extent.width * 0.5
            let halfDepth = extent.height * 0.5
            let clampedX = clamp(localPoint.x, min: -halfWidth, max: halfWidth)
            let clampedZ = clamp(localPoint.z, min: -halfDepth, max: halfDepth)
            let localSnap = SIMD3<Float>(clampedX, 0, clampedZ)
            let edgeOverflow = simd_length(SIMD2<Float>(localPoint.x - clampedX, localPoint.z - clampedZ))
            return ClosestPlanePoint(
                worldPoint: planeTransform.transformPoint(localSnap),
                correctionDistance: simd_distance(localPoint, localSnap),
                perpendicularDistance: abs(localPoint.y),
                edgeOverflowDistance: edgeOverflow
            )
        @unknown default:
            return nil
        }
    }

    private static func worldToLocal(_ worldPoint: SIMD3<Float>, relativeTo anchor: AnchorEntity) -> SIMD3<Float> {
        anchor.transform.matrix.inverse.transformPoint(worldPoint)
    }

    private static func supportFitOverflow(
        for entity: Entity,
        bounds: ModelBoundsComponent?,
        modelType: ModelType,
        worldPosition: SIMD3<Float>,
        worldOrientation: simd_quatf,
        plane: PlaneAnchor
    ) -> Float {
        let localSupportPoints = supportLocalPoints(bounds: bounds, modelType: modelType)
        guard !localSupportPoints.isEmpty else { return 0 }

        let planeTransform = plane.originFromAnchorTransform
        let inversePlaneTransform = planeTransform.inverse
        let extent = plane.geometry.extent
        var maxOverflow: Float = 0

        for localPoint in localSupportPoints {
            let worldPoint = worldPosition + worldOrientation.act(localPoint)
            let planeLocalPoint = inversePlaneTransform.transformPoint(worldPoint)

            let overflow: Float
            let perpendicular: Float
            switch plane.alignment {
            case .vertical:
                let halfWidth = extent.width * 0.5
                let halfHeight = extent.height * 0.5
                let clampedX = clamp(planeLocalPoint.x, min: -halfWidth, max: halfWidth)
                let clampedY = clamp(planeLocalPoint.y, min: -halfHeight, max: halfHeight)
                overflow = simd_length(SIMD2<Float>(planeLocalPoint.x - clampedX, planeLocalPoint.y - clampedY))
                perpendicular = abs(planeLocalPoint.z)
            case .horizontal:
                let halfWidth = extent.width * 0.5
                let halfDepth = extent.height * 0.5
                let clampedX = clamp(planeLocalPoint.x, min: -halfWidth, max: halfWidth)
                let clampedZ = clamp(planeLocalPoint.z, min: -halfDepth, max: halfDepth)
                overflow = simd_length(SIMD2<Float>(planeLocalPoint.x - clampedX, planeLocalPoint.z - clampedZ))
                perpendicular = abs(planeLocalPoint.y)
            @unknown default:
                return .infinity
            }

            maxOverflow = max(maxOverflow, max(overflow, perpendicular))
        }

        return maxOverflow
    }

    private static func supportLocalPoints(
        bounds: ModelBoundsComponent?,
        modelType: ModelType
    ) -> [SIMD3<Float>] {
        guard let bounds else { return [] }

        let halfX = bounds.extents.x * 0.48
        let halfY = bounds.extents.y * 0.48
        let halfZ = bounds.extents.z * 0.48

        if modelType.classification == .ceiling {
            let y = bounds.center.y + (bounds.extents.y * 0.5)
            return [
                SIMD3<Float>(bounds.center.x - halfX, y, bounds.center.z - halfZ),
                SIMD3<Float>(bounds.center.x - halfX, y, bounds.center.z + halfZ),
                SIMD3<Float>(bounds.center.x + halfX, y, bounds.center.z - halfZ),
                SIMD3<Float>(bounds.center.x + halfX, y, bounds.center.z + halfZ)
            ]
        }

        if modelType.plane == .vertical {
            let z = bounds.center.z - (bounds.extents.z * 0.5)
            return [
                SIMD3<Float>(bounds.center.x - halfX, bounds.center.y - halfY, z),
                SIMD3<Float>(bounds.center.x - halfX, bounds.center.y + halfY, z),
                SIMD3<Float>(bounds.center.x + halfX, bounds.center.y - halfY, z),
                SIMD3<Float>(bounds.center.x + halfX, bounds.center.y + halfY, z)
            ]
        }

        let y = bounds.center.y - (bounds.extents.y * 0.5)
        return [
            SIMD3<Float>(bounds.center.x - halfX, y, bounds.center.z - halfZ),
            SIMD3<Float>(bounds.center.x - halfX, y, bounds.center.z + halfZ),
            SIMD3<Float>(bounds.center.x + halfX, y, bounds.center.z - halfZ),
            SIMD3<Float>(bounds.center.x + halfX, y, bounds.center.z + halfZ)
        ]
    }

    private static func supportReferenceWorldPoint(
        for entity: Entity,
        modelType: ModelType,
        worldPosition: SIMD3<Float>,
        worldOrientation: simd_quatf
    ) -> SIMD3<Float>? {
        guard let bounds = entity.components[ModelBoundsComponent.self] else {
            return worldPosition
        }

        let localPoint: SIMD3<Float>
        if modelType.classification == .ceiling {
            localPoint = SIMD3<Float>(
                bounds.center.x,
                bounds.center.y + (bounds.extents.y * 0.5),
                bounds.center.z
            )
        } else if modelType.plane == .vertical {
            localPoint = SIMD3<Float>(
                bounds.center.x,
                bounds.center.y,
                bounds.center.z - (bounds.extents.z * 0.5)
            )
        } else {
            localPoint = bounds.placementOffset
        }

        return worldPosition + worldOrientation.act(localPoint)
    }

    private static func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func classificationDescription(for classification: PlaneAnchor.Classification) -> String {
        switch classification {
        case .notAvailable:
            return "notAvailable"
        case .undetermined:
            return "undetermined"
        case .unknown:
            return "unknown"
        case .wall:
            return "wall"
        case .floor:
            return "floor"
        case .ceiling:
            return "ceiling"
        case .table:
            return "table"
        case .seat:
            return "seat"
        case .window:
            return "window"
        case .door:
            return "door"
        @unknown default:
            return "unknown"
        }
    }

    private static func horizontalForwardVector(from transform: simd_float4x4, up: SIMD3<Float>) -> SIMD3<Float>? {
        var forward = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        forward -= simd_dot(forward, up) * up
        let magnitude = simd_length_squared(forward)
        guard magnitude >= 1e-6 else { return nil }
        return simd_normalize(forward)
    }

    private static func makeOrientation(forward: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
        let normalizedUp = simd_normalize(up)
        let normalizedForward = simd_normalize(forward)
        var right = simd_cross(normalizedUp, normalizedForward)
        if simd_length_squared(right) < 1e-6 {
            right = SIMD3<Float>(1, 0, 0)
        }
        right = simd_normalize(right)
        let adjustedForward = simd_normalize(simd_cross(right, normalizedUp))
        let rotationMatrix = float3x3(columns: (right, normalizedUp, adjustedForward))
        return simd_quaternion(rotationMatrix)
    }

    private struct ClosestPlanePoint {
        let worldPoint: SIMD3<Float>
        let correctionDistance: Float
        let perpendicularDistance: Float
        let edgeOverflowDistance: Float
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
