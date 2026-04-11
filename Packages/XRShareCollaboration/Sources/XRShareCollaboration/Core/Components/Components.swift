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

/// Component attached to the floating per-model edit affordance.
public struct EditAffordanceComponent: Component {
    public let instanceID: UUID

    public init(instanceID: UUID) {
        self.instanceID = instanceID
    }
}

/// Component to store a unique instance ID for networking
public struct InstanceIDComponent: Component, Codable {
    public let id: String

    public init(id: String = UUID().uuidString) {
        self.id = id
    }
}

/// Stores normalized bounds data so placement stays consistent across users
struct ModelBoundsComponent: Component {
    var center: SIMD3<Float>
    var extents: SIMD3<Float>
    var placementOffset: SIMD3<Float>
}

/// Stores original unscaled dimensions for accurate editing
public struct OriginalBoundsComponent: Component {
    public var originalSize: SIMD3<Float>

    public init(originalSize: SIMD3<Float>) {
        self.originalSize = originalSize
    }
}

/// Tracks the applied material type for explicit persistence
public struct MaterialTypeComponent: Component {
    public var materialType: String  // "wood", "metal", "fabric", "leather", "custom"

    public init(materialType: String) {
        self.materialType = materialType
    }
}

/// Stores the most recent successful surface snap so future snaps can be stickier.
public struct SnapStateComponent: Component {
    public enum SourceKind: String, Codable, Sendable {
        case plane
        case roomMesh
    }

    public var source: SourceKind
    public var surfaceID: UUID
    public var classification: String?
    public var score: Float

    public init(source: SourceKind, surfaceID: UUID, classification: String?, score: Float) {
        self.source = source
        self.surfaceID = surfaceID
        self.classification = classification
        self.score = score
    }
}
