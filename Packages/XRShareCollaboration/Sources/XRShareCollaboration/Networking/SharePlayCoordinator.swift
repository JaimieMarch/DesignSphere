//
//  SharePlayCoordinator.swift
//  XR Share
//
//  Manages the app's active SharePlay session and handles communication between participants
//

import Foundation
import GroupActivities
import Combine
import SwiftUI
import RealityKit

@MainActor
class SharePlayCoordinator: ObservableObject {
    @Published var isConnected = false
    @Published var participantCount = 0
    @Published var isHost = false
    
    private var isHandlingReceivedMessage = false
    
    @Published var hasVisionParticipants: Bool = false
    
    private var previousParticipantCount = 0
    
    // SharePlay session management
    var groupSession: GroupSession<DemoActivity>?
    var messenger: GroupSessionMessenger?
    var unreliableMessenger: GroupSessionMessenger?
    
    private var subscriptions = Set<AnyCancellable>()
    var tasks = Set<Task<Void, Never>>()
    
    var mirrorReliableTransforms: Bool = false

    private var receivedAnyModelState: Bool = false
    private var lateResyncTask: Task<Void, Never>?

    // Peer capability map from ProtocolHandshakeMessage
    struct ParticipantCapabilities {
        let platform: String
        let supportsModelSync: Bool
        let supportsARWorldMap: Bool
        let supportsUnreliableTransforms: Bool
    }
    private var capabilitiesByParticipant: [UUID: ParticipantCapabilities] = [:]
    
    // Public getter for the session
    var session: GroupSession<DemoActivity>? {
        return groupSession
    }

    // SystemCoordinator for spatial support
    #if os(visionOS)
    private(set) var systemCoordinator: SystemCoordinator?
    #endif
    
    weak var delegate: SharePlayCoordinatorDelegate?
    
    private var currentModelsState: [UUID: (ModelType, UniversalTransform, UUID?)] = [:]
    private(set) var currentReferenceAnchorID: UUID = UUID()

    // Participant tracking
    private(set) var localParticipantID: UUID?
    #if os(visionOS)
    private var participantStates: [UUID: SystemCoordinator.ParticipantState] = [:]
    #endif
    
    init() {
        observeGroupSessions()
    }
    
    
// MARK: - Group Session Management
    
    /// Observe incoming group session for DemoActivity
    private func observeGroupSessions() {
        Task {
            for await session in DemoActivity.sessions() {
                await configureGroupSession(session)
            }
        }
    }
    
    
    /// Configures a new GroupSession
    func configureGroupSession(_ session: GroupSession<DemoActivity>) async {
        
        groupSession = session
        localParticipantID = session.localParticipant.id
        
        
        // Create messenger for sending and receiving messages
        messenger = GroupSessionMessenger(session: session)
        unreliableMessenger = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
        
        // Get SystemCoordinator from the session (visionOS only)
        #if os(visionOS)
        
        
        if #available(visionOS 26.0, *) {
            systemCoordinator = await session.systemCoordinator
        } else {
            systemCoordinator = nil
        }
        
        #endif
        
        
        
        // Configure SystemCoordinator for group immersive space
        #if os(visionOS)
        
        if #available(visionOS 26.0, *), let coordinator = systemCoordinator {
            var config = SystemCoordinator.Configuration()
            config.supportsGroupImmersiveSpace = true
            config.spatialTemplatePreference = .sideBySide
            coordinator.configuration = config
        }
        
        #endif
        
        
        // Subscribe to session state changes
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleSessionStateChange(state)
            }
            .store(in: &subscriptions)
        
        
        // Subscribe to active participants
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                self?.participantCount = participants.count
                self?.handleParticipantsChanged(participants)
            }
            .store(in: &subscriptions)
        
        // Monitor spatial participant states
        #if os(visionOS)
        if #available(visionOS 26.0, *), let coordinator = systemCoordinator {
            // Check initial participant states
            let initialStates = coordinator.remoteParticipantStates
            handleParticipantStatesUpdate(initialStates)
            
            
            // Monitor local participant state changes via async sequence
            let stateMonitorTask = Task { [weak self] in
                guard let self = self else { return }
                for await _ in coordinator.localParticipantStates {
                    

                    // When local state changes, check all the participant states
                    let currentStates = coordinator.remoteParticipantStates
                    await MainActor.run {
                        self.handleParticipantStatesUpdate(currentStates)
                    }
                }
            }
            tasks.insert(stateMonitorTask)
        }
        #endif
        
        
        // Set up participant observation which includes message handlers
        observeRemoteParticipantUpdates()
        
        
        // Join the group session
        session.join()
    }
    
    
    
    
