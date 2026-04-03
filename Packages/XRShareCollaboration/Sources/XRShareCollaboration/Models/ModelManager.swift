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
public final class ModelManager: ObservableObject {
    @Published var placedModels: [Model] = []
    /// Maps model instance UUIDs to Model objects for fast lookup
    @Published var modelDict: [UUID: Model] = [:]
    @Published var modelTypes: [ModelType] = []
    
    @Published var selectedModelID: ModelType? = nil
    @Published var selectedModelInstanceID: UUID? = nil

    private var resetNotificationObserver: NSObjectProtocol?

    private let minimumVisionHeight: Float = 1.2

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


    /// The old version of spawning logic
    /// Serves as back up in case ours fails
    private func resolvedInitialPlacement(anchor: AnchorEntity, arViewModel: ARViewModel?) async -> SIMD3<Float> {
#if targetEnvironment(simulator)
        return SIMD3<Float>(0, 1.4, -1.2)
#else
        if let dynamicPlacement = await preferredVisionPlacement(relativeTo: anchor) {
            return dynamicPlacement
        }
        return SIMD3<Float>(0, minimumVisionHeight + 0.25, -1.35)
#endif
    }

    #if os(visionOS)
    func preferredVisionPlacement(relativeTo anchor: AnchorEntity) async -> SIMD3<Float>? {
        let headAnchor = AnchorEntity(.head)
        headAnchor.anchoring.trackingMode = .once
        anchor.addChild(headAnchor)

        // Use a single longer initial wait to let the anchor settle,
        // then check a few times with reasonable intervals instead of busy-waiting
        let checkInterval: UInt64 = 100_000_000 // 100ms between checks
        let maxAttempts = 5 // Maximum 500ms total wait

        for _ in 0..<maxAttempts {
            if headAnchor.isAnchored { break }
            try? await Task.sleep(nanoseconds: checkInterval)
        }

        defer { headAnchor.removeFromParent() }

        guard headAnchor.isAnchored else {
            return nil
        }

        let offset = SIMD3<Float>(0, -0.1, -1.2)
        let placement = headAnchor.convert(position: offset, to: anchor)
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
            #if DEBUG
            print("First model or invalid bounds, skipping collision check")
            #endif
            return
        }
        
        
        #if DEBUG
        print("New model bounds: width=\(newExtents.x), depth=\(newExtents.z)")
        #endif
        
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
                #if DEBUG
                print("Skipping model with invalid bounds")
                #endif
                continue
            }
            
            
            // Calculate if bounding boxes overlap on all three axes (X, Y, Z)
            // X-axis
            let newLeft = newCenter.x - newHalfWidth
            let newRight = newCenter.x + newHalfWidth
            let existingHalfWidth = existingExtents.x * 0.5
            let existingLeft = existingCenter.x - existingHalfWidth
            let existingRight = existingCenter.x + existingHalfWidth
            let xOverlap = min(newRight, existingRight) - max(newLeft, existingLeft) + minSpacing

            // Y-axis (height) - must also overlap vertically for a true collision
            let newHalfHeight = newExtents.y * 0.5
            let newBottom = newCenter.y - newHalfHeight
            let newTop = newCenter.y + newHalfHeight
            let existingHalfHeight = existingExtents.y * 0.5
            let existingBottom = existingCenter.y - existingHalfHeight
            let existingTop = existingCenter.y + existingHalfHeight
            let yOverlap = min(newTop, existingTop) - max(newBottom, existingBottom) + minSpacing

            // Z-axis (depth)
            let existingHalfDepth = existingExtents.z * 0.5
            let newFront = newCenter.z - newHalfDepth
            let newBack = newCenter.z + newHalfDepth
            let existingFront = existingCenter.z - existingHalfDepth
            let existingBack = existingCenter.z + existingHalfDepth
            let zOverlap = min(newBack, existingBack) - max(newFront, existingFront) + minSpacing

            // All three axes must overlap for a true 3D collision
            if xOverlap > 0 && yOverlap > 0 && zOverlap > 0 {
                collidingModels.append((entity: existingEntity, model: model, overlap: xOverlap))
                #if DEBUG
                print("Collision detected: xOverlap=\(xOverlap)m, yOverlap=\(yOverlap)m, zOverlap=\(zOverlap)m")
                #endif
            }
        }
        
        
        
        // If there are collisions reposition
        if !collidingModels.isEmpty {
            #if DEBUG
            print("Found \(collidingModels.count) colliding models, repositioning...")
            #endif
            
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
                #if DEBUG
                print("Moved existing model center from x=\(currentCenterX) to x=\(newCenterX) (push distance: \(pushDistance))" )
                #endif
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
            #if DEBUG
            print("Max repositioning depth reached")
            #endif
            return
        }
        
        let minSpacing: Float = 0.1
        var repositioned = false
        let activeEntities = placedModels.compactMap(\.modelEntity).filter { $0 !== newEntity }
        guard activeEntities.count > 1 else { return }

        // Cache bounds once per entity per pass to avoid repeated visualBounds calls.
        var boundsCache: [ObjectIdentifier: (center: SIMD3<Float>, extents: SIMD3<Float>)] = [:]
        for entity in activeEntities {
            let bounds = entity.visualBounds(relativeTo: anchor)
            let extents = bounds.extents
            guard extents.x > 0 && extents.z > 0 else { continue }
            boundsCache[ObjectIdentifier(entity)] = (bounds.center, extents)
        }
        
        // Check all pairs of existing models for collisions
        for index in 0..<(activeEntities.count - 1) {
            let entity1 = activeEntities[index]
            guard let state1 = boundsCache[ObjectIdentifier(entity1)] else { continue }

            for nextIndex in (index + 1)..<activeEntities.count {
                let entity2 = activeEntities[nextIndex]
                guard let state2 = boundsCache[ObjectIdentifier(entity2)] else { continue }

                let extents1 = state1.extents
                let center1 = state1.center
                let extents2 = state2.extents
                let center2 = state2.center

                
                // Calculate bounding box overlap on all three axes
                // X-axis
                let halfWidth1 = extents1.x * 0.5
                let halfWidth2 = extents2.x * 0.5
                let left1 = center1.x - halfWidth1
                let right1 = center1.x + halfWidth1
                let left2 = center2.x - halfWidth2
                let right2 = center2.x + halfWidth2
                let xOverlap = min(right1, right2) - max(left1, left2) + minSpacing

                // Y-axis (height)
                let halfHeight1 = extents1.y * 0.5
                let halfHeight2 = extents2.y * 0.5
                let bottom1 = center1.y - halfHeight1
                let top1 = center1.y + halfHeight1
                let bottom2 = center2.y - halfHeight2
                let top2 = center2.y + halfHeight2
                let yOverlap = min(top1, top2) - max(bottom1, bottom2) + minSpacing

                // Z-axis (depth)
                let halfDepth1 = extents1.z * 0.5
                let halfDepth2 = extents2.z * 0.5
                let front1 = center1.z - halfDepth1
                let back1 = center1.z + halfDepth1
                let front2 = center2.z - halfDepth2
                let back2 = center2.z + halfDepth2
                let zOverlap = min(back1, back2) - max(front1, front2) + minSpacing

                // All three axes must overlap for a true 3D collision
                if xOverlap > 0 && yOverlap > 0 && zOverlap > 0 {
                    // Push the rightmost model further right
                    let pushDistance = xOverlap + 0.05
                    if center2.x > center1.x {
                        entity2.position.x += pushDistance
                        boundsCache[ObjectIdentifier(entity2)] = (
                            center: SIMD3<Float>(center2.x + pushDistance, center2.y, center2.z),
                            extents: extents2
                        )
                    } else {
                        entity1.position.x += pushDistance
                        boundsCache[ObjectIdentifier(entity1)] = (
                            center: SIMD3<Float>(center1.x + pushDistance, center1.y, center1.z),
                            extents: extents1
                        )
                    }
                    repositioned = true
                    #if DEBUG
                    print("Cascade: Pushed models apart by \(pushDistance)m")
                    #endif
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
            #if DEBUG
            print("Attempting to load model: \(modelType.rawValue).usdz")
            #endif
            let model = await Model.load(modelType: modelType, arViewModel: arViewModel)

            // Use the entity that was already loaded inside Model.load.
            guard let entity = model.modelEntity else {
                #if DEBUG
                print("Error: Model entity failed to load for \(modelType.rawValue)")
                #endif
                return
            
            }
            configureInteractivity(for: entity, arViewModel: arViewModel)

            #if DEBUG
            print( "Loaded entity hierarchy for \(modelType.rawValue):")
            #endif

            // Normalize model size
            normalizeModelSizeForVisionOS(entity, modelType: modelType)

            // Store original unscaled bounds for accurate dimension editing
            let originalBounds = entity.visualBounds(relativeTo: entity)
            let originalSize = originalBounds.max - originalBounds.min
            entity.components.set(OriginalBoundsComponent(originalSize: originalSize))

            // Automatically select newly loaded model
            self.selectedModelID = modelType
            self.selectedModelInstanceID = model.id

            // Ensure entity has an InstanceIDComponent that matches the model's ID
            // This enables lookup from Entity → Model via the UUID-keyed modelDict
            entity.components.set(InstanceIDComponent(id: model.id.uuidString))
            let instanceID = model.id.uuidString

            if let anchor = arViewModel?.sharedAnchorEntity {
                let snappedPlacement: SurfacePlacement? = if let resolver = arViewModel?.preferredPlacementResolver {
                    await resolver(entity, modelType)
                } else {
                    nil
                }

                let translatedPosition: SIMD3<Float>
                let basePosition: SIMD3<Float>
                if let snappedPlacement {
                    translatedPosition = snappedPlacement.localPosition
                    basePosition = anchor.convert(position: snappedPlacement.localPosition, to: nil)
                } else {
                    // Fallback to head-relative placement when no compatible surface is available.
                    let initialPosition = await resolvedInitialPlacement(anchor: anchor, arViewModel: arViewModel)
                    let placementOffset = placementOffset(for: entity)
                    basePosition = initialPosition
                    translatedPosition = initialPosition - placementOffset
                }

                anchor.addChild(entity)
                // Directly assign the local position so it works even before the anchor
                // is part of the live RealityKit scene (move(to:) can no-op in that case).
                entity.setPosition(translatedPosition, relativeTo: anchor)
                model.position = entity.position(relativeTo: anchor)

                #if DEBUG
                print("Placed \(modelType.rawValue) at position: base=\(basePosition) pivot=\(translatedPosition), isAnchored=\(anchor.isAnchored), scene? \(entity.scene != nil)")
                #endif

                // Check for collisions and reposition if needed
                self.positionModelWithCollisionAvoidance(entity: entity, anchor: anchor)

                #if DEBUG
                print("Parented model \(modelType.rawValue) to sharedAnchorEntity at local position \(entity.position(relativeTo: anchor))")
                #endif
            } else {
                #if DEBUG
                print("Warning: sharedAnchorEntity not available, model \(modelType.rawValue) not parented")
                #endif
            }

            self.modelDict[model.id] = model
            self.placedModels.append(model)

            #if DEBUG
            print("Loaded model \(modelType.rawValue) (InstanceID: \(instanceID)).")
            #endif
            #if DEBUG
            print("This is the count of the models in model manager \(self.placedModels.count)")
            #endif

//            if let arViewModel = arViewModel, let coordinator = arViewModel.sharePlayCoordinator {
//                let uuid = UUID(uuidString: instanceID) ?? UUID()
//
//                if coordinator.isConnected {
//
//                    Task {
//                        await arViewModel.broadcastAddModel(
//                            modelType: modelType,
//                            instanceID: uuid,
//                            entity: entity
//                        )
//                        print(" Requested addModel via SharePlay: \(modelType.rawValue) (ID: \(uuid))")
//
//                    }
//                    
//                    
//                } else {
//                    print("SharePlay not connected, model \(modelType.rawValue) will be synced when session starts")
//    }
//            } else {
//                 print("ARViewModel or SharePlayCoordinator not available for \(modelType.rawValue)")
//                }


            #if DEBUG
            print("\(modelType.rawValue) chosen – model loaded and selected")
            #endif
        }
    }
    
    
    #if os(visionOS)
    
    
    
    /// Normalize model size specifically for visionOS viewing after placement
    private func normalizeModelSizeForVisionOS(_ entity: ModelEntity, modelType: ModelType) {
        // Skip normalization for models that we are in control of
        if modelType.preserveRealWorldScale {
            Model.updatePlacementMetadata(for: entity, modelType: modelType)
            #if DEBUG
            print("VisionOS: Model \(modelType.rawValue) preserving real-world scale (no normalization)")
            #endif
            return
        }
        
        // rest of this is unmodified.

        let targetSize: Float = 0.25 // Keep visionOS target aligned with iOS normalization

        if let result = Model.calculateNormalization(for: entity, targetSize: targetSize) {
            entity.scale = SIMD3<Float>(repeating: result.scale)
            Model.updatePlacementMetadata(for: entity, modelType: modelType)
            #if DEBUG
            print("VisionOS normalization for \(modelType.rawValue): intrinsic max \(result.intrinsicMaxDimension)m, target \(targetSize)m (scale: \(result.scale))")
            #endif
            return
                }
        
        #if DEBUG
        print("VisionOS normalization for \(modelType.rawValue) falling back to render bounds")
        #endif

        let bounds = entity.visualBounds(relativeTo: entity)
        let extents = bounds.extents
        let maxDimension = max(extents.x, extents.y, extents.z)

        guard maxDimension > 0 else {
            let fallbackScale: Float = targetSize
            entity.scale = SIMD3<Float>(repeating: fallbackScale)
            Model.updatePlacementMetadata(for: entity, modelType: modelType)
            #if DEBUG
            print("Applied visionOS default fallback scale: \(fallbackScale)")
            #endif
            return
    }
        
        let scaleFactor = targetSize / maxDimension
        entity.scale = SIMD3<Float>(repeating: scaleFactor)
        Model.updatePlacementMetadata(for: entity, modelType: modelType)
        #if DEBUG
        print("VisionOS fallback normalization for \(modelType.rawValue): original max \(maxDimension)m, target \(targetSize)m (scale: \(scaleFactor))")
        #endif
    }
    #endif
    
    
    
    
    internal func configureInteractivity(for entity: Entity, arViewModel: ARViewModel? = nil) {
        for child in entity.children {
            #if DEBUG
            print("Configuring child: \(child.name)")
            #endif
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
        modelDict.removeValue(forKey: model.id)
       
        // If we removed the selected model, clear selection or select another
        if selectedModelInstanceID == model.id {
            selectedModelInstanceID = placedModels.first?.id
            selectedModelID = placedModels.first?.modelType
        }
        if placedModels.isEmpty {
        }
        
        // Broadcast remove model in shareplay sessions
//        if broadcast, let arViewModel = model.arViewModel {
//            Task {
//                if let uuid = UUID(uuidString: instanceID) {
//                    await arViewModel.broadcastRemoveModel(instanceID: uuid)
//                }
//    }
//        }
        #if DEBUG
        print("Removed model: \(modelTypeName)")
        #endif
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
  
        #if DEBUG
        print("Reset ModelManager state. Broadcast: \(broadcast)")
        #endif
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
                        #if DEBUG
                        print("Selected \(model.modelType.rawValue)")
                        #endif
                    }
                } else {
                    if entity.components[SelectionComponent.self] != nil {
                        entity.components.remove(SelectionComponent.self)
                        #if DEBUG
                        print("Deselected \(model.modelType.rawValue)")
                        #endif
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

        // Look up model by its instance UUID from the entity's InstanceIDComponent
        guard let instanceIDString = entity.components[InstanceIDComponent.self]?.id,
              let instanceID = UUID(uuidString: instanceIDString),
              let model = self.modelDict[instanceID] else {
            #if DEBUG
            print("Selected non-model entity: \(name)")
            #endif
            return
        }

        self.selectedModelID = model.modelType
        self.selectedModelInstanceID = model.id
        entity.isEnabled = true
        if let parent = entity.parent { parent.isEnabled = true }

        // SharePlay broadcast placeholder (commented out)
        // if let arViewModel = model.arViewModel {
        //     Task {
        //         await arViewModel.broadcastModelSelection(instanceID: instanceID)
        //     }
        // }

        #if DEBUG
        print("Select: Selected \(name) (instance: \(model.id))")
        #endif
    }

    @MainActor func selectModel(instanceID: UUID) {
        guard let model = self.modelDict[instanceID] else { return }
        self.selectedModelID = model.modelType
        self.selectedModelInstanceID = model.id
    }

    @MainActor func deselectModel() {
        if let currentID = selectedModelInstanceID {
            #if DEBUG
            print("Deselect: Clearing selection (was instance: \(currentID))")
            #endif
        }
        selectedModelID = nil
        selectedModelInstanceID = nil
    }

}

#endif
