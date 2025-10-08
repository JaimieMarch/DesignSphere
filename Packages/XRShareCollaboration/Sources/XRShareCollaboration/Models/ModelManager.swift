#if SWIFT_PACKAGE
//
// ModelManager.Swift
// XR Share
//
// Manages placed models, gestures and related logic
//



import SwiftUI
import RealityKit


@MainActor
final class ModelManager: ObservableObject {
    @Published var placedModels: [Model] = []
    @Published var modelDict: [Entity: Model] = [:]
    @Published var modelTypes: [ModelType] = []
    
    @Published var selectedModelID: ModelType? = nil
    @Published var selectedModelInstanceID: UUID? = nil

    private var resetNotificationObserver: NSObjectProtocol?

    init() {
        loadModelTypes()
        setupNotifications()
        
    }
    
    private func setupNotifications() {
        resetNotificationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("resetModelManager"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reset()
            }
        }
    }
    
    deinit {
        if let observer = resetNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
    }
    
// MARK: - Collision-based Positioning
    
    private func positionModelWithCollisionAvoidance(entity: Entity, anchor: Entity) {
        
        // Wait a bit for bounds to be properly calculated
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            await MainActor.run {
                self.performCollisionCheck(entity: entity, anchor: anchor)
            }
        }
    }

    
    private func resolvedInitialPlacement(anchor: AnchorEntity, arViewModel: ARViewModel?) async -> SIMD3<Float> {
        if let pending = arViewModel?.pendingPlacementPosition {
            let converted = anchor.convert(position: pending, from: nil)
            let minimumVisionHeight: Float = 1.2
            return SIMD3<Float>(converted.x, max(converted.y, minimumVisionHeight), converted.z)
        }

        if let dynamicPlacement = await preferredVisionPlacement(relativeTo: anchor) {
            return dynamicPlacement
        }
        let minimumVisionHeight: Float = 1.2
        return SIMD3<Float>(0, minimumVisionHeight + 0.25, -1.35)

    }

    #if os(visionOS)
    func preferredVisionPlacement(relativeTo anchor: AnchorEntity) async -> SIMD3<Float>? {
        let minimumVisionHeight: Float = 1.2
        let headAnchor = AnchorEntity(.head)
        headAnchor.anchoring.trackingMode = .once
        anchor.addChild(headAnchor)

        var attempts = 0
        while attempts < 20 && !headAnchor.isAnchored {
            try? await Task.sleep(nanoseconds: 25_000_000)
            attempts += 1
        }

        guard headAnchor.isAnchored else {
            headAnchor.removeFromParent()
            return nil
        }

        let offset = SIMD3<Float>(0, -0.1, -1.2)
        let placement = headAnchor.convert(position: offset, to: anchor)
        headAnchor.removeFromParent()
        return SIMD3<Float>(placement.x, max(placement.y, minimumVisionHeight), placement.z)
    }
    #endif
    
    

    private func placementOffset(for entity: ModelEntity) -> SIMD3<Float> {
        if let component = entity.components[ModelBoundsComponent.self] {
            return component.placementOffset
        }

        let fallbackBounds = entity.visualBounds(relativeTo: nil)
        let center = fallbackBounds.center
        let extents = fallbackBounds.extents
        let bottomY = center.y - (extents.y * 0.5)
        return SIMD3<Float>(center.x, bottomY, center.z)
    }

    
    private func performCollisionCheck(entity: Entity, anchor: Entity) {
        let minSpacing: Float = 0.1 // Minimum 10cm between model edges
        
        // Get the bounds of the new entity
        let newBounds = entity.visualBounds(relativeTo: anchor)
        let newExtents = newBounds.extents
        let newCenter = newBounds.center
        
        
        // Use the full extents for more accurate collision detection
        let newHalfWidth = newExtents.x * 0.5
        let newHalfDepth = newExtents.z * 0.5
        
        // If this is the first model or bounds are invalid, just place at center
        if placedModels.count <= 1 || newExtents.x <= 0 || newExtents.z <= 0 {
            print("First model or invalid bounds, skipping collision check")
            return
        }
        
        
        print("New model bounds: width=\(newExtents.x), depth=\(newExtents.z)")
        
        // Check all existing models for collisions
        var collidingModels: [(entity: Entity, model: Model, overlap: Float)] = []
        
        for model in placedModels {
            guard let existingEntity = model.modelEntity,
                  existingEntity !== entity else { continue }
            
            // Get bounds of existing model
            let existingBounds = existingEntity.visualBounds(relativeTo: anchor)
            let existingExtents = existingBounds.extents
            let existingCenter = existingBounds.center
            
            if existingExtents.x <= 0 || existingExtents.z <= 0 {
                print("Skipping model with invalid bounds")
                continue
            }
            
            
            // Calculate if bounding boxes overlap on the  X axis
            let newLeft = newCenter.x - newHalfWidth
            let newRight = newCenter.x + newHalfWidth
            let existingHalfWidth = existingExtents.x * 0.5
            let existingLeft = existingCenter.x - existingHalfWidth
            let existingRight = existingCenter.x + existingHalfWidth
            
            // Check for X-axis overlap with spacing
            let xOverlap = min(newRight, existingRight) - max(newLeft, existingLeft) + minSpacing
            
            if xOverlap > 0 {
                // Also check Z-axis to ensure they're on same depth plane
                let existingHalfDepth = existingExtents.z * 0.5
                let zDistance = abs(existingCenter.z - newCenter.z)
                let zThreshold = (newHalfDepth + existingHalfDepth) + minSpacing
                
                if zDistance < zThreshold {
                    collidingModels.append((entity: existingEntity, model: model, overlap: xOverlap))
                    print("Collision detected: overlap=\(xOverlap)m")
                }
                    }
        }
        
        
        
        // If there are collisions reposition
        if !collidingModels.isEmpty {
            print("Found \(collidingModels.count) colliding models, repositioning...")
            
            // Sort by overlap amount
            let sortedCollisions = collidingModels.sorted { $0.overlap > $1.overlap }
            
            // Push colliding models away from center
            for (collidingEntity, _, overlap) in sortedCollisions {
                
                
                // Determine push direction based on current position
                let collidingBounds = collidingEntity.visualBounds(relativeTo: anchor)
                let currentCenterX = collidingBounds.center.x
                let pushDirection: Float
                
                if abs(currentCenterX) < 0.01 {
                    // If at center, alternate push direction based on model count
                    let modelIndex = placedModels.firstIndex { $0.modelEntity === collidingEntity } ?? 0
                    pushDirection = modelIndex % 2 == 0 ? -1.0 : 1.0
                } else {
                    // Push away from center
                    pushDirection = currentCenterX >= 0 ? 1.0 : -1.0
                }
                
                // Push by the overlap amount plus a small buffer
                let pushDistance = overlap + 0.05
                
                // Calculate new position
                var newPosition = collidingEntity.position
                newPosition.x += pushDirection * pushDistance
                    
                
                
                // Apply the movement
                collidingEntity.position = newPosition
                
                let newCenterX = currentCenterX + pushDirection * pushDistance
                print("Moved existing model center from x=\(currentCenterX) to x=\(newCenterX) (push distance: \(pushDistance))" )
            }
            
            
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run {
                    self.cascadeRepositioning(excluding: entity, anchor: anchor, depth: 0)
                }
        }
        }
    }
    
    
    private func cascadeRepositioning(excluding newEntity: Entity, anchor: Entity, depth: Int = 0) {
        
        guard depth < 5 else {
            print("Max repositioning depth reached")
            return
        }
        
        let minSpacing: Float = 0.1
        var repositioned = false
        
        // Check all pairs of existing models for collisions
        for (index, model1) in placedModels.enumerated() {
            guard let entity1 = model1.modelEntity,
                  entity1 !== newEntity else { continue }

            for model2 in placedModels[(index + 1)...] {
                guard let entity2 = model2.modelEntity,
                      entity2 !== newEntity else { continue }

                
                let bounds1 = entity1.visualBounds(relativeTo: anchor)
                let extents1 = bounds1.extents
                guard extents1.x > 0 && extents1.z > 0 else { continue }
                let center1 = bounds1.center

                
                let bounds2 = entity2.visualBounds(relativeTo: anchor)
                let extents2 = bounds2.extents
                guard extents2.x > 0 && extents2.z > 0 else { continue }
                let center2 = bounds2.center

                
                // Calculate bounding box overlap
                let halfWidth1 = extents1.x * 0.5
                let halfWidth2 = extents2.x * 0.5
                let left1 = center1.x - halfWidth1
                let right1 = center1.x + halfWidth1
                let left2 = center2.x - halfWidth2
                let right2 = center2.x + halfWidth2

                let xOverlap = min(right1, right2) - max(left1, left2) + minSpacing


                
                if xOverlap > 0 {
                    // Check Z-axis proximity
                    let halfDepth1 = extents1.z * 0.5
                    let halfDepth2 = extents2.z * 0.5
                    let zDistance = abs(center2.z - center1.z)
                    let zThreshold = (halfDepth1 + halfDepth2) + minSpacing

                    
                    if zDistance < zThreshold {
                        // Push the rightmost model further right
                        let pushDistance = xOverlap + 0.05
                        if center2.x > center1.x {
                            entity2.position.x += pushDistance
                        } else {
                            entity1.position.x += pushDistance
                        }
                        repositioned = true
                        print("Cascade: Pushed models apart by \(pushDistance)m")
                    }
                }
            }
        }
        
        // If we repositioned anything, check again with increased depth
        if repositioned {
            cascadeRepositioning(excluding: newEntity, anchor: anchor, depth: depth + 1)
        }
    }
    
    /// Returns the currently selected model instance
    func getSelectedModel() -> Model? {
        guard let instanceID = selectedModelInstanceID else { return nil }
        return placedModels.first { $0.id == instanceID }
    }
    

    
    
