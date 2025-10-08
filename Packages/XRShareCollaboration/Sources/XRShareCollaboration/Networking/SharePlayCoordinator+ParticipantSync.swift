//
//  SharePlayCoordinator+ParticipantSync.swift
//  XR Share
//
//  Participant synchronization and message observation for Shareplay
//

import Foundation
import GroupActivities
import Combine
import SwiftUI

extension SharePlayCoordinator {
    
    /// Sets up all related observers for active shareplay session
    func observeRemoteParticipantUpdates() {
        observeActiveRemoteParticipants()
        observeRemoteModelUpdates()
      
    }
    
    /// Subscribes to reliable and unreliable data streams for model synchronization
    private func observeRemoteModelUpdates() {
        guard let messenger = messenger else { return }

        
        // One reliable Data stream for all reliable messages
        let reliableTask = Task { [weak self] in
            for await (data, context) in messenger.messages(of: Data.self) {
                await self?.handleWireData(data, from: context)
            }
        }
        tasks.insert(reliableTask)

        // One unreliable Data stream for latency sensitive messages
        if let unreliable = self.unreliableMessenger {
            let unreliableTask = Task { [weak self] in
                for await (data, context) in unreliable.messages(of: Data.self) {
                    await self?.handleWireData(data, from: context)
                }
            }
            tasks.insert(unreliableTask)
        }
    }
    
    
    /// Observes changes to the current set of active participants and reacts to joins and leaves
    private func observeActiveRemoteParticipants() {
        
        guard let session = self.groupSession else { return }
        
        // Track previous participants to detect joins/leaves
        var previousParticipants: Set<Participant> = []
        
        let participantsTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await currentParticipants in session.$activeParticipants.values {
                
                // Create sets of remote participants (excluding local participant)
                let currentRemoteParticipants = currentParticipants.subtracting([session.localParticipant])
                let previousRemoteParticipants = previousParticipants.subtracting([session.localParticipant])
                
                // Detect new participants
                let newParticipants = currentRemoteParticipants.subtracting(previousRemoteParticipants)
                
                // Detect removed participants
                let removedParticipants = previousRemoteParticipants.subtracting(currentRemoteParticipants)
                
                if !newParticipants.isEmpty {

                    #if os(visionOS)
                    
                    if #available(visionOS 26.0, *), let delegate = self.delegate as? ARViewModel {
                        await delegate.shareWorldAnchorWithParticipants(newParticipants)
                        await self.sendSyncAllModels(to: newParticipants)
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            await self?.sendSyncAllModels(to: newParticipants)
                        }
                    }
                    #endif
                    
                    // Handshake to new participants
                    await self.sendHandshake(to: newParticipants)
                }

                // Remove any participants that have left from tracking
                for participant in removedParticipants {
                    print("Participant left: \(participant.id)")
                }
                
                // Update previous participants for next iteration
                previousParticipants = currentParticipants
            }
        }
        
        tasks.insert(participantsTask)
    }
    
    
    
    /// Send all current model states to participants
    func sendSyncAllModels(to participants: Set<Participant>) async {
        
        // Get current models from delegate
        var modelStates: [SyncAllModelsMessage.ModelState] = []
        
        if let delegate = delegate as? ARViewModel {
            
            
            // Get the current models and their states
            for model in delegate.modelManager?.placedModels ?? [] {
                guard let entity = model.modelEntity,
                      let instanceComp = entity.components[InstanceIDComponent.self],
                      let instanceID = UUID(uuidString: instanceComp.id) else { continue }
                
                let transform = UniversalTransform(
                    position: entity.position(relativeTo: delegate.sharedAnchorEntity),
                    rotation: entity.orientation(relativeTo: delegate.sharedAnchorEntity),
                    scale: entity.scale(relativeTo: delegate.sharedAnchorEntity),
                    referenceAnchorID: currentReferenceAnchorID // Use the coordinator's anchor ID
                )
                
                let ownerID = entity.components[OwnershipComponent.self]?.participantID
                
                modelStates.append(SyncAllModelsMessage.ModelState(
                    modelType: model.modelType,
                    instanceID: instanceID,
                    transform: transform,
                    ownerID: ownerID
                ))
                }
                }
        
        let message = SyncAllModelsMessage(
            models: modelStates,
            referenceAnchorID: currentReferenceAnchorID
        )
        
        do {
            try await sendWireReliable(message, kind: WireKind.syncAllModels, to: participants)
            
            print(" Sent SyncAllModelsMessage with \(modelStates.count) models to \(participants.count) participants")
            
            
            
        } catch {
            
            print("Failed to send SyncAllModelsMessage: \(error)")
        }
    }
    

    
    /// Send a protocol / version handshake to participatns for capacbilities
    func sendHandshake(to participants: Set<Participant>? = nil) async {
        
#if os(visionOS)
        
        let platformName = "visionOS"
        
#else
        
        let platformName = "iOS"
        
#endif
        
        let sender = self.localParticipantID ?? self.groupSession?.localParticipant.id ?? UUID()
        
        let handshake = ProtocolHandshakeMessage(
            protocolVersion: 1,
            appName: "Demo",
            platform: platformName,
            senderID: sender,
            supportsModelSync: true,
            supportsARWorldMap: true,
            supportsUnreliableTransforms: true
        )
        do {
            
            if let participants = participants {
                
                try await sendWireReliable(handshake, kind: WireKind.protocolHandshake, to: participants)
                print(" Sent ProtocolHandshakeMessage to \(participants.count) participants")
                
            } else {
                
                try await sendWireReliable(handshake, kind: WireKind.protocolHandshake)
                print(" Sent ProtocolHandshakeMessage to all participants")
            }
            
        } catch {
            print("Failed to send ProtocolHandshakeMessage: \(error)")
    }
        
        
    }
}




