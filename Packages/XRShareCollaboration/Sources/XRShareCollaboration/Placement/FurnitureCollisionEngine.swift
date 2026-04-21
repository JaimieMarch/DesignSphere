import Foundation
import RealityKit
import simd

@MainActor
enum FurnitureCollisionEngine {
    private enum SupportFamily {
        case floor
        case wall
        case ceiling
    }

    struct Result {
        let overlaps: [UUID]
        let resolvedPosition: SIMD3<Float>?

        var hasOverlap: Bool {
            !overlaps.isEmpty
        }
    }

    private struct Footprint {
        let family: SupportFamily
        let center: SIMD3<Float>
        let axisU: SIMD3<Float>
        let axisV: SIMD3<Float>
        let halfExtents: SIMD2<Float>
        let supportPoint: SIMD3<Float>
        let supportNormal: SIMD3<Float>
    }

    private static let horizontalStep: Float = 0.05
    private static let maxSearchRadius: Float = 0.70
    private static let spacingMargin: Float = 0.08

    static func resolve(
        entity: Entity,
        instanceID: UUID,
        modelType: ModelType,
        relativeTo anchor: Entity,
        among placedModels: [Model],
        mode: FurnitureCollisionMode,
        lastValidPosition: SIMD3<Float>? = nil,
        positionValidator: ((SIMD3<Float>) -> Bool)? = nil,
        allowSearch: Bool = true
    ) -> Result {
        guard shouldCheckCollisions(for: modelType),
              let baseFootprint = footprint(for: entity, modelType: modelType, relativeTo: anchor) else {
            return Result(overlaps: [], resolvedPosition: nil)
        }

        let currentPosition = entity.position(relativeTo: anchor)
        let overlaps = overlappingInstanceIDs(
            movingFootprint: baseFootprint,
            excluding: instanceID,
            among: placedModels,
            relativeTo: anchor
        )

        guard !overlaps.isEmpty else {
            return Result(overlaps: [], resolvedPosition: currentPosition)
        }

        guard mode == .prevent else {
            return Result(overlaps: overlaps, resolvedPosition: currentPosition)
        }

        if allowSearch,
           baseFootprint.family == .floor,
           let resolvedPosition = nearestFreePosition(
                from: currentPosition,
                using: baseFootprint,
                excluding: instanceID,
                among: placedModels,
                relativeTo: anchor,
                positionValidator: positionValidator
           ) {
            return Result(overlaps: overlaps, resolvedPosition: resolvedPosition)
        }

        if let lastValidPosition,
           isFree(
                proposedPosition: lastValidPosition,
                currentPosition: currentPosition,
                movingFootprint: baseFootprint,
                excluding: instanceID,
                among: placedModels,
                relativeTo: anchor,
                positionValidator: positionValidator
           ) {
            return Result(overlaps: overlaps, resolvedPosition: lastValidPosition)
        }

        return Result(overlaps: overlaps, resolvedPosition: nil)
    }

    static func hasOverlap(
        entity: Entity,
        instanceID: UUID,
        modelType: ModelType,
        relativeTo anchor: Entity,
        among placedModels: [Model]
    ) -> Bool {
        !overlappingIDs(
            entity: entity,
            instanceID: instanceID,
            modelType: modelType,
            relativeTo: anchor,
            among: placedModels
        ).isEmpty
    }

    static func overlappingIDs(
        entity: Entity,
        instanceID: UUID,
        modelType: ModelType,
        relativeTo anchor: Entity,
        among placedModels: [Model]
    ) -> [UUID] {
        guard shouldCheckCollisions(for: modelType),
              let movingFootprint = footprint(for: entity, modelType: modelType, relativeTo: anchor) else {
            return []
        }

        return overlappingInstanceIDs(
            movingFootprint: movingFootprint,
            excluding: instanceID,
            among: placedModels,
            relativeTo: anchor
        )
    }

    private static func nearestFreePosition(
        from currentPosition: SIMD3<Float>,
        using movingFootprint: Footprint,
        excluding instanceID: UUID,
        among placedModels: [Model],
        relativeTo anchor: Entity,
        positionValidator: ((SIMD3<Float>) -> Bool)?
    ) -> SIMD3<Float>? {
        if isFree(
            proposedPosition: currentPosition,
            currentPosition: currentPosition,
            movingFootprint: movingFootprint,
            excluding: instanceID,
            among: placedModels,
            relativeTo: anchor,
            positionValidator: positionValidator
        ) {
            return currentPosition
        }

        let directions: [SIMD2<Float>] = [
            SIMD2<Float>(1, 0),
            SIMD2<Float>(-1, 0),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(0, -1),
            simd_normalize(SIMD2<Float>(1, 1)),
            simd_normalize(SIMD2<Float>(1, -1)),
            simd_normalize(SIMD2<Float>(-1, 1)),
            simd_normalize(SIMD2<Float>(-1, -1))
        ]

        var radius = horizontalStep
        while radius <= maxSearchRadius {
            for direction in directions {
                let candidate = SIMD3<Float>(
                    currentPosition.x + (direction.x * radius),
                    currentPosition.y,
                    currentPosition.z + (direction.y * radius)
                )
                if isFree(
                    proposedPosition: candidate,
                    currentPosition: currentPosition,
                    movingFootprint: movingFootprint,
                    excluding: instanceID,
                    among: placedModels,
                    relativeTo: anchor,
                    positionValidator: positionValidator
                ) {
                    return candidate
                }
            }
            radius += horizontalStep
        }

        return nil
    }