// MARK: - Loading a ModelEntity
    
    func loadModel(for modelType: ModelType, arViewModel: ARViewModel?) {
        
        
        Task { @MainActor in
            print("Attempting to load model: \(modelType.rawValue).usdz")
            let model = await Model.load(modelType: modelType, arViewModel: arViewModel)

            // Use the entity that was already loaded inside Model.load.
            guard let entity = model.modelEntity else {
                print("Error: Model entity failed to load for \(modelType.rawValue)")
                return
            
            }
            configureInteractivity(for: entity, arViewModel: arViewModel)

            print( "Loaded entity hierarchy for \(modelType.rawValue):")

            // Normalize model size
            normalizeModelSizeForVisionOS(entity, modelType: modelType)

            // Automatically select newly loaded model
            self.selectedModelID = modelType
            self.selectedModelInstanceID = model.id

    
            if entity.components[InstanceIDComponent.self] == nil {
                entity.components.set(InstanceIDComponent())
            }
            guard let idComp = entity.components[InstanceIDComponent.self] else {
                print("Error: Missing InstanceIDComponent on entity during model loading.")
                return
            }
            let instanceID = idComp.id

            
            
            if let anchor = arViewModel?.sharedAnchorEntity {
                let initialPosition = await resolvedInitialPlacement(anchor: anchor, arViewModel: arViewModel)
                let placementOffset = placementOffset(for: entity)
                let translatedPosition = initialPosition - placementOffset
                anchor.addChild(entity)
                var updatedTransform = entity.transform
                updatedTransform.translation = translatedPosition
                entity.move(to: updatedTransform, relativeTo: anchor, duration: 0)
                arViewModel?.pendingPlacementPosition = nil
                model.position = entity.position(relativeTo: anchor)

                print("Placed \(modelType.rawValue): base=\(initialPosition) pivot=\(translatedPosition), isAnchored=\(anchor.isAnchored), scene? \(entity.scene != nil)")

                
                
                // Check for collisions and reposition if needed
                self.positionModelWithCollisionAvoidance(entity: entity, anchor: anchor)

                print("Parented model \(modelType.rawValue) to sharedAnchorEntity at local position \(entity.position(relativeTo: anchor))")
            } else {
                print("Warning: sharedAnchorEntity not available, model \(modelType.rawValue) not parented")
            }

            self.modelDict[entity] = model
            self.placedModels.append(model)


            print("Loaded model \(modelType.rawValue) (InstanceID: \(instanceID)).")
            print("This is the count of the models in model manager \(self.placedModels.count)")

            if let arViewModel = arViewModel, let coordinator = arViewModel.sharePlayCoordinator {
                let uuid = UUID(uuidString: instanceID) ?? UUID()

                if coordinator.isConnected {

                    Task {
                        await arViewModel.broadcastAddModel(
                            modelType: modelType,
                            instanceID: uuid,
                            entity: entity
                        )
                        print(" Requested addModel via SharePlay: \(modelType.rawValue) (ID: \(uuid))")

                    }
                    
                    
                } else {
                    print("SharePlay not connected, model \(modelType.rawValue) will be synced when session starts")
    }
            } else {
                 print("ARViewModel or SharePlayCoordinator not available for \(modelType.rawValue)")
                }


            print("\(modelType.rawValue) chosen – model loaded and selected")
        }
    }
    
    
    #if os(visionOS)
    
    
    
    /// Normalize model size specifically for visionOS viewing after placement
    private func normalizeModelSizeForVisionOS(_ entity: ModelEntity, modelType: ModelType) {
        let targetSize: Float = 0.25 // Keep visionOS target aligned with iOS normalization

        if let result = Model.calculateNormalization(for: entity, targetSize: targetSize) {
            entity.scale = SIMD3<Float>(repeating: result.scale)
            Model.updatePlacementMetadata(for: entity, modelType: modelType)
            print("VisionOS normalization for \(modelType.rawValue): intrinsic max \(result.intrinsicMaxDimension)m, target \(targetSize)m (scale: \(result.scale))")
            return
                }
        
        print("VisionOS normalization for \(modelType.rawValue) falling back to render bounds")

        let bounds = entity.visualBounds(relativeTo: entity)
        let extents = bounds.extents
        let maxDimension = max(extents.x, extents.y, extents.z)

        guard maxDimension > 0 else {
            let fallbackScale: Float = targetSize
            entity.scale = SIMD3<Float>(repeating: fallbackScale)
            Model.updatePlacementMetadata(for: entity, modelType: modelType)
            print("Applied visionOS default fallback scale: \(fallbackScale)")
            return
    }
        
        let scaleFactor = targetSize / maxDimension
        entity.scale = SIMD3<Float>(repeating: scaleFactor)
        Model.updatePlacementMetadata(for: entity, modelType: modelType)
        print("VisionOS fallback normalization for \(modelType.rawValue): original max \(maxDimension)m, target \(targetSize)m (scale: \(scaleFactor))")
    }
    #endif
    
    
    
    
    func configureInteractivity(for entity: Entity, arViewModel: ARViewModel? = nil) {
        for child in entity.children {
            print("Configuring child: \(child.name)")
            configureInteractivity(for: child, arViewModel: arViewModel)
        }
        
        if let modelEntity = entity as? ModelEntity {
            #if os(visionOS)
       
            if #available(visionOS 26.0, *),
               let viewModel = arViewModel,
               let manipulationManager = viewModel.manipulationManager {
                manipulationManager.configureModelForManipulation(entity: modelEntity)
            } else {
                // Fallback: basic interaction setup
                if modelEntity.components[CollisionComponent.self] == nil {
                    let shape = ShapeResource.generateBox(size: [0.1, 0.1, 0.1])
                    modelEntity.components.set(CollisionComponent(shapes: [shape]))
                }
                modelEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
                modelEntity.components.set(HoverEffectComponent())
            }

            #endif
        }
    }

    

