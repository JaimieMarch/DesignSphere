#if os(visionOS)
import Foundation
import RealityKit
import UIKit

@available(visionOS 26.0, *)
@MainActor
enum EditAffordanceFactory {
    private static let rootWidth: Float = 0.132
    private static let rootHeight: Float = 0.052
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
            mesh: .generatePlane(width: rootWidth, height: rootHeight, cornerRadius: 0.018),
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
        material.color = .init(tint: UIColor(white: 0.98, alpha: 0.94))
        material.blending = .transparent(opacity: 0.94)
        return material
    }

    private static func createTitleEntity() -> ModelEntity {
        let textMesh = MeshResource.generateText(
            "Edit",
            extrusionDepth: 0.0012,
            font: .systemFont(ofSize: 0.034, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            alignment: .center,
            lineBreakMode: .byClipping
        )

        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.17, green: 0.20, blue: 0.24, alpha: 0.98))

        let title = ModelEntity(mesh: textMesh, materials: [material])
        title.name = "EditAffordanceTitle"
        title.position = SIMD3<Float>(-0.034, -0.012, 0.007)
        return title
    }
}
#endif
