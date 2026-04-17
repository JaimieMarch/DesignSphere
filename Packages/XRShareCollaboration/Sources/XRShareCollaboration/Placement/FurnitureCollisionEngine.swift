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
        let extents: SIMD2<Float>
        let yRange: ClosedRange<Float>

        var minX: Float { center.x - (extents.x * 0.5) }
        var maxX: Float { center.x + (extents.x * 0.5) }
        var minZ: Float { center.y - (extents.y * 0.5) }
        var maxZ: Float { center.y + (extents.y * 0.5) }
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
        positionValidator: ((SIMD3<Float>) -> Bool)? = nil
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

        if let resolvedPosition = nearestFreePosition(
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
            extents: footprint.extents,
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
        let xOverlap = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
        let zOverlap = min(lhs.maxZ, rhs.maxZ) - max(lhs.minZ, rhs.minZ)
        return xOverlap > -spacingMargin && zOverlap > -spacingMargin
    }

    private static func yRangesOverlap(_ lhs: ClosedRange<Float>, _ rhs: ClosedRange<Float>) -> Bool {
        min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound) > -0.02
    }

    private static func footprint(for entity: Entity, relativeTo anchor: Entity) -> Footprint? {
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
            extents: SIMD2<Float>(bounds.extents.x, bounds.extents.z),
            yRange: bounds.min.y...bounds.max.y
        )
    }

    private static func shouldCheckCollisions(for modelType: ModelType) -> Bool {
        modelType.plane == .horizontal && modelType.classification == .floor
    }
}
