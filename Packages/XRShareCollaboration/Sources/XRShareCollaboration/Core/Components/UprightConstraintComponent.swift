//
//  UprightConstraintComponent.swift
//  XR Share
//
//  Keeps manipulated entities aligned to a fixed up-axis in real time

import RealityKit

#if os(visionOS)
@available(visionOS 26.0, *)
struct UprightConstraintComponent: Component {
    var upAxis: SIMD3<Float> = simd_normalize(SIMD3<Float>(0, 1, 0))
    var lastForward: SIMD3<Float>? = nil
}

@available(visionOS 26.0, *)
final class UprightConstraintSystem: System {
    static let query = EntityQuery(where: .has(UprightConstraintComponent.self))
    
    required init(scene: RealityKit.Scene) { }
    
    func update(context: SceneUpdateContext) {
        for entity in context.scene.performQuery(Self.query) {
            guard var component = entity.components[UprightConstraintComponent.self] else { continue }
            let up = component.upAxis
            let parent = entity.parent
            let transform = entity.transformMatrix(relativeTo: parent)
            
            var forward = horizontalForwardVector(from: transform, up: up)
            if forward == nil {
                forward = component.lastForward
            }
            guard let validForward = forward else { continue }
            
            applyOrientation(for: entity, forward: validForward, up: up, relativeTo: parent)
            component.lastForward = simd_normalize(validForward)
            entity.components.set(component)
        }
    }
    
    private func horizontalForwardVector(from transform: float4x4, up: SIMD3<Float>) -> SIMD3<Float>? {
        var forward = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        forward -= simd_dot(forward, up) * up
        let magnitude = simd_length_squared(forward)
        guard magnitude >= 1e-6 else { return nil }
        return simd_normalize(forward)
    }
    
    private func applyOrientation(for entity: Entity, forward: SIMD3<Float>, up: SIMD3<Float>, relativeTo parent: Entity?) {
        let normalizedUp = simd_normalize(up)
        var right = simd_cross(normalizedUp, forward)
        if simd_length_squared(right) < 1e-6 {
            right = SIMD3<Float>(1, 0, 0)
        }
        right = simd_normalize(right)
        let adjustedForward = simd_normalize(simd_cross(right, normalizedUp))
        
        let rotationMatrix = float3x3(columns: (
            SIMD3<Float>(right.x, right.y, right.z),
            SIMD3<Float>(normalizedUp.x, normalizedUp.y, normalizedUp.z),
            SIMD3<Float>(adjustedForward.x, adjustedForward.y, adjustedForward.z)
        ))
        let constrainedOrientation = simd_quaternion(rotationMatrix)
        entity.setOrientation(constrainedOrientation, relativeTo: parent)
    }
}

@available(visionOS 26.0, *)
func registerUprightConstraintSystem() {
    UprightConstraintSystem.registerSystem()
}
#endif
