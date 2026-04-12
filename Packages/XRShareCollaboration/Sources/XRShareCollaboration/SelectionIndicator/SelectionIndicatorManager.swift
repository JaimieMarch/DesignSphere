import Foundation
import RealityKit
import SwiftUI
import UIKit

#if os(visionOS)
@MainActor
public final class SelectionIndicatorManager: ObservableObject {

    private weak var sharedAnchorEntity: AnchorEntity?
    private weak var trackedEntity: Entity?
    private var indicatorRoot: Entity?
    private var focusPlate: ModelEntity?
    private var cornerSegments: [ModelEntity] = []
    private var lastSignature: Signature?

    private let updateThreshold: Float = 0.001

    public init() {}

    public func setSharedAnchor(_ anchor: AnchorEntity) {
        sharedAnchorEntity = anchor
    }

    public func showSelectionIndicator(for entity: Entity) {
        guard trackedEntity !== entity || indicatorRoot == nil else {
            updateIndicatorPosition(for: entity)
            return
        }

        hideSelectionIndicator()

        guard let sharedAnchor = sharedAnchorEntity else {
            #if DEBUG
            print("Warning: sharedAnchorEntity not set for selection indicator")
            #endif
            return
        }

        let root = Entity()
        let plate = createPlateEntity()
        let segments = (0..<8).map { _ in createCornerSegment() }

        root.addChild(plate)
        for segment in segments {
            root.addChild(segment)
        }
        sharedAnchor.addChild(root)

        indicatorRoot = root
        focusPlate = plate
        cornerSegments = segments
        trackedEntity = entity
        lastSignature = nil

        updateIndicatorPosition(for: entity)
    }

    public func hideSelectionIndicator() {
        indicatorRoot?.removeFromParent()
        indicatorRoot = nil
        focusPlate = nil
        cornerSegments.removeAll()
        trackedEntity = nil
        lastSignature = nil
    }

    public func updateIndicatorPosition(for entity: Entity? = nil) {
        guard let sharedAnchor = sharedAnchorEntity,
              let root = indicatorRoot,
              let plate = focusPlate,
              cornerSegments.count == 8 else {
            return
        }

        let targetEntity = entity ?? trackedEntity
        guard let targetEntity,
              targetEntity.parent != nil else {
            hideSelectionIndicator()
            return
        }

        let bounds = targetEntity.visualBounds(relativeTo: sharedAnchor)
        guard bounds.extents.x.isFinite,
              bounds.extents.y.isFinite,
              bounds.extents.z.isFinite,
              bounds.extents.x > 0,
              bounds.extents.y > 0,
              bounds.extents.z > 0 else {
            hideSelectionIndicator()
            return
        }

        let signature = Signature(center: bounds.center, extents: bounds.extents)
        if let lastSignature,
           lastSignature.isApproximatelyEqual(to: signature, threshold: updateThreshold) {
            return
        }

        lastSignature = signature
        applyLayout(
            to: root,
            plate: plate,
            cornerSegments: cornerSegments,
            bounds: bounds,
            relativeTo: sharedAnchor
        )
    }

    // MARK: - Layout

    private func applyLayout(
        to root: Entity,
        plate: ModelEntity,
        cornerSegments: [ModelEntity],
        bounds: BoundingBox,
        relativeTo sharedAnchor: AnchorEntity
    ) {
        let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        let horizontalPadding = min(max(maxDimension * 0.11, 0.045), 0.12)
        let verticalOffset = min(max(maxDimension * 0.055, 0.04), 0.09)
        let width = max(bounds.extents.x + horizontalPadding, 0.12)
        let depth = max(bounds.extents.z + horizontalPadding, 0.12)
        let thickness = min(max(maxDimension * 0.012, 0.005), 0.012)
        let segmentWidth = min(max(width * 0.22, 0.045), 0.16)
        let segmentDepth = min(max(depth * 0.22, 0.045), 0.16)
        let plateHeight = thickness * 0.24
        let plateInset = thickness * 1.8

        root.setPosition(
            SIMD3<Float>(bounds.center.x, bounds.max.y + verticalOffset, bounds.center.z),
            relativeTo: sharedAnchor
        )

        plate.position = SIMD3<Float>(0, -thickness * 0.1, 0)
        plate.scale = SIMD3<Float>(
            max(width - plateInset, thickness * 2),
            plateHeight,
            max(depth - plateInset, thickness * 2)
        )

        let halfWidth = width * 0.5
        let halfDepth = depth * 0.5
        let xInset = halfWidth - (segmentWidth * 0.5)
        let zInset = halfDepth - (segmentDepth * 0.5)

        let layouts: [(position: SIMD3<Float>, scale: SIMD3<Float>)] = [
            (SIMD3<Float>(-xInset, 0, -halfDepth), SIMD3<Float>(segmentWidth, thickness, thickness)),
            (SIMD3<Float>(-halfWidth, 0, -zInset), SIMD3<Float>(thickness, thickness, segmentDepth)),
            (SIMD3<Float>(xInset, 0, -halfDepth), SIMD3<Float>(segmentWidth, thickness, thickness)),
            (SIMD3<Float>(halfWidth, 0, -zInset), SIMD3<Float>(thickness, thickness, segmentDepth)),
            (SIMD3<Float>(-xInset, 0, halfDepth), SIMD3<Float>(segmentWidth, thickness, thickness)),
            (SIMD3<Float>(-halfWidth, 0, zInset), SIMD3<Float>(thickness, thickness, segmentDepth)),
            (SIMD3<Float>(xInset, 0, halfDepth), SIMD3<Float>(segmentWidth, thickness, thickness)),
            (SIMD3<Float>(halfWidth, 0, zInset), SIMD3<Float>(thickness, thickness, segmentDepth))
        ]

        for (segment, layout) in zip(cornerSegments, layouts) {
            segment.position = layout.position
            segment.scale = layout.scale
        }
    }

    // MARK: - Factory

    private func createPlateEntity() -> ModelEntity {
        let plate = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(repeating: 1), cornerRadius: 0.22),
            materials: [plateMaterial()]
        )
        return plate
    }

    private func createCornerSegment() -> ModelEntity {
        let segment = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(repeating: 1), cornerRadius: 0.18),
            materials: [accentMaterial()]
        )
        return segment
    }

    private func accentMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.95, green: 0.82, blue: 0.56, alpha: 0.98))
        return material
    }

    private func plateMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.95, green: 0.82, blue: 0.56, alpha: 0.14))
        material.blending = .transparent(opacity: 0.14)
        return material
    }
}

private extension SelectionIndicatorManager {
    struct Signature {
        let center: SIMD3<Float>
        let extents: SIMD3<Float>

        func isApproximatelyEqual(to other: Signature, threshold: Float) -> Bool {
            simd_distance(center, other.center) <= threshold &&
            simd_distance(extents, other.extents) <= threshold
        }
    }
}
#endif