// MARK: - SharePlay Controls
    
    func startSession(name: String) async {
    
        isHost = true
        
        do {
            _ = try await DemoActivity().activate()
        } catch {
            print("Failed to activate DemoActivity: \(error)")
        }
    }
    
    func joinSession() async {
        isHost = false
    
    }
    
    func leaveSession() {
        groupSession?.leave()
        cleanup()
    }

    func endSessionForAll() {
        groupSession?.end()
        cleanup()
    }
    
    
    
    
// MARK: - Send Message Data to Participants (Outbound)
    
    /// Send AddModelMessage to other participants
    func sendAddModel(modelType: ModelType, instanceID: UUID, transform: UniversalTransform) async {
        let message = AddModelMessage(
            modelType: modelType,
            instanceID: instanceID,
            initialTransform: transform
        )
        do {
            try await sendWireReliable(message, kind: WireKind.addModel)
            
            // Update the local state
            currentModelsState[instanceID] = (modelType, transform, localParticipantID)
            
            print("Sent AddModelMessage for \(modelType.rawValue) (ID: \(instanceID))")
        } catch {
            
            print("Failed to send AddModelMessage: \(error)")
        }
    }

    
    /// Send RemoveModelMessage to other participants
    func sendRemoveModel(instanceID: UUID) async {
        let message = RemoveModelMessage(instanceID: instanceID)
        
        do {
            try await sendWireReliable(message, kind: WireKind.removeModel)
            
            // Update local state
            currentModelsState.removeValue(forKey: instanceID)
            
            print("Sent RemoveModelMessage for ID: \(instanceID)")
            
        } catch {
            
            print("Failed to send RemoveModelMessage: \(error)")
        }
    }
    
    
        
   /// Send ModelTransformMessage to other participants
    func sendModelTransform(instanceID: UUID, transform: UniversalTransform) async {
        let message = ModelTransformMessage(
            instanceID: instanceID,
            newTransform: transform
        )
        
        do {
            try await sendWireUnreliable(message, kind: WireKind.modelTransform)
            if mirrorReliableTransforms {
                try await sendWireReliable(message, kind: WireKind.modelTransform)
            }
            
            // Update local state
            if var state = currentModelsState[instanceID] {
                state.1 = transform
                currentModelsState[instanceID] = state
            }
            print("Sent ModelTransformMessage for ID: \(instanceID)")
            
        } catch {
            
            print("Failed to send ModelTransformMessage: \(error)")
        }
    }
    
    
    /// Send SelectModelMessage to other participants
    func sendSelectModel(entityID: UUID, participantID: UUID) async {
        let message = SelectModelMessage(
            entityID: entityID,
            participantID: participantID
        )
        
        do {
            try await sendWireReliable(message, kind: WireKind.selectModel)
            
            print("Sent SelectModelMessage for ID: \(entityID)")
        } catch {
            print("Failed to send SelectModelMessage: \(error)")
        }
    }

    
    /// Send OwnershipChangeMessage to other participants
    func sendOwnershipChange(entityID: UUID, newOwner: UUID) async {
        let message = OwnershipChangeMessage(
            entityID: entityID,
            newOwner: newOwner
        )
        
        do {
            try await sendWireReliable(message, kind: WireKind.ownershipChange)
            
            // Update local state
            if var state = currentModelsState[entityID] {
                state.2 = newOwner
                currentModelsState[entityID] = state
            }
            
            print("Sent OwnershipChangeMessage for ID: \(entityID)")
        } catch {
            print("Failed to send OwnershipChangeMessage: \(error)")
        }
    }


    /// Send SyncAllModelsMessage to other participants
    func sendSyncAllModels() async {
        guard isHost else {
            print(" Cannot send sync: Not host or no messenger")
            return
        }
        
        // Get current models from the delegate (ARViewModel)
        var modelStates: [SyncAllModelsMessage.ModelState] = []
        
        if let arViewModel = delegate as? ARViewModel,
           let modelManager = arViewModel.modelManager {
            print(" Gathering current models for sync...")
            
            for model in modelManager.placedModels {
                guard let entity = model.modelEntity,
                      let instanceComp = entity.components[InstanceIDComponent.self],
                      let instanceID = UUID(uuidString: instanceComp.id) else { continue }
                
                
                let transform = UniversalTransform(
                    position: entity.position(relativeTo: arViewModel.sharedAnchorEntity),
                    rotation: entity.orientation(relativeTo: arViewModel.sharedAnchorEntity),
                    scale: entity.scale(relativeTo: arViewModel.sharedAnchorEntity),
                    referenceAnchorID: currentReferenceAnchorID
                )
                
                
                let ownerID = entity.components[OwnershipComponent.self]?.participantID
                
                modelStates.append(SyncAllModelsMessage.ModelState(
                    modelType: model.modelType,
                    instanceID: instanceID,
                    transform: transform,
                    ownerID: ownerID
                ))
                
                print("Added \(model.modelType.rawValue) to sync")
            }
        } else {
            
            // Fallback to internal state if delegate not available
            modelStates = currentModelsState.map { (instanceID, state) in
                SyncAllModelsMessage.ModelState(
                    modelType: state.0,
                    instanceID: instanceID,
                    transform: state.1,
                    ownerID: state.2
                )
                }
        }
        
        let message = SyncAllModelsMessage(
            models: modelStates,
            referenceAnchorID: currentReferenceAnchorID
        )
        
        
        do {
            try await sendWireReliable(message, kind: WireKind.syncAllModels)
            print(" Sent SyncAllModelsMessage with \(modelStates.count) models")
            
      
        } catch {
            print("Failed to send SyncAllModelsMessage: \(error)")
        }
    }
    
    
    
    /// Send RequestSyncMessage to other participants
    func sendRequestSync() async {
        guard let participantID = localParticipantID else { return }
        
        let message = RequestSyncMessage(participantID: participantID)
        
        do {
            try await sendWireReliable(message, kind: WireKind.requestSync)
            
            print("Sent RequestSyncMessage")
        } catch {
            print("Failed to send RequestSyncMessage: \(error)")
        }
    }
    
    
    
