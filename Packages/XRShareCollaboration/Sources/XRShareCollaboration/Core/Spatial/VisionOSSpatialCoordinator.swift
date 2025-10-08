//
// VisionOSSpatialCoordinator.swift
// XR Share
//
// Provides implementation for shared spatial alignment using World Anchors
//



#if os(visionOS)
import Foundation
import RealityKit
import GroupActivities
import SwiftUI
import ARKit


/// Coordinates spatial alignment in shareplay visionOS sessions using shared world anchors
@available(visionOS 26.0, *)
class VisionOSSpatialCoordinator {
    private var session: GroupSession<DemoActivity>
    private var rootEntity: Entity?
    private var realityViewContent: RealityViewContent?
    private var worldAnchorEntity: Entity?
    private(set) var currentAnchorID: UUID?
    private(set) var isAligned: Bool = false
    private var arKitSession: ARKitSession?
    private var worldTrackingProvider: Any?
    private var worldAnchors: [UUID: Any] = [:]

    var onAnchorTransformUpdated: ((simd_float4x4) -> Void)?
    
    var initialAnchorTransform: simd_float4x4?
    
    required init(session: GroupSession<DemoActivity>) {
        self.session = session
    }

    func configureSession(
        for entity: Entity,
        in realityViewContent: RealityViewContent
    ) async {
        self.rootEntity           = entity
        self.realityViewContent   = realityViewContent

        // Initialise world tracking and create/share the anchor.
        await setupWorldTracking()
        await createSharedWorldAnchor()

        print("visionOS: Configured spatial session with world anchors and nearby sharing")
    }
    
    // Configure with existing ARKit session
    @available(visionOS 26.0, *)
    func configureWithARKitSession(_ session: ARKitSession) async throws {
        self.arKitSession = session
        
        // Create provider
        let provider = WorldTrackingProvider()
        self.worldTrackingProvider = provider
        
        // Run the session with the provider
        try await session.run([provider])
        
        // Set up anchor update monitoring
        let anchorSeq = provider.anchorUpdates
        Task.detached { [weak self] in
            for await update in anchorSeq {
                await self?.handleWorldAnchorUpdate(update)
            }
        }
        
        print("visionOS: Configured ARKit session with world tracking provider")
    }
    
    
    
    func handleAnchorMessage(_ message: AnchorMessage) async {

        switch message.anchorType {
        case .worldAnchor:
            if let data = message.anchorData {
                await loadWorldAnchor(from: data, id: message.anchorID)
            }
        case .worldMap:
            
            // iOS ARWorldMap is not used on visionOS so we can ignore
            print("visionOS: Received worldMap anchor message; ignoring (not applicable)")
        }
    }
    
    
    
