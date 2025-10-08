///
//  ARViewModel.swift
//  XR Share
//
//  Core AR/XR view model with streamlined functionality
//

import SwiftUI
import Combine
import RealityKit
import GroupActivities
#if os(iOS)
import ARKit
#endif

/// Main view model for AR/XR functionality
@MainActor
class ARViewModel: NSObject, ObservableObject {

// MARK: - Published Properties
    
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var loadingProgress: Float = 0.0
    @Published var isConnected: Bool = false
    @Published var participantCount: Int = 0
    
    @Published var userRole: UserRole = .localSession
    @Published var connectedPeers: [String] = []
    @Published var selectedSession: Session? = nil
    
    
    @Published var sessionIsActive = false
    @Published var showingParticipantsList = false

    var openWindowAction: ((String) -> Void)?
    var dismissWindowAction: ((String) -> Void)?

    // Pending placement coordinate
    @Published var pendingPlacementPosition: SIMD3<Float>? = nil

    // Pending head-centered placement request
    var pendingHeadCenterInstanceID: UUID?

    // Manage head anchored placement across frames
    struct HeadCenterWork {
        var instanceID: UUID
        var headAnchor: AnchorEntity
        var attemptsRemaining: Int
    }
    var headCenterWork: HeadCenterWork?

    // Take and clear the pending request
    func takePendingHeadCenterRequest() -> UUID? {
        let id = pendingHeadCenterInstanceID
        pendingHeadCenterInstanceID = nil
        return id
    }

    
    let sharedAnchorEntity = AnchorEntity(.world(transform: matrix_identity_float4x4))
    private let sharedAnchorID = UUID()

    
// MARK: - Properties
    
    @Published var currentScene: RealityKit.Scene?
    
    // SharePlay integration
    var sharePlayCoordinator: SharePlayCoordinator?
    #if os(visionOS)
    
    // Backing storage that avoids direct reference to a versioned type in a stored property
    private var _manipulationManagerAny: Any?
    @available(visionOS 26.0, *)
    var manipulationManager: ManipulationManager? {
        get { _manipulationManagerAny as? ManipulationManager }
        set { _manipulationManagerAny = newValue }
    }

    // VisionOS spatial coordinator wiring
    private var _spatialCoordinatorAny: Any?
    @available(visionOS 26.0, *)
    var spatialCoordinator: VisionOSSpatialCoordinator? {
        get { _spatialCoordinatorAny as? VisionOSSpatialCoordinator }
        set { _spatialCoordinatorAny = newValue }
    }
    #endif
    
    
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""
    var models: [Model] = []
    
    private var subscriptions = Set<AnyCancellable>()
    @Published var modelManager: ModelManager?

    
    
// MARK: - Initialization
    
    // Initialize SharePlay coordinator
    override init() {
        super.init()
        
        self.sharePlayCoordinator = SharePlayCoordinator()
        self.sharePlayCoordinator?.delegate = self
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            self.manipulationManager = ManipulationManager(sharePlayCoordinator: sharePlayCoordinator)
        }
        #endif
        
        observeSharePlayState()
        
        print("ARViewModel initialized with sessionID: \(sessionID)")
    }
    
    deinit {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
}



// MARK: - SharePlay Methods

extension ARViewModel {
    func startSharePlaySession(name: String) async {
        sessionName = name
        await sharePlayCoordinator?.startSession(name: name)
    }
    
    func joinSharePlaySession() async {
        await sharePlayCoordinator?.joinSession()
    }
    
    @MainActor func leaveSharePlaySession() {
        sharePlayCoordinator?.leaveSession()
    }
    
    private func observeSharePlayState() {
        sharePlayCoordinator?.$isConnected
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                self.isConnected = isConnected

                // Initialize manipulation manager when SharePlay connects
                if isConnected {
                    #if os(visionOS)
                    if #available(visionOS 26.0, *), self.manipulationManager == nil {
                        self.manipulationManager = ManipulationManager(sharePlayCoordinator: self.sharePlayCoordinator)
                        print("ARViewModel: Initialized ManipulationManager for SharePlay session")
                    }
                    #endif
                }
            }
            .store(in: &subscriptions)
            
        sharePlayCoordinator?.$participantCount
            .sink { [weak self] count in
                self?.participantCount = count
            }
            .store(in: &subscriptions)

        sharePlayCoordinator?.$isHost
            .sink { [weak self] isHost in

            }
            .store(in: &subscriptions)
        
        if let coordinator = sharePlayCoordinator {
            coordinator.$hasVisionParticipants
                .sink { [weak self] (hasVision: Bool) in

                }
                .store(in: &subscriptions)
        }
    }
}