    private static func isFree(
        proposedPosition: SIMD3<Float>,
        currentPosition: SIMD3<Float>,
        movingFootprint: Footprint,
        excluding instanceID: UUID,
        among placedModels: [Model],
        relativeTo anchor: Entity,
        positionValidator: ((SIMD3<Float>) -> Bool)?
    ) -> Bool {
        if let positionValidator, !positionValidator(proposedPosition) {
            return false
        }

        let candidateFootprint = translatedFootprint(
            from: movingFootprint,
            currentPosition: currentPosition,
            proposedPosition: proposedPosition
        )
        return overlappingInstanceIDs(
            movingFootprint: candidateFootprint,
            excluding: instanceID,
            among: placedModels,
            relativeTo: anchor
        ).isEmpty
    }

    private static func translatedFootprint(
        from footprint: Footprint,
        currentPosition: SIMD3<Float>,
        proposedPosition: SIMD3<Float>
    ) -> Footprint {
        let delta = proposedPosition - currentPosition
        return Footprint(
            family: footprint.family,
            center: footprint.center + delta,
            axisU: footprint.axisU,
            axisV: footprint.axisV,
            halfExtents: footprint.halfExtents,
            supportPoint: footprint.supportPoint + delta,
            supportNormal: footprint.supportNormal
        )
    }

    private static func overlappingInstanceIDs(
        movingFootprint: Footprint,
        excluding instanceID: UUID,
        among placedModels: [Model],
        relativeTo anchor: Entity
    ) -> [UUID] {
        placedModels.compactMap { model in
            guard model.id != instanceID,
                  shouldCheckCollisions(for: model.modelType),
                  let entity = model.modelEntity,
                  entity.parent != nil,
                  let candidateFootprint = footprint(for: entity, modelType: model.modelType, relativeTo: anchor),
                  supportsComparableCollision(lhs: movingFootprint, rhs: candidateFootprint),
                  footprintsOverlap(lhs: movingFootprint, rhs: candidateFootprint) else {
                return nil
            }
            return model.id
        }
    }

    private static func footprintsOverlap(lhs: Footprint, rhs: Footprint) -> Bool {
        let axes = [lhs.axisU, lhs.axisV, rhs.axisU, rhs.axisV]
        for axis in axes {
            let normalizedAxis = normalized(axis)
            let centerDelta = abs(simd_dot(rhs.center - lhs.center, normalizedAxis))
            let lhsRadius = projectionRadius(of: lhs, onto: normalizedAxis)
            let rhsRadius = projectionRadius(of: rhs, onto: normalizedAxis)

            if centerDelta > (lhsRadius + rhsRadius + spacingMargin) {
                return false
            }
        }

        return true
    }

    private static func supportsComparableCollision(lhs: Footprint, rhs: Footprint) -> Bool {
        guard lhs.family == rhs.family else { return false }

        switch lhs.family {
        case .floor:
            let normalAlignment = abs(simd_dot(lhs.supportNormal, rhs.supportNormal))
            guard normalAlignment >= 0.95 else { return false }
            let planeSeparation = abs(simd_dot(rhs.supportPoint - lhs.supportPoint, lhs.supportNormal))
            return planeSeparation <= 0.12
        case .wall:
            let normalAlignment = simd_dot(lhs.supportNormal, rhs.supportNormal)
            guard normalAlignment >= 0.98 else { return false }
            let planeSeparation = abs(simd_dot(rhs.supportPoint - lhs.supportPoint, lhs.supportNormal))
            return planeSeparation <= 0.08
        case .ceiling:
            let normalAlignment = abs(simd_dot(lhs.supportNormal, rhs.supportNormal))
            guard normalAlignment >= 0.985 else { return false }
            let planeSeparation = abs(simd_dot(rhs.supportPoint - lhs.supportPoint, lhs.supportNormal))
            return planeSeparation <= 0.08
        }
    }

