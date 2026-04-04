#if os(visionOS)
import ARKit
import Metal
import RealityKit
import simd

@available(visionOS 2.0, *)
enum RoomMeshPlacementEngine {
    static func placementForSpawn(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        deviceTransform: simd_float4x4,
        roomAnchor: RoomAnchor,
        options: SurfaceSnappingEngine.Options = .initialPlacement
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
            roomAnchor: roomAnchor,
            options: options
        )
    }

    static func placementForManipulation(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        viewerWorldPosition: SIMD3<Float>,
        roomAnchor: RoomAnchor,
        options: SurfaceSnappingEngine.Options = .manipulation
    ) -> SurfacePlacement? {
        let referencePoint = snapReferencePoint(for: entity, modelType: modelType, relativeTo: nil)

        return resolvePlacement(
            entity: entity,
            modelType: modelType,
            sharedAnchor: sharedAnchor,
            preferredWorldPoint: referencePoint,
            viewerWorldPosition: viewerWorldPosition,
            roomAnchor: roomAnchor,
            options: options
        )
    }

    private static func resolvePlacement(
        entity: Entity,
        modelType: ModelType,
        sharedAnchor: AnchorEntity,
        preferredWorldPoint: SIMD3<Float>,
        viewerWorldPosition: SIMD3<Float>,
        roomAnchor: RoomAnchor,
        options: SurfaceSnappingEngine.Options
    ) -> SurfacePlacement? {
        let desiredClassifications = meshClassifications(for: modelType)
        let candidates = extractCandidates(
            from: roomAnchor,
            preferredWorldPoint: preferredWorldPoint,
            desiredClassifications: desiredClassifications,
            preferredAlignment: modelType.plane
        )

        guard !candidates.isEmpty else { return nil }

        let bounds = entity.components[ModelBoundsComponent.self]
        var bestCandidate: (
            worldPosition: SIMD3<Float>,
            worldOrientation: simd_quatf?,
            score: Float
        )?

        for candidate in candidates {
            guard candidate.correctionDistance <= options.maxSnapDistance else { continue }
            guard candidate.perpendicularDistance <= options.maxPerpendicularDistance else { continue }
            guard candidate.edgeOverflowDistance <= options.maxEdgeOverflowDistance else { continue }

            let worldPosition = resolvedWorldPosition(
                bounds: bounds,
                modelType: modelType,
                snappedPoint: candidate.closestPoint,
                surfaceNormal: candidate.normal,
                viewerWorldPosition: viewerWorldPosition
            )
            guard roomAnchor.contains(worldPosition) else { continue }

            let worldOrientation = resolvedWorldOrientation(
                for: entity,
                modelType: modelType,
                snappedPoint: candidate.closestPoint,
                surfaceNormal: candidate.normal,
                viewerWorldPosition: viewerWorldPosition
            )
            let score = candidate.correctionDistance
                + (candidate.perpendicularDistance * 0.35)
                + (candidate.edgeOverflowDistance * 0.2)
                + surfacePenalty(for: modelType, classification: candidate.classification)
                + orientationPenalty(
                    for: entity,
                    snappedPoint: candidate.closestPoint,
                    surfaceNormal: candidate.normal,
                    viewerWorldPosition: viewerWorldPosition
                )

            if let currentBest = bestCandidate {
                if score < currentBest.score {
                    bestCandidate = (
                        worldPosition,
                        worldOrientation,
                        score
                    )
                }
            } else {
                bestCandidate = (
                    worldPosition,
                    worldOrientation,
                    score
                )
            }
        }

        guard let bestCandidate else { return nil }
        return SurfacePlacement(
            localPosition: worldToLocal(bestCandidate.worldPosition, relativeTo: sharedAnchor),
            worldOrientation: bestCandidate.worldOrientation,
            source: .roomMesh(roomAnchor.id)
        )
    }

    private static func extractCandidates(
        from roomAnchor: RoomAnchor,
        preferredWorldPoint: SIMD3<Float>,
        desiredClassifications: Set<MeshAnchor.MeshClassification>,
        preferredAlignment: AnchoringComponent.Target.Alignment
    ) -> [TriangleCandidate] {
        let geometry = roomAnchor.geometry
        let vertices = decodeVertices(from: geometry.vertices)
        let classifications = decodeClassifications(from: geometry.classifications)
        let faces = geometry.faces

        guard faces.primitive == .triangle else { return [] }

        let roomTransform = roomAnchor.originFromAnchorTransform
        let faceCount = faces.count
        var candidates: [TriangleCandidate] = []
        candidates.reserveCapacity(faceCount)

        for faceIndex in 0..<faceCount {
            let classification = classifications.flatMap { faceIndex < $0.count ? $0[faceIndex] : nil }

            if let classification,
               !desiredClassifications.isEmpty,
               !desiredClassifications.contains(classification) {
                continue
            }

            guard let indices = readTriangleIndices(from: faces, faceIndex: faceIndex),
                  indices.0 < vertices.count,
                  indices.1 < vertices.count,
                  indices.2 < vertices.count else { continue }

            let worldA = roomTransform.transformPoint(vertices[indices.0])
            let worldB = roomTransform.transformPoint(vertices[indices.1])
            let worldC = roomTransform.transformPoint(vertices[indices.2])

            guard let candidate = candidateForTriangle(
                worldA,
                worldB,
                worldC,
                classification: classification,
                preferredWorldPoint: preferredWorldPoint,
                preferredAlignment: preferredAlignment
            ) else { continue }

            candidates.append(candidate)
        }

        return candidates
    }

    private static func candidateForTriangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        classification: MeshAnchor.MeshClassification?,
        preferredWorldPoint: SIMD3<Float>,
        preferredAlignment: AnchoringComponent.Target.Alignment
    ) -> TriangleCandidate? {
        let ab = b - a
        let ac = c - a
        let unnormalizedNormal = simd_cross(ab, ac)
        let normalLengthSquared = simd_length_squared(unnormalizedNormal)
        guard normalLengthSquared >= 1e-8 else { return nil }

        let normal = simd_normalize(unnormalizedNormal)
        guard alignmentMatches(preferredAlignment, surfaceNormal: normal) else { return nil }

        let closestPoint = closestPointOnTriangle(
            point: preferredWorldPoint,
            a: a,
            b: b,
            c: c
        )

        let signedDistance = simd_dot(preferredWorldPoint - a, normal)
        let projectedPoint = preferredWorldPoint - (normal * signedDistance)

        return TriangleCandidate(
            closestPoint: closestPoint,
            classification: classification,
            normal: normal,
            correctionDistance: simd_distance(preferredWorldPoint, closestPoint),
            perpendicularDistance: abs(signedDistance),
            edgeOverflowDistance: simd_distance(projectedPoint, closestPoint)
        )
    }

    private static func decodeVertices(from source: GeometrySource) -> [SIMD3<Float>] {
        guard source.count > 0 else { return [] }

        let rawPointer = source.buffer.contents()
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(source.count)

        for index in 0..<source.count {
            let vectorPointer = rawPointer.advanced(by: source.offset + (index * source.stride))
            let floatPointer = vectorPointer.bindMemory(to: Float.self, capacity: max(source.componentsPerVector, 3))
            let x = floatPointer[0]
            let y = source.componentsPerVector > 1 ? floatPointer[1] : 0
            let z = source.componentsPerVector > 2 ? floatPointer[2] : 0
            vertices.append(SIMD3<Float>(x, y, z))
        }

        return vertices
    }

    private static func decodeClassifications(
        from source: GeometrySource?
    ) -> [MeshAnchor.MeshClassification]? {
        guard let source, source.count > 0 else { return nil }

        let rawPointer = source.buffer.contents()
        var classifications: [MeshAnchor.MeshClassification] = []
        classifications.reserveCapacity(source.count)

        for index in 0..<source.count {
            let scalarPointer = rawPointer.advanced(by: source.offset + (index * source.stride))
            let rawValue = readUnsignedInteger(from: scalarPointer, byteCount: max(source.stride, 1))
            guard let classification = MeshAnchor.MeshClassification(rawValue: Int(rawValue)) else {
                classifications.append(.none)
                continue
            }
            classifications.append(classification)
        }

        return classifications
    }

    private static func readTriangleIndices(
        from faces: GeometryElement,
        faceIndex: Int
    ) -> (Int, Int, Int)? {
        let bytesPerFace = faces.bytesPerIndex * 3
        let facePointer = faces.buffer.contents().advanced(by: faceIndex * bytesPerFace)

        let i0 = Int(readUnsignedInteger(from: facePointer, byteCount: faces.bytesPerIndex))
        let i1 = Int(readUnsignedInteger(from: facePointer.advanced(by: faces.bytesPerIndex), byteCount: faces.bytesPerIndex))
        let i2 = Int(readUnsignedInteger(from: facePointer.advanced(by: faces.bytesPerIndex * 2), byteCount: faces.bytesPerIndex))
        return (i0, i1, i2)
    }

    private static func readUnsignedInteger(from pointer: UnsafeMutableRawPointer, byteCount: Int) -> UInt64 {
        switch byteCount {
        case 1:
            return UInt64(pointer.load(as: UInt8.self))
        case 2:
            return UInt64(pointer.load(as: UInt16.self))
        case 4:
            return UInt64(pointer.load(as: UInt32.self))
        case 8:
            return pointer.load(as: UInt64.self)
        default:
            return UInt64(pointer.load(as: UInt32.self))
        }
    }

    private static func meshClassifications(for modelType: ModelType) -> Set<MeshAnchor.MeshClassification> {
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
            default:
                return []
            }
        }
    }

    private static func surfacePenalty(
        for modelType: ModelType,
        classification: MeshAnchor.MeshClassification?
    ) -> Float {
        guard modelType.classification == .any else { return 0 }

        guard let classification else {
            return 0.025
        }

        if modelType.plane == .vertical {
            switch classification {
            case .wall:
                return 0
            case .window:
                return 0.04
            case .door:
                return 0.07
            case .cabinet, .tv:
                return 0.05
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
            case .seat, .bed:
                return 0.05
            default:
                return 0.03
            }
        }

        return 0.02
    }

    private static func alignmentMatches(
        _ preferred: AnchoringComponent.Target.Alignment,
        surfaceNormal: SIMD3<Float>
    ) -> Bool {
        if preferred == .any {
            return true
        }

        let upAlignment = abs(simd_dot(simd_normalize(surfaceNormal), SIMD3<Float>(0, 1, 0)))
        if preferred == .horizontal {
            return upAlignment >= 0.82
        }
        if preferred == .vertical {
            return upAlignment <= 0.25
        }
        return true
    }

    private static func resolvedWorldPosition(
        bounds: ModelBoundsComponent?,
        modelType: ModelType,
        snappedPoint: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>,
        viewerWorldPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        if modelType.plane == .vertical {
            let modelCenter = bounds?.center ?? .zero
            let depth = bounds?.extents.z ?? 0
            var outward = simd_normalize(surfaceNormal)
            if simd_dot(outward, viewerWorldPosition - snappedPoint) < 0 {
                outward *= -1
            }
            let wallPadding = max(depth * 0.5, 0.01)
            return snappedPoint - modelCenter + (outward * wallPadding)
        }

        if modelType.classification == .ceiling {
            let ceilingOffset = ceilingAttachmentOffset(from: bounds)
            return snappedPoint - ceilingOffset
        }

        let placementOffset = bounds?.placementOffset ?? .zero
        return snappedPoint - placementOffset
    }

    private static func resolvedWorldOrientation(
        for entity: Entity,
        modelType: ModelType,
        snappedPoint: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>,
        viewerWorldPosition: SIMD3<Float>
    ) -> simd_quatf? {
        let worldUp = SIMD3<Float>(0, 1, 0)
        let worldTransform = entity.transformMatrix(relativeTo: nil)

        if modelType.plane == .vertical {
            var outward = simd_normalize(surfaceNormal)
            if simd_dot(outward, viewerWorldPosition - snappedPoint) < 0 {
                outward *= -1
            }
            return makeOrientation(forward: outward, up: worldUp)
        }

        guard let forward = horizontalForwardVector(from: worldTransform, up: worldUp) else {
            return nil
        }
        return makeOrientation(forward: forward, up: worldUp)
    }

    private static func orientationPenalty(
        for entity: Entity,
        snappedPoint: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>,
        viewerWorldPosition: SIMD3<Float>
    ) -> Float {
        let upAlignment = abs(simd_dot(simd_normalize(surfaceNormal), SIMD3<Float>(0, 1, 0)))
        guard upAlignment <= 0.25 else { return 0 }

        let worldUp = SIMD3<Float>(0, 1, 0)
        let worldTransform = entity.transformMatrix(relativeTo: nil)
        guard let currentForward = horizontalForwardVector(from: worldTransform, up: worldUp) else {
            return 0
        }

        var targetForward = simd_normalize(surfaceNormal)
        if simd_dot(targetForward, viewerWorldPosition - snappedPoint) < 0 {
            targetForward *= -1
        }

        let alignment = max(simd_dot(currentForward, targetForward), 0)
        return (1 - alignment) * 0.025
    }

    private static func ceilingAttachmentOffset(from bounds: ModelBoundsComponent?) -> SIMD3<Float> {
        guard let bounds else { return .zero }
        return SIMD3<Float>(
            bounds.center.x,
            bounds.center.y + (bounds.extents.y * 0.5),
            bounds.center.z
        )
    }

    private static func deviceTargetPoint(
        from deviceTransform: simd_float4x4,
        preferredDistance: Float
    ) -> SIMD3<Float> {
        let position = deviceTransform.translation
        let forward = simd_normalize(-deviceTransform.forward)
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

        if modelType.classification == .ceiling {
            let topPoint = SIMD3<Float>(
                bounds.center.x,
                bounds.center.y + (bounds.extents.y * 0.5),
                bounds.center.z
            )
            return entity.convert(position: topPoint, to: reference)
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

    private static func closestPointOnTriangle(
        point p: SIMD3<Float>,
        a: SIMD3<Float>,
        b: SIMD3<Float>,
        c: SIMD3<Float>
    ) -> SIMD3<Float> {
        let ab = b - a
        let ac = c - a
        let ap = p - a

        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0, d2 <= 0 { return a }

        let bp = p - b
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0, d4 <= d3 { return b }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            let v = d1 / (d1 - d3)
            return a + (ab * v)
        }

        let cp = p - c
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0, d5 <= d6 { return c }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            let w = d2 / (d2 - d6)
            return a + (ac * w)
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0, (d4 - d3) >= 0, (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return b + ((c - b) * w)
        }

        let denom = 1 / (va + vb + vc)
        let v = vb * denom
        let w = vc * denom
        return a + (ab * v) + (ac * w)
    }

    private static func worldToLocal(_ worldPoint: SIMD3<Float>, relativeTo anchor: AnchorEntity) -> SIMD3<Float> {
        anchor.transform.matrix.inverse.transformPoint(worldPoint)
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

    private struct TriangleCandidate {
        let closestPoint: SIMD3<Float>
        let classification: MeshAnchor.MeshClassification?
        let normal: SIMD3<Float>
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
#endif