// MARK: - Anchor Senders
    
    func sendAnchorMessage(_ message: AnchorMessage, to participants: Set<Participant>? = nil) async {
        
        // Update our reference anchor ID locally so future transforms/syncs use the same ID
        currentReferenceAnchorID = message.anchorID

        do {
            try await sendWireReliable(message, kind: WireKind.anchor, to: participants)
            print("Sent AnchorMessage: \(message.anchorType) (ID: \(message.anchorID))")
            
        } catch {
            print("Failed to send AnchorMessage: \(error)")
        }
    }

    
    
    
// MARK: - Receive and Handle Message Data from Participants (Inbound)
    
    /// Handle AddModelMessage from other participants
    func handle(_ message: AddModelMessage) async {
        print("Received AddModelMessage: \(message.modelType.rawValue) (ID: \(message.instanceID))")
        
        receivedAnyModelState = true
        cancelLateJoinResyncIfNeeded()
        
        // Update local state
        currentModelsState[message.instanceID] = (message.modelType, message.initialTransform, nil)
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveAddModel: message)
    }
    
    
    /// Handle RemoveModelMessage from other participants
    func handle(_ message: RemoveModelMessage) async { // Changed from private to internal
        print("Received RemoveModelMessage: ID \(message.instanceID)")
        
        // Update local state
        currentModelsState.removeValue(forKey: message.instanceID)
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveRemoveModel: message)
    }
    
    
    /// Handle ModelTransformMessage from other participants
    func handle(_ message: ModelTransformMessage) async { // Changed from private to internal
        print("Received ModelTransformMessage: ID \(message.instanceID)")
        
        // Update local state
        if var state = currentModelsState[message.instanceID] {
            state.1 = message.newTransform
            currentModelsState[message.instanceID] = state
            }
        
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveTransformUpdate: message)
    }
    
    
    /// Handle SelectModelMessage from other participants
    func handle(_ message: SelectModelMessage) async { // Changed from private to internal
        print("Received SelectModelMessage: ID \(message.entityID)")
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveModelSelection: message)
    }
    
    
    
    /// Handle OwnershipChangeMessage from other participants
    func handle(_ message: OwnershipChangeMessage) async { // Changed from private to internal
        print("Received OwnershipChangeMessage: ID \(message.entityID), Owner: \(message.newOwner)")
        
        // Update local state
        if var state = currentModelsState[message.entityID] {
            state.2 = message.newOwner
            currentModelsState[message.entityID] = state
        }
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveOwnershipChange: message)
    }
    
    
    
    /// Handle SyncAllModelsMessage from other participants
    func handle(_ message: SyncAllModelsMessage) async { // Changed from private to internal
        print("Received SyncAllModelsMessage with \(message.models.count) models")
        
        receivedAnyModelState = true
        cancelLateJoinResyncIfNeeded()
        
        // Update local state
        currentReferenceAnchorID = message.referenceAnchorID
        currentModelsState.removeAll()
        
        for modelState in message.models {
            currentModelsState[modelState.instanceID] = (modelState.modelType, modelState.transform, modelState.ownerID)
            }
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveSyncAllModels: message)
    }
    
    
    /// Handle RequestSyncMessage from other participants
    func handle(_ message: RequestSyncMessage) async { // Changed from private to internal
        print("Received RequestSyncMessage from participant: \(message.participantID)")


        if isHost {
            var target: Set<Participant> = []
            if let session = groupSession {
                let matches = session.activeParticipants.filter { $0.id == message.participantID }
                target = Set(matches)
            }
            await sendSyncAllModels()
        }
    }
    
    
    /// Handle AnchorMessage from other participants
    func handle(_ message: AnchorMessage) async { // Changed from private to internal
        print("Received AnchorMessage: \(message.anchorType) (ID: \(message.anchorID))")
        
        // Update reference anchor
        currentReferenceAnchorID = message.anchorID
        
        // Forward to SharePlayCoordinator delegate
        await delegate?.sharePlayCoordinator(self, didReceiveAnchor: message)
    }

    
    /// Handle ProtocolHandshakeMessage from other participants
    func handle(_ message: ProtocolHandshakeMessage) async {
        print("Received ProtocolHandshakeMessage: version=\(message.protocolVersion), app=\(message.appName), platform=\(message.platform), modelSync=\(message.supportsModelSync), worldMap=\(message.supportsARWorldMap), unreliable=\(message.supportsUnreliableTransforms)")
       
    }

    