    private static func footprint(
        for entity: Entity,
        modelType: ModelType,
        relativeTo anchor: Entity
    ) -> Footprint? {
        if let modelBounds = entity.components[ModelBoundsComponent.self] {
            let transform = entity.transformMatrix(relativeTo: anchor)
            let snapState = entity.components[SnapStateComponent.self]

            if let family = supportFamily(for: modelType) {
                let fallbackNormal: SIMD3<Float>
                switch family {
                case .floor:
                    fallbackNormal = SIMD3<Float>(0, 1, 0)
                case .wall:
                    let forward = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
                    fallbackNormal = normalized(forward)
                case .ceiling:
                    fallbackNormal = SIMD3<Float>(0, -1, 0)
                }

                let supportNormal = normalized(snapState?.supportNormal ?? fallbackNormal)
                let supportPoint = snapState?.supportPosition
                    ?? entity.convert(
                        position: supportReferenceLocalPoint(bounds: modelBounds, family: family),
                        to: anchor
                    )

                return orientedFootprint(
                    for: entity,
                    bounds: modelBounds,
                    family: family,
                    supportNormal: supportNormal,
                    supportPoint: supportPoint,
                    transform: transform,
                    relativeTo: anchor
                )
            }
        }

        let bounds = entity.visualBounds(relativeTo: anchor)
        guard bounds.extents.x.isFinite,
              bounds.extents.z.isFinite,
              bounds.extents.x > 0,
              bounds.extents.z > 0 else {
            return nil
        }

        return Footprint(
            family: .floor,
            center: SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z),
            axisU: SIMD3<Float>(1, 0, 0),
            axisV: SIMD3<Float>(0, 0, 1),
            halfExtents: SIMD2<Float>(bounds.extents.x * 0.5, bounds.extents.z * 0.5),
            supportPoint: SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z),
            supportNormal: SIMD3<Float>(0, 1, 0)
        )
    }

    private static func orientedFootprint(
        for entity: Entity,
        bounds: ModelBoundsComponent,
        family: SupportFamily,
        supportNormal: SIMD3<Float>,
        supportPoint: SIMD3<Float>,
        transform: simd_float4x4,
        relativeTo anchor: Entity
    ) -> Footprint {
        switch family {
        case .floor, .ceiling:
            let localCenter = SIMD3<Float>(
                bounds.center.x,
                family == .ceiling ? bounds.center.y + (bounds.extents.y * 0.5) : bounds.center.y - (bounds.extents.y * 0.5),
                bounds.center.z
            )
            let center = entity.convert(position: localCenter, to: anchor)
            let worldAxisX = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            let worldAxisZ = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

            let axisU = normalized(project(worldAxisX, ontoPlaneWithNormal: supportNormal))
            let axisV = normalized(project(worldAxisZ, ontoPlaneWithNormal: supportNormal))
            return Footprint(
                family: family,
                center: center,
                axisU: axisU,
                axisV: axisV,
                halfExtents: SIMD2<Float>(bounds.extents.x * 0.5, bounds.extents.z * 0.5),
                supportPoint: supportPoint,
                supportNormal: supportNormal
            )
        case .wall:
            let center = entity.convert(position: bounds.center, to: anchor)
            let worldAxisX = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            let worldAxisY = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)

            let axisU = normalized(project(worldAxisX, ontoPlaneWithNormal: supportNormal))
            let axisV = normalized(project(worldAxisY, ontoPlaneWithNormal: supportNormal))
            return Footprint(
                family: .wall,
                center: center,
                axisU: axisU,
                axisV: axisV,
                halfExtents: SIMD2<Float>(bounds.extents.x * 0.5, bounds.extents.y * 0.5),
                supportPoint: supportPoint,
                supportNormal: supportNormal
            )
        }
    }

    private static func supportFamily(for modelType: ModelType) -> SupportFamily? {
        switch modelType.classification {
        case .floor:
            return .floor
        case .wall:
            return .wall
        case .ceiling:
            return .ceiling
        default:
            return nil
        }
    }

    private static func supportReferenceLocalPoint(
        bounds: ModelBoundsComponent,
        family: SupportFamily
    ) -> SIMD3<Float> {
        switch family {
        case .floor:
            return bounds.placementOffset
        case .ceiling:
            return SIMD3<Float>(
                bounds.center.x,
                bounds.center.y + (bounds.extents.y * 0.5),
                bounds.center.z
            )
        case .wall:
            return bounds.center
        }
    }

    private static func projectionRadius(of footprint: Footprint, onto axis: SIMD3<Float>) -> Float {
        let normalizedAxis = normalized(axis)
        return footprint.halfExtents.x * abs(simd_dot(normalizedAxis, footprint.axisU))
            + footprint.halfExtents.y * abs(simd_dot(normalizedAxis, footprint.axisV))
    }

    private static func project(_ vector: SIMD3<Float>, ontoPlaneWithNormal normal: SIMD3<Float>) -> SIMD3<Float> {
        vector - (simd_dot(vector, normal) * normal)
    }

    private static func normalized(_ axis: SIMD3<Float>) -> SIMD3<Float> {
        let magnitudeSquared = simd_length_squared(axis)
        guard magnitudeSquared > 1e-6 else {
            return SIMD3<Float>(1, 0, 0)
        }
        return simd_normalize(axis)
    }

    private static func shouldCheckCollisions(for modelType: ModelType) -> Bool {
        switch modelType.classification {
        case .floor, .wall, .ceiling:
            return true
        default:
            return false
        }
    }
}
