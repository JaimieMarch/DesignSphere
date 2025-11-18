//
//  RotationComponent.swift
//  XR Share
//
//  Component for continuous rotation animation

import RealityKit
import SwiftUI

/// Component that enables continuous rotation for any entity
struct RotationComponent: Component {
    var isEnabled: Bool = true
    var speed: Float = 1.0 // Rotations per second
    var axis: SIMD3<Float> = [0, 1, 0] // Default Y-axis rotation
}

/// System that handles rotation animation
@available(visionOS 2.0, *)
class RotationSystem: System {
    static let query = EntityQuery(where: .has(RotationComponent.self))
    
    required init(scene: RealityKit.Scene) {
        // Required initializer for Reality Kit
        }
    
    func update(context: SceneUpdateContext) {
        for entity in context.scene.performQuery(Self.query) {
            
            guard let rotation = entity.components[RotationComponent.self],
                  rotation.isEnabled else { continue }
            
            let angle = Float(context.deltaTime) * rotation.speed * .pi * 2
            entity.transform.rotation *= simd_quatf(angle: angle, axis: rotation.axis)
                }
            }
}

@available(visionOS 2.0, *)
/// Register the system when the app starts
public func registerRotationSystem() {
    RotationSystem.registerSystem()
}