// MARK: - Wire Helpers

func sendWireReliable<M: Codable>(_ payload: M, kind: WireKind, to participants: Set<Participant>? = nil) async throws {
    guard let messenger = messenger else {
        throw NSError(domain: "SharePlayCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No messenger"])
    }
    let data = try WireCodec.encode(payload, kind: kind)
    if kind == .modelTransform {
        print("Wire(slow) send: modelTransform (\(data.count) bytes)")
    }
    if let participants = participants {
        try await messenger.send(data, to: .only(participants))
    } else {
        try await messenger.send(data)
    }
}
    
    

func sendWireUnreliable<M: Codable>(_ payload: M, kind: WireKind) async throws {
    guard let unreliable = unreliableMessenger else {
        throw NSError(domain: "SharePlayCoordinator", code: -2, userInfo: [NSLocalizedDescriptionKey: "No unreliable messenger"])
    }
    let data = try WireCodec.encode(payload, kind: kind)
    if kind == .modelTransform {
        print("Wire(fast) send: modelTransform (\(data.count) bytes)")
    }
    try await unreliable.send(data)
}
    
    

func handleWireData(_ data: Data, from context: GroupSessionMessenger.MessageContext? = nil) async {
    do {
        let env = try WireCodec.decodeEnvelope(data)
        switch env.t {
        case .addModel:
            let msg = try JSONDecoder().decode(AddModelMessage.self, from: env.message)
            await handle(msg)
        case .removeModel:
            let msg = try JSONDecoder().decode(RemoveModelMessage.self, from: env.message)
            await handle(msg)
        case .modelTransform:
            let msg = try JSONDecoder().decode(ModelTransformMessage.self, from: env.message)
            print("Wire recv: modelTransform for \(msg.instanceID)")
            await handle(msg)
        case .selectModel:
            let msg = try JSONDecoder().decode(SelectModelMessage.self, from: env.message)
            await handle(msg)
        case .ownershipChange:
            let msg = try JSONDecoder().decode(OwnershipChangeMessage.self, from: env.message)
            await handle(msg)
        case .syncAllModels:
            let msg = try JSONDecoder().decode(SyncAllModelsMessage.self, from: env.message)
            await handle(msg)
        case .requestSync:
            let msg = try JSONDecoder().decode(RequestSyncMessage.self, from: env.message)
            await handle(msg)
        case .anchor:
            let msg = try JSONDecoder().decode(AnchorMessage.self, from: env.message)
            await handle(msg)

        case .protocolHandshake:
            let msg = try JSONDecoder().decode(ProtocolHandshakeMessage.self, from: env.message)
            capabilitiesByParticipant[msg.senderID] = ParticipantCapabilities(
                platform: msg.platform,
                supportsModelSync: msg.supportsModelSync,
                supportsARWorldMap: msg.supportsARWorldMap,
                supportsUnreliableTransforms: msg.supportsUnreliableTransforms
            )
            recomputePlatformFlags()
            await handle(msg)
        }
    } catch {
        print("Wire decode error: \(error)")
    }
}

    
    private func handleSessionStateChange(_ state: GroupSession<DemoActivity>.State) {
        switch state {
            
        case .waiting:
            isConnected = false
            receivedAnyModelState = false
            cancelLateJoinResyncIfNeeded()
            
            
        case .joined:
            isConnected = true
            if !isHost {
                Task {
                    await sendRequestSync()
                }
                startLateJoinResyncs()
            } else {
                // For ios as host will send the map
            }

            // Send handshake so other apps can discover capabilities
            Task { [weak self] in
                await self?.sendHandshake()
            }

            
        case .invalidated(let error):
            isConnected = false
            print("Session invalidated with error: \(error)")
            cleanup()
            
            
        @unknown default:
            break
        }
    }
    
    private func handleParticipantsChanged(_ participants: Set<Participant>) {
        
        // Count nearby vs remote participants (visionOS)
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            let nearbyParticipants = participants.filter { participant in
                return participant.isNearbyWithLocalParticipant && participant.id != groupSession?.localParticipant.id
            }
            let remoteParticipants = participants.filter { participant in
                return !participant.isNearbyWithLocalParticipant && participant.id != groupSession?.localParticipant.id
            }
            let nearbyCount = nearbyParticipants.count
            let remoteCount = remoteParticipants.count
            print("Participants changed - Total: \(participants.count), Nearby: \(nearbyCount), Remote: \(remoteCount)")
        } else {
            let nearbyCount = 0
            let remoteCount = max(0, participants.count - 1)
            print("Participants changed - Total: \(participants.count), Nearby: \(nearbyCount), Remote: \(remoteCount)")
        }
        #endif

        // Derive a host, the participant with the smallest UUID acts as map provider
        if let session = groupSession {
            let all = participants
            let minID = all.map { $0.id }.min(by: { $0.uuidString < $1.uuidString })
            let localID = session.localParticipant.id
            let newIsHost = (minID == localID)
            if newIsHost != isHost {
                isHost = newIsHost
                print("Derived host status changed. isHost=\(isHost)")
            }
        }
        
        // Check if new participants joined
        let newParticipantJoined = participants.count > previousParticipantCount
        
        // Update counts after comparison
        previousParticipantCount = participantCount
        participantCount = participants.count
        
        // If we're the host and a new participant joined, send sync to sync everything
        if isHost && newParticipantJoined {
            Task {
                
                print("New participant joined, sending sync all models...")
                
                await sendSyncAllModels()
            }
    }
        
        recomputePlatformFlags()
    }
    
    
    #if os(visionOS)
    @available(visionOS 26.0, *)
    private func handleParticipantStatesUpdate(
        _ states: [Participant: SystemCoordinator.ParticipantState]
    ) {
        // Update participant states
        for (participant, state) in states {
            participantStates[participant.id] = state
            
            let locationInfo = participant.isNearbyWithLocalParticipant ? "nearby" : "remote"
            print("Participant \(participant.id) (\(locationInfo)) state updated")
            
        }
        
        // Notify delegate about spatial state changes
        Task {
            await delegate?.sharePlayCoordinator(self, didUpdateParticipantStates: participantStates)
        }
    }
    #endif
    
    
    private nonisolated func cleanup() {
        Task { @MainActor in

            for task in tasks {
                task.cancel()
            }
            
            tasks.removeAll()
            subscriptions.removeAll()
            groupSession?.leave()
            groupSession = nil
            messenger = nil
            unreliableMessenger = nil
            #if os(visionOS)
            systemCoordinator = nil
            currentModelsState.removeAll()
            participantStates.removeAll()
         
            #endif
            currentModelsState.removeAll()
            
            isConnected = false
            participantCount = 0
            localParticipantID = nil
            self.receivedAnyModelState = false
            self.cancelLateJoinResyncIfNeeded()
            
            self.capabilitiesByParticipant.removeAll()
            self.hasVisionParticipants = false
            
            
        }
    }
        
        deinit {
                cleanup()
            }
}