// MARK: - Remove a Single Model
    
    @MainActor func removeModel(_ model: Model, broadcast: Bool = true) {
        guard let entity = model.modelEntity else { return }
        
        
        // Use InstanceIDComponent for removal broadcast if available
        let instanceID: String = entity.components[InstanceIDComponent.self]?.id ?? UUID().uuidString
        let modelTypeName = model.modelType.rawValue // Get name before potential removal
        
        
        // Clean up entity properly
        entity.components.remove(SelectionComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(ModelTypeComponent.self)
        entity.components.remove(LastTransformComponent.self)
    
    
        // Remove from parent after cleanup
        entity.removeFromParent()
        
        // Update collections
        placedModels.removeAll { $0.id == model.id }
        modelDict = modelDict.filter { $0.value.id != model.id }
       
        // If we removed the selected model, clear selection or select another
        if selectedModelInstanceID == model.id {
            selectedModelInstanceID = placedModels.first?.id
            selectedModelID = placedModels.first?.modelType
        }
        if placedModels.isEmpty {
        }
        
        // Broadcast remove model in shareplay sessions
        if broadcast, let arViewModel = model.arViewModel {
            Task {
                if let uuid = UUID(uuidString: instanceID) {
                    await arViewModel.broadcastRemoveModel(instanceID: uuid)
                }
    }
        }
        print("Removed model: \(modelTypeName)")
    }
    
    
    
    @MainActor func reset(broadcast: Bool = false) {
        // Remove all models
        let modelsToRemove = placedModels
        for model in modelsToRemove {
            removeModel(model, broadcast: broadcast)
        }
        
        placedModels.removeAll()
        modelDict.removeAll()
        selectedModelID = nil
        selectedModelInstanceID = nil
  
        print("Reset ModelManager state. Broadcast: \(broadcast)")
    }
    
    
// MARK: - Update the 3D Scene
    
    @MainActor func updatePlacedModels(
        arViewModel: ARViewModel
    ) {

        // Check all models
        for model in placedModels {
            guard let entity = model.modelEntity else { continue }

            // Make sure entity is visible and interactive
            entity.isEnabled = true
            if entity.components[InputTargetComponent.self] == nil {
                 entity.components.set(InputTargetComponent())
            }
            if entity.components[HoverEffectComponent.self] == nil {
                 entity.components.set(HoverEffectComponent())
            }
            if entity.collision == nil {
                 entity.generateCollisionShapes(recursive: true)
            }

            // Track selection state without visual highlight
            if entity.scene != nil {
                 if model.id == selectedModelInstanceID {
                    if entity.components[SelectionComponent.self] == nil {
                        entity.components.set(SelectionComponent())
                        print("Selected \(model.modelType.rawValue)")
                    }
                } else {
                    if entity.components[SelectionComponent.self] != nil {
                        entity.components.remove(SelectionComponent.self)
                        print("Deselected \(model.modelType.rawValue)")
                }
            }
                
                
            } else {
                 if entity.components[SelectionComponent.self] != nil {
                     entity.components.remove(SelectionComponent.self)
                 }
            }
            
}
    }

    
    
    
// MARK: - Selection Handling
    
    @available(visionOS 26.0, *)
    @MainActor func selectModel(entity: Entity) {
        let name = entity.name.isEmpty ? "unnamed entity" : entity.name
        
        
        if let model = self.modelDict[entity] {
            
            self.selectedModelID = model.modelType
            self.selectedModelInstanceID = model.id
            entity.isEnabled = true
            if let parent = entity.parent { parent.isEnabled = true }
            
            
            if let arViewModel = model.arViewModel,
               let instanceIDString = entity.components[InstanceIDComponent.self]?.id,
               let instanceID = UUID(uuidString: instanceIDString) {
                Task {
                    await arViewModel.broadcastModelSelection(instanceID: instanceID)
                    }
            }

            
            print("Select: Selected \(name) (instance: \(model.id))")
        } else {
            print("Selected non-model entity: \(name)")
        }
        }
    
}

#endif
