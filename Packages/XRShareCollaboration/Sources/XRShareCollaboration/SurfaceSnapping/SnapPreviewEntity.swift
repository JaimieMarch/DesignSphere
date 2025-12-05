//
// SnapPreviewEntity.swift
// XRShareCollaboration
//
// Visual preview feedback for surface snapping
//

import Foundation
import RealityKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public class SnapPreviewEntity {
    private var previewEntity: ModelEntity?
    private var surfaceOutlineEntity: ModelEntity?

    public init() {}

    /// Create and configure the snap preview
    public func createPreview(parent: Entity) {
        // Create circular preview indicator
        let mesh = MeshResource.generatePlane(width: 0.5, depth: 0.5, cornerRadius: 0.25)
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.4))

        let preview = ModelEntity(mesh: mesh, materials: [material])
        preview.name = "SnapPreview"
        preview.isEnabled = false

        parent.addChild(preview)
        self.previewEntity = preview

        // Create surface outline (for showing table/surface bounds)
        createSurfaceOutline(parent: parent)
    }

    /// Create surface bounds outline
    private func createSurfaceOutline(parent: Entity) {
        let mesh = MeshResource.generateBox(width: 1, height: 0.01, depth: 1)
        var material = UnlitMaterial()
        material.color = .init(tint: .cyan.withAlphaComponent(0.2))

        let outline = ModelEntity(mesh: mesh, materials: [material])
        outline.name = "SurfaceOutline"
        outline.isEnabled = false

        parent.addChild(outline)
        self.surfaceOutlineEntity = outline
    }

    /// Show snap preview at position
    public func showPreview(at position: SIMD3<Float>, color: UIColor = .green) {
        guard let preview = previewEntity else { return }

        preview.position = position
        preview.isEnabled = true

        // Update color
        if var material = preview.model?.materials.first as? UnlitMaterial {
            material.color = .init(tint: color.withAlphaComponent(0.4))
            preview.model?.materials = [material]
        }
    }

    /// Hide snap preview
    public func hidePreview() {
        previewEntity?.isEnabled = false
        surfaceOutlineEntity?.isEnabled = false
    }

    /// Show surface bounds outline
    public func showSurfaceBounds(at center: SIMD3<Float>, extent: SIMD3<Float>) {
        guard let outline = surfaceOutlineEntity else { return }

        outline.position = center
        outline.scale = extent
        outline.isEnabled = true
    }

    /// Hide surface bounds outline
    public func hideSurfaceBounds() {
        surfaceOutlineEntity?.isEnabled = false
    }

    /// Update preview color (e.g., green for valid, red for invalid)
    public func updatePreviewColor(_ color: UIColor) {
        guard let preview = previewEntity,
              var material = preview.model?.materials.first as? UnlitMaterial else {
            return
        }

        material.color = .init(tint: color.withAlphaComponent(0.4))
        preview.model?.materials = [material]
    }

    /// Animate preview (pulsing effect)
    public func animatePreview() {
        guard let preview = previewEntity else { return }

        // Simple scale animation
        var transform = preview.transform
        transform.scale = SIMD3<Float>(repeating: 1.1)

        preview.move(
            to: transform,
            relativeTo: preview.parent,
            duration: 0.3,
            timingFunction: .easeInOut
        )

        // Scale back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var resetTransform = preview.transform
            resetTransform.scale = SIMD3<Float>(repeating: 1.0)
            preview.move(
                to: resetTransform,
                relativeTo: preview.parent,
                duration: 0.3,
                timingFunction: .easeInOut
            )
        }
    }
}