// MARK: - Model Synchronization Methods (Outbound Broadcasts)

/// Methods to broadcast local changes to peers in shareplay session
extension ARViewModel {
    
    /// Call this when a new model is added in the session
    func broadcastAddModel(modelType: ModelType, instanceID: UUID, entity: Entity) async {
        guard let coordinator = sharePlayCoordinator, coordinator.isConnected else {
            print("SharePlay not connected, skipping broadcastAddModel")
            return
        }
        
        let position = entity.position(relativeTo: sharedAnchorEntity)
        let rotation = entity.orientation(relativeTo: sharedAnchorEntity)
        let scale = entity.scale(relativeTo: sharedAnchorEntity)
        
        let referenceID = sharePlayCoordinator?.currentReferenceAnchorID ?? sharedAnchorID
        let transform = UniversalTransform(
            position: position,
            rotation: rotation,
            scale: scale,
            referenceAnchorID: referenceID
        )
        
        print("Broadcasting AddModel: \(modelType.rawValue)")
        print(" Position: \(position)")
        print("Scale: \(scale)")
        print("InstanceID: \(instanceID)")
        
        await coordinator.sendAddModel(
            modelType: modelType,
            instanceID: instanceID,
            transform: transform
        )
    }
    
    
    /// Call this when a model is removed from the session
    func broadcastRemoveModel(instanceID: UUID) async {
        await sharePlayCoordinator?.sendRemoveModel(instanceID: instanceID)
    }
    
    
    
    /// Call this when there is model a transform update in the session
    func broadcastModelTransform(instanceID: UUID, entity: Entity) async {
        let referenceID = sharePlayCoordinator?.currentReferenceAnchorID ?? sharedAnchorID

        let transform = UniversalTransform(
            position: entity.position(relativeTo: sharedAnchorEntity),
            rotation: entity.orientation(relativeTo: sharedAnchorEntity),
            scale: entity.scale(relativeTo: sharedAnchorEntity),
            referenceAnchorID: referenceID
        )
        await sharePlayCoordinator?.sendModelTransform(instanceID: instanceID, transform: transform)
    }
    
    
    
    /// Call this when a model is selected in session
    func broadcastModelSelection(instanceID: UUID) async {
        guard let participantID = sharePlayCoordinator?.localParticipantID else { return }
        
        await sharePlayCoordinator?.sendSelectModel(
            
            entityID: instanceID,
            participantID: participantID
        )
    }
    
    
    
    /// Call this when ownership changes
    func broadcastOwnershipChange(instanceID: UUID, newOwner: UUID) async {
        
        
        await sharePlayCoordinator?.sendOwnershipChange(
            entityID: instanceID,
            newOwner: newOwner
        )
    }
    
    
}


// MARK: - SharePlayCoordinator Delegate (Inbound)

/// Delegate methods for handling remote messages and events, applies remote changes  to local scene
extension ARViewModel: SharePlayCoordinatorDelegate {
    