// MARK: - SharePlayCoordinator Delgate (Inbound)

/// Receives remote messages and events decoded by SharePlayCoordinator
@MainActor
protocol SharePlayCoordinatorDelegate: AnyObject {
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveAddModel message: AddModelMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveRemoveModel message: RemoveModelMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveTransformUpdate message: ModelTransformMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveModelSelection message: SelectModelMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveOwnershipChange message: OwnershipChangeMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveSyncAllModels message: SyncAllModelsMessage) async
    
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didReceiveAnchor message: AnchorMessage) async
    
        
    func sharePlayCoordinator(_ coordinator: SharePlayCoordinator, didUpdateParticipantStates states: [UUID: SystemCoordinator.ParticipantState]) async
}


// MARK: - Late join Resync

private extension SharePlayCoordinator {
    
    
    func startLateJoinResyncs() {
        cancelLateJoinResyncIfNeeded()
        receivedAnyModelState = false
        lateResyncTask = Task { [weak self] in
            guard let self = self else { return }
            
           
            // First nudge after ~1.2s
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            if !self.receivedAnyModelState {
                await self.sendRequestSync()
           
            }
            // Second nudge after another ~1.8s
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if Task.isCancelled { return }
            if !self.receivedAnyModelState {
                await self.sendRequestSync()
            }
        }
    }
    
    func cancelLateJoinResyncIfNeeded() {
        lateResyncTask?.cancel()
        lateResyncTask = nil
    }
    
    
    func recomputePlatformFlags() {
            guard let session = self.groupSession else {
                if hasVisionParticipants != false {
                    hasVisionParticipants = false
                    print("Platform flags updated: hasVisionParticipants= false (no session)")
                }
                return
            }
            let remotes = session.activeParticipants.subtracting([session.localParticipant])
            let hasVision = remotes.contains { p in
                if let caps = capabilitiesByParticipant[p.id] {
                    return caps.platform.lowercased() == "visionos"
                }
                return false
            }
            if hasVisionParticipants != hasVision {
                hasVisionParticipants = hasVision
                print("Platform flags updated: hasVisionParticipants=\(hasVision)")
            }
        }
}
