#if os(visionOS)
import Foundation
import RealityKit
import UIKit

@available(visionOS 26.0, *)
@MainActor
enum EditAffordanceFactory {
    private static let rootWidth: Float = 0.18
    private static let rootHeight: Float = 0.074
    private static let rootDepth: Float = 0.014

    static func syncEditAffordances(for models: [Model], relativeTo sharedAnchor: AnchorEntity) {
        let liveInstanceIDs = Set(models.map(\.id))

        for child in sharedAnchor.children {
            guard let affordance = child.components[EditAffordanceComponent.self],
                  liveInstanceIDs.contains(affordance.instanceID) == false else { continue }
            child.removeFromParent()
        }

        for model in models {
            guard let modelEntity = model.modelEntity else { continue }
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
        let yOffset = min(max(max(size.x, size.y, size.z) * 0.24, 0.12), 0.28)

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
        material.color = .init(tint: UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 0.92))
        material.blending = .transparent(opacity: 0.92)
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
        material.color = .init(tint: UIColor.white)

        let title = ModelEntity(mesh: textMesh, materials: [material])
        title.position = SIMD3<Float>(-0.04, -0.012, 0.008)
        title.scale = SIMD3<Float>(repeating: 0.016)

        let icon = ModelEntity(
            mesh: .generateBox(size: [0.014, 0.014, 0.006], cornerRadius: 0.003),
            materials: [material]
        )
        icon.position = SIMD3<Float>(0.052, 0, 0.004)
        title.addChild(icon)
        return title
    }
}
#endif
