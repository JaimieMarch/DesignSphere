//
//  ManipulationManager.swift
//  XR Share
//
// Manages 3D object manipulation


import Foundation
import RealityKit
import SwiftUI
import Combine
import QuartzCore


#if os(visionOS)
#endif

/// Manages manipulation of 3D entities for VisionOS
@available(visionOS 26.0, *)
@MainActor
class ManipulationManager {
    private var sharePlayCoordinator: SharePlayCoordinator?
    private var manipulationSubscriptions: [Entity: AnyCancellable] = [:]
    
    #if os(visionOS)
    private var didInstallSubscriptions = false
    private var contentSubscriptions: [EventSubscription] = []
    #endif

    private var lastSendTime: [UUID: CFTimeInterval] = [:]
    private let minSendInterval: CFTimeInterval = 1.0 / 30.0
    private let debugTransforms = false

    init(sharePlayCoordinator: SharePlayCoordinator? = nil) {
        self.sharePlayCoordinator = sharePlayCoordinator
    }
    
    /// Configure an entity for manipulation
    @available(visionOS 26.0, *)
    func configureModelForManipulation(entity: Entity) {
        
        // Create ManipulationComponent with releaseBehavior set to .stay
        var manipulationComponent = ManipulationComponent()
        manipulationComponent.releaseBehavior = .stay
        
        // Add the component to the entity
        entity.components.set(manipulationComponent)
        
        // Add the required supporting components
        if entity.components[CollisionComponent.self] == nil {
            entity.generateCollisionShapes(recursive: true)
        }
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(HoverEffectComponent(.spotlight(.default)))
        

    }
    
    @available(visionOS 26.0, *)
    func setupManipulationEventHandlers(for content: RealityViewContent) {
        if didInstallSubscriptions { return }
        
        // Subscribe to transform updates
        let didUpdateToken = content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { [weak self] event in
            guard let self = self,
                  let instanceIDString = event.entity.components[InstanceIDComponent.self]?.id,
                  let instanceID = UUID(uuidString: instanceIDString) else { return }
            
            Task {
                await self.handleTransformUpdate(for: event.entity, instanceID: instanceID)
            }
    }

        // Subscribe to manipulation begin events for ownership and selection
        let willBeginToken = content.subscribe(to: ManipulationEvents.WillBegin.self) { [weak self] event in
            
            guard let self = self,
                  
                  let instanceIDString = event.entity.components[InstanceIDComponent.self]?.id,
                  let instanceID = UUID(uuidString: instanceIDString) else { return }
            
            event.entity.components.remove(PhysicsMotionComponent.self)
            event.entity.components.remove(PhysicsBodyComponent.self)
            
            Task {
                await self.handleSelection(for: event.entity, instanceID: instanceID)
                            
                // Handle ownership change
                if let participantID = self.sharePlayCoordinator?.localParticipantID {
                    await self.handleOwnershipChange(for: event.entity, instanceID: instanceID, newOwnerID: participantID)
                }
    }
    }

        
        // Subscribe to manipulation end events
        let willEndToken = content.subscribe(to: ManipulationEvents.WillEnd.self) { [weak self] event in
            guard let self = self else { return }
            
            event.entity.components.remove(PhysicsMotionComponent.self)
            
            // Send final transform after manipulation ends
            if let instanceIDString = event.entity.components[InstanceIDComponent.self]?.id,
               let instanceID = UUID(uuidString: instanceIDString) {
                Task {
                    await self.handleTransformUpdate(for: event.entity, instanceID: instanceID, force: true)
                }
            }
        }

        // Subscribe to hand-off events, so when another participant takes control of the model
        let handOffToken = content.subscribe(to: ManipulationEvents.DidHandOff.self) { [weak self] event in
            guard let self = self,
                  let instanceIDString = event.entity.components[InstanceIDComponent.self]?.id,
                  let instanceID = UUID(uuidString: instanceIDString) else { return }
            
            Task {
                if let participantID = self.sharePlayCoordinator?.localParticipantID {
                    await self.handleOwnershipChange(for: event.entity, instanceID: instanceID, newOwnerID: participantID)
                }
            }
        }
        
        contentSubscriptions.append(contentsOf: [didUpdateToken, willBeginToken, willEndToken, handOffToken])
        didInstallSubscriptions = true

        print("visionOS: ManipulationEvents subscriptions configured.")
    }
    
    
    
    
    /// Called when a model's transform changes, so when the model is moved, rotated or expanded
    func handleTransformUpdate(for entity: Entity, instanceID: UUID, force: Bool = false) async {
        
        // Only send to SharePlay if we're connected and have a coordinator
        guard let coordinator = sharePlayCoordinator,
              coordinator.isConnected else {
            if debugTransforms {
                print("Local session: transform update for id=\(instanceID) pos=\(entity.position(relativeTo: entity.parent)) ( no SharePlay sync)")
            }
            return
        }
        
        let now = CACurrentMediaTime()
        if !force, let last = lastSendTime[instanceID], (now - last) < minSendInterval {
            return
        }
        lastSendTime[instanceID] = now
        
        

        // Create transform relative to the shared anchor
        let reference: Entity? = entity.parent
        let transform = UniversalTransform(
            position: entity.position(relativeTo: reference),
            rotation: entity.orientation(relativeTo: reference),
            scale: entity.scale(relativeTo: reference),
            referenceAnchorID: coordinator.currentReferenceAnchorID
        )
        
        if debugTransforms {
            print("SharePlay session: send transform: id=\(instanceID) pos=\(transform.position)")
        }
        
        // Send message to shareplay coordinator
        await coordinator.sendModelTransform(instanceID: instanceID, transform: transform)
    }
    
    
    /// Called when a model is selected
    func handleSelection(for entity: Entity, instanceID: UUID) async {
        
        // Only send to SharePlay if we're connected and have a coordinator
        guard let coordinator = sharePlayCoordinator,
              coordinator.isConnected,
              let participantID = coordinator.localParticipantID else {
            
            // Otherwise in local session, just handle selection locally
            print("Local session: model selected id=\(instanceID) (no SharePlay sync)")
            return
        }
        
        Task {
            // Send message to shareplay coordinator
            await coordinator.sendSelectModel(entityID: instanceID, participantID: participantID)
        }
    }
    
    
    
    // Called when ownership changes
    func handleOwnershipChange(for entity: Entity, instanceID: UUID, newOwnerID: UUID) async {
        
        // Always update local ownership component but only send to SharePlay if it is connected
        entity.components.set(OwnershipComponent(participantID: newOwnerID))
        
        if let coordinator = sharePlayCoordinator, coordinator.isConnected {
            print("SharePlay session: ownership change for id=\(instanceID) to owner=\(newOwnerID)")
            
        } else {
            print("Local session: ownership change for id=\(instanceID) to owner=\(newOwnerID) (local only)")
        }
    }
    
    
    // Remove manipulation capabilities from an entity
    func removeManipulation(from entity: Entity) {
        
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(GestureComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(CollisionComponent.self)
    }
    

    
// MARK: - Cleanup

    /// Reset all state for clean session restart
    func reset() {
        print("ManipulationManager: Resetting state")

        // Cancel all entity subscriptions
        manipulationSubscriptions.values.forEach { $0.cancel() }
        manipulationSubscriptions.removeAll()

        #if os(visionOS)
        // Cancel all event subscriptions
        contentSubscriptions.forEach { $0.cancel() }
        contentSubscriptions.removeAll()
        didInstallSubscriptions = false
        #endif

        lastSendTime.removeAll()

        sharePlayCoordinator = nil

        print("ManipulationManager: Reset completed")
    }
}

