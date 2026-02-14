import Foundation
import RealityKit
import SwiftUI

#if os(visionOS)
@MainActor
public final class SelectionIndicatorManager: ObservableObject {

    private weak var sharedAnchorEntity: AnchorEntity?
    private var arrowEntity: ModelEntity?
    private weak var trackedEntity: Entity?
    private var currentSelectedEntityID: UUID?
    private var lastTrackedPosition: SIMD3<Float>?
    private let updateThreshold: Float = 0.001 // Only update if moved > 1mm

    public init() {}

    public func setSharedAnchor(_ anchor: AnchorEntity) {
        self.sharedAnchorEntity = anchor
    }

    /// Show selection arrow above the given entity
    public func showSelectionIndicator(for entity: Entity) {
        // Remove existing arrow if any
        hideSelectionIndicator()

        guard let sharedAnchor = sharedAnchorEntity else {
            print("Warning: sharedAnchorEntity not set for selection indicator")
            return
        }

        // Create arrow pointing down at the selected model
        let arrow = createArrowEntity()

        // Position arrow above the entity
        positionArrow(arrow, above: entity, relativeTo: sharedAnchor)

        // Add to scene
        sharedAnchor.addChild(arrow)
        arrowEntity = arrow
        trackedEntity = entity

        // Store initial position for tracking
        lastTrackedPosition = entity.position(relativeTo: sharedAnchor)

        // Store entity ID for tracking
        if let instanceComponent = entity.components[InstanceIDComponent.self],
           let id = UUID(uuidString: instanceComponent.id) {
            currentSelectedEntityID = id
        }
    }

    /// Hide and remove the selection arrow
    public func hideSelectionIndicator() {
        arrowEntity?.removeFromParent()
        arrowEntity = nil
        trackedEntity = nil
        currentSelectedEntityID = nil
        lastTrackedPosition = nil
    }

    /// Update arrow position if the selected entity has moved
    public func updateIndicatorPosition(for entity: Entity? = nil) {
        guard let arrow = arrowEntity,
              let sharedAnchor = sharedAnchorEntity else {
            return
        }

        // Use provided entity or fall back to tracked entity
        let targetEntity = entity ?? trackedEntity
        guard let targetEntity = targetEntity else {
            return
        }

        // Check if entity has moved significantly before updating
        let currentPosition = targetEntity.position(relativeTo: sharedAnchor)

        if let lastPos = lastTrackedPosition {
            let distance = simd_distance(currentPosition, lastPos)
            // Only update if moved more than threshold
            guard distance > updateThreshold else {
                return
            }
        }

        // Update position and store new position
        lastTrackedPosition = currentPosition
        positionArrow(arrow, above: targetEntity, relativeTo: sharedAnchor)
    }

    // MARK: - Private Helpers

    private func createArrowEntity() -> ModelEntity {
        // Create a cone pointing down (arrow shape)
        let coneHeight: Float = 0.15
        let coneRadius: Float = 0.08

        let coneMesh = MeshResource.generateCone(height: coneHeight, radius: coneRadius)

        // Create material with MustardTan color from assets
        var material = UnlitMaterial()
        material.color = .init(tint: .init(red: 0.765, green: 0.580, blue: 0.357, alpha: 1.0)) // MustardTan

        let cone = ModelEntity(mesh: coneMesh, materials: [material])

        // Rotate cone to point downward (cone generates pointing up by default)
        cone.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))

        // Add animation - bobbing up and down
        if let bobAnimation = createBobbingAnimation() {
            cone.playAnimation(bobAnimation.repeat())
        }

        return cone
    }

    private func positionArrow(_ arrow: ModelEntity, above entity: Entity, relativeTo sharedAnchor: AnchorEntity) {
        // Get entity's bounding box to position arrow above it
        let bounds = entity.visualBounds(relativeTo: sharedAnchor)
        let entityTop = bounds.max.y

        // Position arrow slightly above the top of the entity
        let arrowOffset: Float = 0.25 // 25cm above the top
        let arrowY = entityTop + arrowOffset

        // Get entity's center position in X and Z
        let entityPosition = entity.position(relativeTo: sharedAnchor)

        arrow.setPosition(
            SIMD3<Float>(entityPosition.x, arrowY, entityPosition.z),
            relativeTo: sharedAnchor
        )
    }

    private func createBobbingAnimation() -> AnimationResource? {
        // Create gentle up-down bobbing motion
        let bobDistance: Float = 0.05 // 5cm up and down
        let duration: TimeInterval = 1.5

        // Create transform for up position
        var upTransform = Transform()
        upTransform.translation = SIMD3<Float>(0, bobDistance, 0)

        // Create transform for down position (relative to original)
        var downTransform = Transform()
        downTransform.translation = SIMD3<Float>(0, -bobDistance, 0)

        // Create animation from current position -> up -> down -> current
        let animation = FromToByAnimation(
            name: "bob",
            from: downTransform,
            to: upTransform,
            duration: duration,
            timing: .easeInOut,
            isAdditive: true,
            bindTarget: .transform
        )

        do {
            return try AnimationResource.generate(with: animation)
        } catch {
            print("SelectionIndicatorManager: Failed to create bobbing animation - \(error)")
            return nil
        }
    }
}
#endif
