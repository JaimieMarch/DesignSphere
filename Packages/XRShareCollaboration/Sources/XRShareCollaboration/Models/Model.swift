#if SWIFT_PACKAGE
//
// Model.swift
// XR Share
//
// Core model class for loading, managing and synchronizing 3D models
//

import RealityKit
import SwiftUI
import Foundation
import Combine
import ARKit
import simd


/// Represents a 3D anatomical model with loading and placement capabilities
@MainActor
final class Model: ObservableObject, Identifiable {
    
    // Track the loading state for the model entity
    enum LoadingState: Equatable {
        case notStarted, loading, loaded, failed(Error)
        
        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted), (.loading, .loading), (.loaded, .loaded):
                return true
            case (.failed(_), .failed(_)):
                return true
            default:
                return false
            }
        }
    }
    
    let modelType: ModelType
    @Published var modelEntity: ModelEntity?
    @Published var loadingState: LoadingState = .notStarted
    
    // Properties for scene placement
    @Published var position: SIMD3<Float> = SIMD3<Float>(repeating: 0)
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    
   // @Published var controlPanelState = ControlPanelState()
    
    // Reference to ARViewModel for synchronization
    weak var arViewModel: ARViewModel?
    
    var cancellables = Set<AnyCancellable>()
    
    // Unique identifier for each model instance
    let id = UUID()
    
    // Use ModelType for type identification
    var typeId: ModelType { modelType }
    var entity: Entity?
    
    
