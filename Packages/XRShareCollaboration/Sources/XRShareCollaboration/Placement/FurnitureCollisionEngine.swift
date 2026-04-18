import Foundation
import RealityKit

@MainActor
enum FurnitureCollisionEngine {
    struct Result {
        let overlaps: [UUID]
        let resolvedPosition: SIMD3<Float>?

        var hasOverlap: Bool {
            !overlaps.isEmpty
        }
    }

    private struct Footprint {
        let center: SIMD2<Float>
        let axisX: SIMD2<Float>
        let axisZ: SIMD2<Float>
        let halfExtents: SIMD2<Float>
        let yRange: ClosedRange<Float>
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
        guard shouldCheckCollisions(for: modelType) else {
            return Result(overlaps: [], resolvedPosition: nil)
        }

        guard let baseFootprint = footprint(for: entity, relativeTo: anchor) else {
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
        guard shouldCheckCollisions(for: modelType),
              let movingFootprint = footprint(for: entity, relativeTo: anchor) else {
            return false
        }

        return !overlappingInstanceIDs(
            movingFootprint: movingFootprint,
            excluding: instanceID,
            among: placedModels,
            relativeTo: anchor
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
              let movingFootprint = footprint(for: entity, relativeTo: anchor) else {
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
            center: footprint.center + SIMD2<Float>(delta.x, delta.z),
            axisX: footprint.axisX,
            axisZ: footprint.axisZ,
            halfExtents: footprint.halfExtents,
            yRange: (footprint.yRange.lowerBound + delta.y)...(footprint.yRange.upperBound + delta.y)
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
                  let candidateFootprint = footprint(for: entity, relativeTo: anchor),
                  yRangesOverlap(movingFootprint.yRange, candidateFootprint.yRange),
                  footprintsOverlap(lhs: movingFootprint, rhs: candidateFootprint) else {
                return nil
            }
            return model.id
        }
    }

    private static func footprintsOverlap(lhs: Footprint, rhs: Footprint) -> Bool {
        let axes = [lhs.axisX, lhs.axisZ, rhs.axisX, rhs.axisZ]
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

    private static func yRangesOverlap(_ lhs: ClosedRange<Float>, _ rhs: ClosedRange<Float>) -> Bool {
        min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound) > -0.02
    }

    private static func footprint(for entity: Entity, relativeTo anchor: Entity) -> Footprint? {
        if let modelBounds = entity.components[ModelBoundsComponent.self] {
            let centerWorld = entity.convert(position: modelBounds.center, to: anchor)
            let transform = entity.transformMatrix(relativeTo: anchor)
            let axisX3 = SIMD3<Float>(transform.columns.0.x, 0, transform.columns.0.z)
            let axisZ3 = SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
            let bounds = entity.visualBounds(relativeTo: anchor)

            return Footprint(
                center: SIMD2<Float>(centerWorld.x, centerWorld.z),
                axisX: normalized(SIMD2<Float>(axisX3.x, axisX3.z)),
                axisZ: normalized(SIMD2<Float>(axisZ3.x, axisZ3.z)),
                halfExtents: SIMD2<Float>(modelBounds.extents.x * 0.5, modelBounds.extents.z * 0.5),
                yRange: bounds.min.y...bounds.max.y
            )
        }

        let bounds = entity.visualBounds(relativeTo: anchor)
        guard bounds.extents.x.isFinite,
              bounds.extents.y.isFinite,
              bounds.extents.z.isFinite,
              bounds.extents.x > 0,
              bounds.extents.z > 0 else {
            return nil
        }

        return Footprint(
            center: SIMD2<Float>(bounds.center.x, bounds.center.z),
            axisX: SIMD2<Float>(1, 0),
            axisZ: SIMD2<Float>(0, 1),
            halfExtents: SIMD2<Float>(bounds.extents.x * 0.5, bounds.extents.z * 0.5),
            yRange: bounds.min.y...bounds.max.y
        )
    }

    private static func projectionRadius(of footprint: Footprint, onto axis: SIMD2<Float>) -> Float {
        let normalizedAxis = normalized(axis)
        return footprint.halfExtents.x * abs(simd_dot(normalizedAxis, footprint.axisX))
            + footprint.halfExtents.y * abs(simd_dot(normalizedAxis, footprint.axisZ))
    }

    private static func normalized(_ axis: SIMD2<Float>) -> SIMD2<Float> {
        let magnitudeSquared = simd_length_squared(axis)
        guard magnitudeSquared > 1e-6 else {
            return SIMD2<Float>(1, 0)
        }
        return simd_normalize(axis)
    }

    private static func shouldCheckCollisions(for modelType: ModelType) -> Bool {
        modelType.plane == .horizontal && modelType.classification == .floor
    }
}
