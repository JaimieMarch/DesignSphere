//
//  Components.swift
//  XR Share
//
//  RealityKit components used throughout the app
//

import Foundation
import RealityKit
import simd

/// Component to store the model type
struct ModelTypeComponent: Component {
    let type: ModelType
}


/// Component to track last known transform matrix for change detection
struct LastTransformComponent: Component {
    var matrix: simd_float4x4
}

/// Component to mark a model as currently selected
struct SelectionComponent: Component {}

/// Component to store a unique instance ID for networking
struct InstanceIDComponent: Component, Codable {
    let id: String
    
    init(id: String = UUID().uuidString) {
        self.id = id
    }
}

/// Stores normalized bounds data so placement stays consistent across users
struct ModelBoundsComponent: Component {
    var center: SIMD3<Float>
    var extents: SIMD3<Float>
    var placementOffset: SIMD3<Float>
}