    func createAndShareAnchor() async -> AnchorMessage? {

        guard let anchorID = currentAnchorID,
              let typedAnchors = worldAnchors as? [UUID: WorldAnchor],
              let worldAnchor = typedAnchors[anchorID] else { return nil }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: worldAnchor,
                                                        requiringSecureCoding: false)
            return AnchorMessage(anchorID: anchorID,
                                 anchorType: .worldAnchor,
                                 anchorData: data)
        } catch {
            print("visionOS: Failed to archive world anchor – \(error)")
            return nil
}
    }
    
    
    
    @available(visionOS 26.0, *)
    func createAnchorAtTransform(_ transform: simd_float4x4) async throws -> UUID {
        guard let provider = worldTrackingProvider as? WorldTrackingProvider else {
            throw NSError(domain: "VisionOSSpatialCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "WorldTrackingProvider not available"])
        }
        
        let anchorID = UUID()
        
        // Create a world anchor at the specified transform
        let worldAnchor = WorldAnchor(
            originFromAnchorTransform: transform,
            sharedWithNearbyParticipants: true
        )
        
        // Add anchor to the provider
        try await provider.addAnchor(worldAnchor)
        
        // Store the anchor
        var typedDict = (worldAnchors as? [UUID: WorldAnchor]) ?? [:]
        typedDict[anchorID] = worldAnchor
        worldAnchors = typedDict
        
        print("visionOS: Created shared world anchor at custom transform with ID: \(anchorID)")
        
        return anchorID
    }
    
    
    
    // MARK: - Private Methods

    @available(visionOS 26.0, *)
    private func setupWorldTracking() async {
        
        // If we have an existing ARKit session, use its provider
        if let session = self.arKitSession,
           let provider = worldTrackingProvider as? WorldTrackingProvider {
            
            // Provider already set up in configureWithARKitSession
            print("visionOS: Using existing WorldTrackingProvider from ARKit session")
            
        } else {
            // Create provider and store as `Any`
            let provider = WorldTrackingProvider()
            self.worldTrackingProvider = provider
            print("visionOS: Created new WorldTrackingProvider")
        }
        
        guard let provider = worldTrackingProvider as? WorldTrackingProvider else { return }

        // Get the async sequence of anchor updates to observe shared anchors from nearby participants
        let anchorSeq = provider.anchorUpdates

        
        // Handle updates on a detached task
        Task.detached { [weak self] in
            for await update in anchorSeq {
                await self?.handleWorldAnchorUpdate(update)
            }
                }
    }
    
    @available(visionOS 26.0, *)
    func createSharedWorldAnchor() async {
        let anchorID = UUID()
        
        do {
            // Create a world anchor at the device's current position
        let seedTransform = initialAnchorTransform ?? matrix_identity_float4x4
        let worldAnchor = WorldAnchor(
            originFromAnchorTransform: seedTransform,
            sharedWithNearbyParticipants: true
        )
            
            // Add anchor to the provider
            if let provider = worldTrackingProvider as? WorldTrackingProvider {
                try await provider.addAnchor(worldAnchor)
                }
            
            // Store the anchor as any
            var typedDict = (worldAnchors as? [UUID: WorldAnchor]) ?? [:]
            typedDict[anchorID] = worldAnchor
            worldAnchors = typedDict
            
            currentAnchorID = anchorID
            isAligned = true
            
            // Create visual representation
            await MainActor.run {
                let anchorEntity = Entity()
                anchorEntity.name = "SharedWorldAnchor"
                anchorEntity.transform = Transform(matrix: worldAnchor.originFromAnchorTransform)
                
                if let rootEntity = rootEntity {
                    rootEntity.addChild(anchorEntity)
                    worldAnchorEntity = anchorEntity
                    }
                
                // Notify other participants so they can rebase their own shared anchor
                self.onAnchorTransformUpdated?(worldAnchor.originFromAnchorTransform)
            }
            
            print("visionOS: Created shared world anchor with ID: \(anchorID)")
            
        } catch {
            print("visionOS: Failed to create shared world anchor - \(error)")
        }
    }
    
    @available(visionOS 26.0, *)
    private func loadWorldAnchor(from data: Data?, id: UUID) async {
        
        // In visionOS, WorldAnchors are managed by the system so
        // we just need to track the anchor ID for reference
        currentAnchorID = id
        isAligned = true
        
        print("visionOS: Received world anchor reference \(id)")

        // The actual WorldAnchor will be provided by the system through
        // WorldTrackingProvider.anchorUpdates when it's available
    }
    
    @available(visionOS 26.0, *)
    private func handleWorldAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) async {
        switch update.event {
        case .added:
            let anchor = update.anchor
            print("visionOS: New world anchor detected: \(anchor.id)")
            print("  - Transform: \(anchor.originFromAnchorTransform)")
            print("  - Is from nearby participant: \(anchor.id != currentAnchorID)")
            
            // Store the anchor
            var typedDict = (worldAnchors as? [UUID: WorldAnchor]) ?? [:]
            typedDict[anchor.id] = anchor
            worldAnchors = typedDict
            
            // If this is a shared anchor from a nearby participant, use it as our reference
            if anchor.id != currentAnchorID {
                currentAnchorID = anchor.id
                isAligned = true
                
                // Update or create the anchor entity
                await MainActor.run {
                    if let existingEntity = worldAnchorEntity {
                        existingEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                    } else {
                        let anchorEntity = Entity()
                        anchorEntity.name = "SharedWorldAnchor"
                        anchorEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                        
                        if let rootEntity = rootEntity {
                            rootEntity.addChild(anchorEntity)
                            worldAnchorEntity = anchorEntity
                        }
                    }
                    
                    print("visionOS: Using shared world anchor from nearby participant")
                }
            }

        case .updated:
            let anchor = update.anchor
            print("visionOS: World anchor updated: \(anchor.id)")
            
            // Update stored anchor
            var typedDict = (worldAnchors as? [UUID: WorldAnchor]) ?? [:]
            typedDict[anchor.id] = anchor
            worldAnchors = typedDict
            
            // Update the transform if this is our current anchor
            if anchor.id == currentAnchorID {
                await MainActor.run {
                    worldAnchorEntity?.transform = Transform(matrix: anchor.originFromAnchorTransform)
                    self.onAnchorTransformUpdated?(anchor.originFromAnchorTransform)
                }
            }

        case .removed:
            print("visionOS: World anchor removed: \(update.anchor.id)")
            
            // Remove from storage
            var typedDict = (worldAnchors as? [UUID: WorldAnchor]) ?? [:]
            typedDict.removeValue(forKey: update.anchor.id)
            worldAnchors = typedDict
            
            // If this was our current anchor, mark as not aligned
            if update.anchor.id == currentAnchorID {
                isAligned = false
                currentAnchorID = nil
            }
        }
    }
    
    
    
    // MARK: - Public Accessors
    
    /// Get the world anchor entity that models should be attached to for spatial consistency
    @MainActor
    var sharedAnchorEntity: Entity? {
        return worldAnchorEntity
    }
    
    /// Check if spatial alignment is ready
    var isSpatiallyAligned: Bool {
        return isAligned && worldAnchorEntity != nil
    }
    
    /// Get the current world anchor ID
    var sharedAnchorID: UUID? {
        return currentAnchorID
    }

    // MARK: - Cleanup

    /// Cleanup all resources for session end
    @available(visionOS 26.0, *)
    func cleanup() async {
        print("VisionOSSpatialCoordinator: Cleaning up resources")

        // Remove all world anchors from the provider
        if let provider = worldTrackingProvider as? WorldTrackingProvider,
           let typedAnchors = worldAnchors as? [UUID: WorldAnchor] {
            for (_, anchor) in typedAnchors {
                try? await provider.removeAnchor(anchor)
            }
        }

        // Clear all state
        worldAnchors.removeAll()
        currentAnchorID = nil
        isAligned = false
        worldAnchorEntity = nil
        rootEntity = nil
        realityViewContent = nil
        onAnchorTransformUpdated = nil
        initialAnchorTransform = nil

        print("VisionOSSpatialCoordinator: Cleanup is completed")
    }
}
#endif

