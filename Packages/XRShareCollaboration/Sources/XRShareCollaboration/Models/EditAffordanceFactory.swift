#if os(visionOS)
import Foundation
import RealityKit
import UIKit

@available(visionOS 26.0, *)
@MainActor
enum EditAffordanceFactory {
    private static let rootWidth: Float = 0.152
    private static let rootHeight: Float = 0.062
    private static let rootDepth: Float = 0.012

    static func syncEditAffordances(
        for models: [Model],
        relativeTo sharedAnchor: AnchorEntity,
        selectedInstanceID: UUID?,
        expandedInstanceID: UUID?
    ) {
        let liveInstanceIDs = Set(models.map(\.id))

        for child in sharedAnchor.children {
            guard let affordance = child.components[EditAffordanceComponent.self],
                  liveInstanceIDs.contains(affordance.instanceID) == false else { continue }
            child.removeFromParent()
        }

        for model in models {
            guard let modelEntity = model.modelEntity else { continue }
            if model.id != selectedInstanceID {
                existingAffordance(for: model.id, relativeTo: sharedAnchor)?.removeFromParent()
                continue
            }
            if model.id == expandedInstanceID {
                existingAffordance(for: model.id, relativeTo: sharedAnchor)?.removeFromParent()
                continue
            }
            updateAffordance(for: model.id, modelEntity: modelEntity, relativeTo: sharedAnchor)
        }
    }

    private static func updateAffordance(for instanceID: UUID, modelEntity: Entity, relativeTo sharedAnchor: AnchorEntity) {
        let affordance = existingAffordance(for: instanceID, relativeTo: sharedAnchor) ?? createAffordance(for: instanceID)

        if affordance.parent !== sharedAnchor {
            sharedAnchor.addChild(affordance)
        }

        let bounds = modelEntity.visualBounds(relativeTo: sharedAnchor)
        let size = bounds.extents
        let yOffset = min(max(max(size.x, size.y, size.z) * 0.18, 0.10), 0.22)

        affordance.setPosition(
            SIMD3<Float>(bounds.center.x, bounds.max.y + yOffset, bounds.center.z),
            relativeTo: sharedAnchor
        )
        affordance.scale = .one
    }

    private static func existingAffordance(for instanceID: UUID, relativeTo sharedAnchor: AnchorEntity) -> Entity? {
        sharedAnchor.children.first {
            $0.components[EditAffordanceComponent.self]?.instanceID == instanceID
        }
    }

    private static func createAffordance(for instanceID: UUID) -> Entity {
        let background = createBackgroundMaterial()
        let affordance = ModelEntity(
            mesh: .generatePlane(width: rootWidth, height: rootHeight, cornerRadius: 0.022),
            materials: [background]
        )
        affordance.name = affordanceName(for: instanceID)
        affordance.components.set(EditAffordanceComponent(instanceID: instanceID))
        affordance.components.set(InputTargetComponent(allowedInputTypes: .all))
        affordance.components.set(HoverEffectComponent(.spotlight(.default)))
        affordance.components.set(CollisionComponent(shapes: [
            .generateBox(width: rootWidth, height: rootHeight, depth: rootDepth)
        ]))

        if #available(visionOS 2.0, *) {
            var billboard = BillboardComponent()
            billboard.blendFactor = 1.0
            affordance.components.set(billboard)
        }

        let title = createTitleEntity()
        affordance.addChild(title)
        return affordance
    }

    private static func affordanceName(for instanceID: UUID) -> String {
        "EditAffordance_\(instanceID.uuidString)"
    }

    private static func createBackgroundMaterial() -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 0.82))
        material.blending = .transparent(opacity: 0.82)
        return material
    }

    private static func createTitleEntity() -> ModelEntity {
        let textMesh = MeshResource.generateText(
            "Edit",
            extrusionDepth: 0.003,
            font: .systemFont(ofSize: 0.05, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            alignment: .center,
            lineBreakMode: .byClipping
        )

        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(white: 0.98, alpha: 0.98))

        let title = ModelEntity(mesh: textMesh, materials: [material])
        title.position = SIMD3<Float>(-0.032, -0.011, 0.007)
        title.scale = SIMD3<Float>(repeating: 0.0145)

        let icon = ModelEntity(
            mesh: .generateBox(size: [0.010, 0.020, 0.005], cornerRadius: 0.003),
            materials: [material]
        )
        icon.position = SIMD3<Float>(0.044, 0, 0.004)
        title.addChild(icon)

        let detail = ModelEntity(
            mesh: .generateBox(size: [0.0032, 0.012, 0.006], cornerRadius: 0.002),
            materials: [material]
        )
        detail.position = SIMD3<Float>(0.054, 0.002, 0.004)
        title.addChild(detail)
        return title
    }
}
#endif
