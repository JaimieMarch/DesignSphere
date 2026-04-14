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
    private var guideStem: ModelEntity?
    private var guideCap: ModelEntity?
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
        let stem = createGuideStem()
        let cap = createGuideCap()

        root.addChild(plate)
        for segment in segments {
            root.addChild(segment)
        }
        root.addChild(stem)
        root.addChild(cap)
        sharedAnchor.addChild(root)

        indicatorRoot = root
        focusPlate = plate
        cornerSegments = segments
        guideStem = stem
        guideCap = cap
        trackedEntity = entity
        lastSignature = nil

        updateIndicatorPosition(for: entity)
    }

    public func hideSelectionIndicator() {
        indicatorRoot?.removeFromParent()
        indicatorRoot = nil
        focusPlate = nil
        cornerSegments.removeAll()
        guideStem = nil
        guideCap = nil
        trackedEntity = nil
        lastSignature = nil
    }

    public func updateIndicatorPosition(for entity: Entity? = nil) {
        guard let sharedAnchor = sharedAnchorEntity,
              let root = indicatorRoot,
              let plate = focusPlate,
              let guideStem,
              let guideCap,
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
            guideStem: guideStem,
            guideCap: guideCap,
            bounds: bounds,
            relativeTo: sharedAnchor
        )
    }

    // MARK: - Layout

    private func applyLayout(
        to root: Entity,
        plate: ModelEntity,
        cornerSegments: [ModelEntity],
        guideStem: ModelEntity,
        guideCap: ModelEntity,
        bounds: BoundingBox,
        relativeTo sharedAnchor: AnchorEntity
    ) {
        let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        let horizontalPadding = min(max(maxDimension * 0.095, 0.04), 0.10)
        let verticalOffset = min(max(maxDimension * 0.065, 0.05), 0.10)
        let width = max(bounds.extents.x + horizontalPadding, 0.12)
        let depth = max(bounds.extents.z + horizontalPadding, 0.12)
        let thickness = min(max(maxDimension * 0.010, 0.004), 0.010)
        let segmentWidth = min(max(width * 0.20, 0.04), 0.14)
        let segmentDepth = min(max(depth * 0.20, 0.04), 0.14)
        let plateHeight = thickness * 0.18
        let plateInset = thickness * 1.4
        let stemHeight = max(verticalOffset - (thickness * 1.2), thickness * 1.8)
        let capHeight = thickness * 1.4
        let capWidth = min(max(width * 0.22, 0.035), 0.08)
        let capDepth = min(max(depth * 0.16, 0.03), 0.06)

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
        guideStem.position = SIMD3<Float>(0, -(stemHeight * 0.5), 0)
        guideStem.scale = SIMD3<Float>(thickness * 0.8, stemHeight, thickness * 0.8)
        guideCap.position = SIMD3<Float>(0, plateHeight * 0.85, 0)
        guideCap.scale = SIMD3<Float>(capWidth, capHeight, capDepth)

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

    private func createGuideStem() -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(repeating: 1), cornerRadius: 0.24),
            materials: [stemMaterial()]
        )
    }

    private func createGuideCap() -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(repeating: 1), cornerRadius: 0.45),
            materials: [accentMaterial()]
        )
    }

    private func accentMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.94, green: 0.84, blue: 0.66, alpha: 0.94))
        return material
    }

    private func plateMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.95, green: 0.86, blue: 0.72, alpha: 0.10))
        material.blending = .transparent(opacity: 0.10)
        return material
    }

    private func stemMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.95, green: 0.86, blue: 0.72, alpha: 0.36))
        material.blending = .transparent(opacity: 0.36)
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