// MARK: - Initialization
    
    /// Creates a model wrapper instance for a given ModelType
    init(modelType: ModelType, arViewModel: ARViewModel? = nil) {
        self.modelType = modelType
        self.arViewModel = arViewModel
    }
    
    /// Ceate a Model and asynchronously loads its ModelEntity.
    static func load(modelType: ModelType, arViewModel: ARViewModel? = nil) async -> Model {
        let model = Model(modelType: modelType, arViewModel: arViewModel)
        await model.loadModelEntity()
        return model
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    
    
    
// MARK: - Loading
    
    /// Loads the RealityKit ModelEntity for this model (via cache or bundle), applies normalization and interaction components
    @MainActor
    func loadModelEntity() async {
        
        // Skip if we're already loaded or loading
        guard case .notStarted = loadingState else { return }
        
        loadingState = .loading
        
        // Try to get from cache first for instant loading
        if let cachedEntity = await ModelCache.shared.getCachedEntity(for: modelType) {
            self.modelEntity = cachedEntity
            print("Model \(modelType.rawValue) loaded from cache (instant)")
            
        } else {
            var loadError: Error?

            if let modelURL = Bundle.xrShareLocateUSDZ(named: modelType.rawValue) {
                do {
                    self.modelEntity = try await ModelEntity(contentsOf: modelURL)
                } catch {
                    loadError = error
                    print("Failed to load model \(modelType.rawValue) from URL: \(error)")
        }
            }

            if self.modelEntity == nil {
                let filename = "\(modelType.rawValue).usdz"
                for bundle in Bundle.xrShareResourceBundles {
                    do {
                        self.modelEntity = try await ModelEntity(named: filename, in: bundle)
                        break
                    } catch {
                        loadError = error
                        continue
                    }
    }
            }

            if self.modelEntity == nil {
                let error = loadError ?? NSError(
                    domain: "XRShareCollaboration.Model",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Model \(modelType.rawValue) not found"]
                )
                loadingState = .failed(error)
                return
                    }
                }
        
        applyInteractivityRecursively()
        
        // Apply the correct rotation and sizing based on model type
        if let entity = self.modelEntity {
            
            // Name the entity meaningfully for better identification
            entity.name = "Model_\(modelType.rawValue)"
            
            print("Model \(modelType.rawValue) loaded successfully")
            
            
            // Normalize model size based on bounds after roatation
            normalizeModelSize(entity: entity)
            
            
            // Generate collision shapes after size normalization
            entity.generateCollisionShapes(recursive: true)
            
            // Add input target component for gesture interaction
            entity.components.set(InputTargetComponent())
            
            
            // Add hover effect to show interactivity
            entity.components.set(HoverEffectComponent())
            
            // Add grounding shadow for better awareness
            entity.components.set(GroundingShadowComponent(castsShadow: true))
            
            
            // Add components for synchronization
            entity.components[ModelTypeComponent.self] = ModelTypeComponent(type: modelType)
            entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)
            
            // Add collision component for interaction
            if entity.collision == nil {
                let normalizedBounds = entity.visualBounds(relativeTo: nil).extents
                entity.collision = CollisionComponent(
                    shapes: [.generateBox(size: normalizedBounds)],
                    isStatic: false,
                    filter: .default
                )
            }
            
            // Add InstanceID component
            if entity.components[InstanceIDComponent.self] == nil {
                entity.components.set(InstanceIDComponent())
    }
}
        
        // Set as laoded
        self.loadingState = .loaded
    }
    
    
    /// Applies interaction components recursively to the model's entity hierarchy
    func applyInteractivityRecursively() {
        guard let entity = modelEntity else { return }
        Model.applyComponents(to: entity)
    }
    
    
    /// Normalize  the model size so that it fits within a target bounding box
    private func normalizeModelSize(entity: ModelEntity) {
        let targetSize: Float = 0.25 // same initial size of 25 cm

        if let result = Self.calculateNormalization(for: entity, targetSize: targetSize) {
            entity.scale = SIMD3<Float>(repeating: result.scale)
            Self.updatePlacementMetadata(for: entity, modelType: modelType)
            
            print("Model \(modelType.rawValue) normalized using intrinsic bounds: intrinsic max \(result.intrinsicMaxDimension)m,  target \(targetSize)m (scale: \(result.scale))")
            return
        }

        print("Model \(modelType.rawValue), intrinsic normalization failed, falling back to render bounds")

        
        let fallbackBounds = entity.visualBounds(relativeTo: entity)
        let fallbackExtents = fallbackBounds.extents
        let fallbackMaxDimension = max(fallbackExtents.x, fallbackExtents.y, fallbackExtents.z)
        

        guard fallbackMaxDimension > 0 else {
            
            print("Model \(modelType.rawValue), render bounds invalid, applying default scale")
            entity.scale = SIMD3<Float>(repeating: targetSize)
            Self.updatePlacementMetadata(for: entity, modelType: modelType)
            print("Applied default fallback scale: \(targetSize)")
            return
        }

        
        let scaleFactor = targetSize / fallbackMaxDimension
        entity.scale = SIMD3<Float>(repeating: scaleFactor)
        Self.updatePlacementMetadata(for: entity, modelType: modelType)
        print("Model \(modelType.rawValue) normalized via fallback: original max dimension \(fallbackMaxDimension)m,  target \(targetSize)m (scale: \(scaleFactor))")
    }
    
    
    /// Placement related metatdata so that the entity is consistent across users
    static func updatePlacementMetadata(for entity: ModelEntity, modelType: ModelType) {
        let adjustedBounds = entity.visualBounds(relativeTo: nil)
        let extents = adjustedBounds.extents

        guard extents.x.isFinite, extents.y.isFinite, extents.z.isFinite,
              
                
              extents.x > 0, extents.y > 0, extents.z > 0 else {
            entity.components[ModelBoundsComponent.self] = nil
            print("Model \(modelType.rawValue) bounds metadata is unavailable (extents=\(extents))")
            return
        }
        
        let center = adjustedBounds.center
        let bottomY = center.y - (extents.y * 0.5)
        let placementOffset = SIMD3<Float>(center.x, bottomY, center.z)

        entity.components[ModelBoundsComponent.self] = ModelBoundsComponent(
            center: center,
            extents: extents,
            placementOffset: placementOffset
        )

        print("Model \(modelType.rawValue) metadata updated: center= \(center), extents=\(extents), placementOffset=  \(placementOffset)")
    }

    
    struct NormalizationResult {
        let scale: Float
        let intrinsicMaxDimension: Float
    }

    
    /// Calculate the normalization
    static func calculateNormalization(for entity: ModelEntity, targetSize: Float) -> NormalizationResult? {
        guard targetSize > 0 else { return nil }

        guard let intrinsicBounds = intrinsicBounds(for: entity) else {
            return nil
        }

        let extents = intrinsicBounds.extents
        let intrinsicMax = max(extents.x, extents.y, extents.z)

        guard intrinsicMax.isFinite, intrinsicMax > 0 else { return nil }

        let scale = targetSize / intrinsicMax
        guard scale.isFinite, scale > 0 else { return nil }

        return NormalizationResult(scale: scale, intrinsicMaxDimension: intrinsicMax)
    }
    
    
    

    private static func intrinsicBounds(for root: Entity) -> (center: SIMD3<Float>, extents: SIMD3<Float>)? {
        var minPoint = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        func traverse(_ entity: Entity, parentTransform: simd_float4x4, ignoreScale: Bool) {
            var localTransform = entity.transform.matrix

            if ignoreScale {
                let transform = entity.transform
                let rotationMatrix = simd_float4x4(transform.rotation)
                let translationMatrix = simd_float4x4(translation: transform.translation)
                localTransform = translationMatrix * rotationMatrix
            }

            
            let worldTransform = parentTransform * localTransform

            if let modelComponent = entity.components[ModelComponent.self] {
                accumulateBounds(from: modelComponent, transform: worldTransform, minPoint: &minPoint, maxPoint: &maxPoint)
            }

            for child in entity.children {
                traverse(child, parentTransform: worldTransform, ignoreScale: false)
            }
        }

        traverse(root, parentTransform: matrix_identity_float4x4, ignoreScale: true)

        guard minPoint.x < Float.greatestFiniteMagnitude else { return nil }

        let center = (maxPoint + minPoint) * 0.5
        let extents = maxPoint - minPoint
        return (center, extents)
    }
    
    

    private static func accumulateBounds(from modelComponent: ModelComponent, transform: simd_float4x4, minPoint: inout SIMD3<Float>, maxPoint: inout SIMD3<Float>) {
        let bounds = modelComponent.mesh.bounds
        let center = bounds.center
        let halfExtents = bounds.extents * 0.5

        for corner in boundingBoxCorners(center: center, halfExtents: halfExtents) {
            let worldPosition = transform * SIMD4<Float>(corner, 1)
            let point = worldPosition.xyz
            minPoint = SIMD3<Float>(Swift.min(minPoint.x, point.x), Swift.min(minPoint.y, point.y), Swift.min(minPoint.z, point.z))
            maxPoint = SIMD3<Float>(Swift.max(maxPoint.x, point.x), Swift.max(maxPoint.y, point.y), Swift.max(maxPoint.z, point.z))
    }
    }
    
    

    private static func boundingBoxCorners(center: SIMD3<Float>, halfExtents: SIMD3<Float>) -> [SIMD3<Float>] {
        let offsets = [
            SIMD3<Float>(-halfExtents.x, -halfExtents.y, -halfExtents.z),
            SIMD3<Float>(halfExtents.x, -halfExtents.y, -halfExtents.z),
            SIMD3<Float>(-halfExtents.x, halfExtents.y, -halfExtents.z),
            SIMD3<Float>(halfExtents.x, halfExtents.y, -halfExtents.z),
            SIMD3<Float>(-halfExtents.x, -halfExtents.y, halfExtents.z),
            SIMD3<Float>(halfExtents.x, -halfExtents.y, halfExtents.z),
            SIMD3<Float>(-halfExtents.x, halfExtents.y, halfExtents.z),
            SIMD3<Float>(halfExtents.x, halfExtents.y, halfExtents.z)
        ]

        return offsets.map { center + $0 }
    }
    private static func applyComponents(to entity: Entity) {
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(HoverEffectComponent())

        if let modelEntity = entity as? ModelEntity {
            modelEntity.generateCollisionShapes(recursive: false)
        }

        for child in entity.children {
            applyComponents(to: child)
            }
    }
    
    
// MARK: - Status helpers
    
    /// True while the model is in the loading state.
    func isLoading() -> Bool {
        if case .loading = loadingState { return true }
        return false
    }
    
    /// True when the model has finished loading successfully.
    func isLoaded() -> Bool {
        if case .loaded = loadingState { return true }
        return false
    }
    
    
    
    /// True if loading failed.
    func didFail() -> Bool {
        if case .failed(_) = loadingState { return true }
        return false
    }
    
    /// Returns a human-readable error message when loading failed.
    func errorMessage() -> String? {
        if case .failed(let error) = loadingState {
            return error.localizedDescription
        }
        return nil
    }
    
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

private extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }
}

#endif