    /// Handle participant state changes
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didUpdateParticipantStates states: [UUID : SystemCoordinator.ParticipantState]) async {
        
        print("ARViewModel: Participant states updated")
        
        
        for (participantID, _) in states {
            print("  - Participant \(participantID):")
            }
    }


    /// Handle anchor data with  incoming anchors
    @available(visionOS 26.0, *)
    func shareWorldAnchorWithParticipants(_ participants: Set<Participant>) async {
        guard let coordinator = self.spatialCoordinator else { return }
        if let msg = await coordinator.createAndShareAnchor() {
            await sharePlayCoordinator?.sendAnchorMessage(msg, to: participants)
}
}
    
    
    
    /// Applies remote AddModelMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveAddModel message: AddModelMessage) async {
        
        print(" Received AddModelMessage from remote participant:")
        print("  Model: \(message.modelType.rawValue)")
        print("InstanceID: \(message.instanceID)")
        print("Position: \(message.initialTransform.position)")
        print("Scale: \(message.initialTransform.scale)")
        
        // Enhanced duplicate detection, check all existing models
        let isDuplicate = modelManager?.placedModels.contains { model in
            guard let entity = model.modelEntity,
                  let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
            let modelInstanceID = UUID(uuidString: instanceComp.id)
            if modelInstanceID == message.instanceID {
                print(" Found existing model with same ID: \(message.instanceID)")
                return true
            }
            return false
        } ?? false
        
        if isDuplicate {
            print("Model with ID \(message.instanceID) already exists, skipping duplicate")
            return
        }
        
        // Create and load the model properly with all components
        print(" Loading model \(message.modelType.rawValue)...")
        let model = await Model.load(modelType: message.modelType, arViewModel: self)
        
        guard let modelEntity = model.modelEntity else {
            print("Failed to load model entity for \(message.modelType.rawValue)")
            return
        }
        
        // Set the instance ID to match the sender's
        modelEntity.components.set(InstanceIDComponent(id: message.instanceID.uuidString))
        
        sharedAnchorEntity.addChild(modelEntity)
        
        // Apply the transform relative to shared anchor (single assignment to reduce overhead)
        let transform = message.initialTransform
        modelEntity.transform = Transform(
            scale: transform.scale,
            rotation: transform.rotation,
            translation: transform.position
        )
        
        print("Applied transformm - Position: \(modelEntity.position(relativeTo: sharedAnchorEntity))")
        
        // Configure for manipulation and add required components
        modelManager?.configureInteractivity(for: modelEntity, arViewModel: self)
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            manipulationManager?.configureModelForManipulation(entity: modelEntity)
        }
        #endif
        
        // Add components for tracking
        modelEntity.components.set(ModelTypeComponent(type: message.modelType))
        modelEntity.components.set(LastTransformComponent(matrix: modelEntity.transform.matrix))
        
        // Ensure the model has all necessary components for interaction
        if modelEntity.components[InputTargetComponent.self] == nil {
            modelEntity.components.set(InputTargetComponent())
        }
        if modelEntity.components[HoverEffectComponent.self] == nil {
            modelEntity.components.set(HoverEffectComponent())
            
            
        }
        if modelEntity.collision == nil {
            modelEntity.generateCollisionShapes(recursive: true)
        }
        

        // Add to manager collections
        modelManager?.placedModels.append(model)
        modelManager?.modelDict[modelEntity] = model
        
        print("Successfully added remote model: \(message.modelType.rawValue) (ID: \(message.instanceID))")
        print(" Total models in scene: \(modelManager?.placedModels.count ?? 0)")
        
                }
    
    
    
    /// Applies remote RemoveModelMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveRemoveModel message: RemoveModelMessage) async {
        print("ARViewModel: Handling RemoveModelMessage for ID: \(message.instanceID)")
        
        // Find the model with this instance ID
        if let model = modelManager?.placedModels.first(where: { model in
            guard let entity = model.modelEntity,
                  let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
            return UUID(uuidString: instanceComp.id) == message.instanceID
            
        }) {
            
            // Remove without broadcasting
            modelManager?.removeModel(model, broadcast: false)
            
            print("Successfully removed remote model with ID: \(message.instanceID)")

            if (modelManager?.placedModels.isEmpty == true) {
                
                print("Last model removed, delete model menu bar and control panel")
                
                dismissWindowAction?("ModelMenuBar")
                dismissWindowAction?("ModelControlPanel")
            }
            
        } else {
            print("Could not find model with ID: \(message.instanceID)")
            }
    }
    
    
    /// Applies remote ModelTransformMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveTransformUpdate message: ModelTransformMessage) async {
        print("ARViewModel: Handling ModelTransformMessage for ID: \(message.instanceID)")
        
        // Find the entity with this instance ID
        if let model = modelManager?.placedModels.first(where: { model in
            guard let entity = model.modelEntity,
                  let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
            return UUID(uuidString: instanceComp.id) == message.instanceID
        }), let entity = model.modelEntity {
            
            
            // Apply the new transform
            let transform = message.newTransform
            entity.transform = Transform(
                scale: transform.scale,
                rotation: transform.rotation,
                translation: transform.position
            )
            
            // Update the last transform component to avoid re-broadcasting
            entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)
            
            
            print("Successfully updated transform for model ID: \(message.instanceID)")
        } else {
            print("Could not find model with ID: \(message.instanceID)")
            
                }
    }

    /// Applies remote SelectModelMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveModelSelection message: SelectModelMessage) async {
        print("ARViewModel: Handling SelectModelMessage for ID: \(message.entityID)")
        
        // Find and select the model
        if let model = modelManager?.placedModels.first(where: { model in
            guard let entity = model.modelEntity,
                  let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
            return UUID(uuidString: instanceComp.id) == message.entityID
        }) {
            modelManager?.selectedModelInstanceID = model.id
            modelManager?.selectedModelID = model.modelType
            print("Successfully selected remote model: \(model.modelType.rawValue)")
                }
    }
    
    
    /// Applies remote OwnershipChangeMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveOwnershipChange message: OwnershipChangeMessage) async {
        print("ARViewModel: Handling OwnershipChangeMessage for ID: \(message.entityID)")
        
        
        // Find the entity and update ownership
        if let model = modelManager?.placedModels.first(where: { model in
            guard let entity = model.modelEntity,
                  let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
            return UUID(uuidString: instanceComp.id) == message.entityID
        }), let entity = model.modelEntity {
            
            entity.components.set(OwnershipComponent(participantID: message.newOwner))
            print("Successfully updated ownership for model ID: \(message.entityID)")
        }
    }
    
    
    /// Applies remote SyncAllModelsMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveSyncAllModels message: SyncAllModelsMessage) async {

        print("Received SyncAllModelsMessage with \(message.models.count) models")
        print("   Reference Anchor ID: \(message.referenceAnchorID)")
        
        
        // Clear existing models first to avoid duplicates
        print("Clearing existing models")
        modelManager?.reset()
        
        
        // Add all models from sync message
        for (index, modelState) in message.models.enumerated() {
            print("   [\(index + 1)/\(message.models.count)] Syncing \(modelState.modelType.rawValue)")
            
            await sharePlayCoordinator(coordinator, didReceiveAddModel: AddModelMessage(
                modelType: modelState.modelType,
                instanceID: modelState.instanceID,
                initialTransform: modelState.transform
            ))
            
            // Set ownership if specified
            if let ownerID = modelState.ownerID,
               let model = modelManager?.placedModels.first(where: { model in
                   guard let entity = model.modelEntity,
                         let instanceComp = entity.components[InstanceIDComponent.self] else { return false }
                   return UUID(uuidString: instanceComp.id) == modelState.instanceID
               }), let entity = model.modelEntity {
                entity.components.set(OwnershipComponent(participantID: ownerID))
                print("   Set owner: \(ownerID)")
            }
    }
        
        print(" Successfully synchronized \(message.models.count) models")
        print(" Total models in scene: \(modelManager?.placedModels.count ?? 0)")

        if (modelManager?.placedModels.isEmpty == true) {
            dismissWindowAction?("ModelMenuBar")
            dismissWindowAction?("ModelControlPanel")
        }
}
    
    
    /// Applies remote RequestSyncMessage to local state
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveAnchor message: AnchorMessage) async {
        print("ARViewModel: Handling AnchorMessage for anchor ID: \(message.anchorID)")
        
        #if os(visionOS)
        if #available(visionOS 26.0, *), message.anchorType == .worldAnchor {
            await spatialCoordinator?.handleAnchorMessage(message)
        }
        #endif
        
        print("Received anchor data for spatial alignment")
    }
    
}


extension ARViewModel {

    // MARK: - Reset Methods

    /// Comprehensive reset of all ARViewModel state for clean restart
    @MainActor
    func resetToCleanState() {
        print("ARViewModel: Resetting to clean state")
        selectedModel = nil

        showingParticipantsList = false
   

        loadingProgress = 0.0
        alertItem = nil
        showingParticipantsList = false
        sessionIsActive = false
   
        pendingPlacementPosition = nil
        pendingHeadCenterInstanceID = nil
        headCenterWork = nil

        
        // Clean up spatial coordinator
        if #available(visionOS 26.0, *), let coordinator = spatialCoordinator {
            Task {
                await coordinator.cleanup()
            }
        }
        
        
        if #available(visionOS 26.0, *) {
            spatialCoordinator = nil
        }

        // Clean up manipulation manager
        if #available(visionOS 26.0, *) {
            manipulationManager?.reset()
            manipulationManager = nil
        }


        // Reset shared anchor entity, clear all children and reset transform
        sharedAnchorEntity.children.removeAll()
        sharedAnchorEntity.transform = Transform(translation: SIMD3<Float>(0, 1.2, -1.2))
     
        sharedAnchorEntity.isEnabled = true


        print("ARViewModel: Clean state reset completed")
    }

}
