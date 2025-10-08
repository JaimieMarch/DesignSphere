import SwiftUI
import Combine
import RealityKit
#if canImport(ARKit)
import ARKit
#endif

@MainActor

/// Main controller for local and shareplay sessions
public final class CollaborativeSessionController: ObservableObject {
    
    /// Model descriptor for models that can be placed
    public struct ModelDescriptor: Identifiable, Hashable {
        public let id: String
        public let name: String
        fileprivate let type: ModelType

        fileprivate init(type: ModelType) {
            self.id = type.id
            self.name = type.displayName
            self.type = type
        }
    }
    

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var participantCount: Int = 0
    @Published public private(set) var availableModels: [ModelDescriptor] = []
    @Published public private(set) var placedModelSummaries: [String] = []
    @Published public private(set) var loadingProgress: Float = 0.0

    public var sessionName: String {
        get { arViewModel.sessionName }
        set { arViewModel.sessionName = newValue}
    }

    
    
    public var sessionID: String {
        
        get {arViewModel.sessionID }
        set { arViewModel.sessionID = newValue }
    }

    private let arViewModel: ARViewModel
    private let modelManager: ModelManager
    #if os(visionOS)
    public let immersiveSession: ARKitSession
    #endif
    private var cancellables: Set<AnyCancellable> = []

    /// Wires everything together
    public init() {
        let modelManager = ModelManager()
        let arViewModel = ARViewModel()
        arViewModel.modelManager = modelManager

        self.arViewModel = arViewModel
        self.modelManager = modelManager
        #if os(visionOS)
        self.immersiveSession = ARKitSession()
        #endif
        bindState()
        refreshAvailableModels()
    }

// MARK: - Session Helpers
    
    /// Start a local session
    public func startLocalSession(named name: String = "Local Session") {
        sessionName = name
        sessionID = UUID().uuidString
        Task {
            await preloadIfNeeded()
        }
    }
    
    

    /// Host shareplay session
    public func startSharePlayHosting(named name: String) {
        sessionName = name
        
        Task {
            await preloadIfNeeded()
            await arViewModel.startSharePlaySession(name: name)
        }
    }

    
    /// Join existing shareplay session
    public func joinSharePlaySession() {
        Task {
            await preloadIfNeeded()
            await arViewModel.joinSharePlaySession()
        }
    }

    
    /// Leave the current sharepaly session
    public func leaveSharePlaySession() {
        arViewModel.leaveSharePlaySession()
    }

    
    /// Clears everything in the session
    public func resetScene() {
        Task {
            await MainActor.run {
                self.modelManager.reset(broadcast: true)
            }
        }
    }
    

// MARK: - Model Helpers

    
    /// Add a model to the session
    public func addModel(_ descriptor: ModelDescriptor) {
        modelManager.loadModel(for: descriptor.type, arViewModel: arViewModel)
    }

    
    /// Remove all the models from the session
    public func removeAllModels() {
        modelManager.reset(broadcast: true)
    }

    
    /// Remove a single model from the session
    public func removeModel(named name: String) {
        if let model = modelManager.placedModels.first(where: { $0.modelType.displayName == name }) {
            modelManager.removeModel(model, broadcast: true)
        }
    }

    
    /// Makes sure that all the models and thumnails are preloaded
    public func preloadIfNeeded() async {
        if ModelCache.shared.preloadingComplete == false {
            await ModelCache.shared.preloadAllModels()
        }
        if ThumbnailCache.shared.preloadingComplete == false {
            await ThumbnailCache.shared.preloadAllThumbnails()
        }
        await arViewModel.loadModels()
    }

    
    
// MARK: - RealityView

    #if os(visionOS)
    @available(visionOS 26.0, *)
    
    /// Add the shared anchor and set up spatial coordination in shareplay
    public func makeRealityContent(_ content: RealityViewContent, session: ARKitSession) {
        if !content.entities.contains(arViewModel.sharedAnchorEntity) {
            content.add(arViewModel.sharedAnchorEntity)
        }
        arViewModel.sharedAnchorEntity.isEnabled = true

        
        // If we are in shareplay session, set up the spatial coordiantion for shared world anchor
        if let shareSession = arViewModel.sharePlayCoordinator?.session {
            
            
            if arViewModel.spatialCoordinator == nil {
                
                let coordinator = VisionOSSpatialCoordinator(session: shareSession)
                coordinator.onAnchorTransformUpdated = { [weak arViewModel] transform in
                    Task { @MainActor in
                        
                        arViewModel?.sharedAnchorEntity.transform = Transform(matrix: transform)
                    }
                }
                
                arViewModel.spatialCoordinator = coordinator
                Task {
                    try? await coordinator.configureWithARKitSession(session)
                    await coordinator.createSharedWorldAnchor()
                }
    }
        }
    }

    
    @available(visionOS 26.0, *)
    /// Keep the RealityView content in sync
    public func updateRealityContent(_ content: RealityViewContent) {
        if !content.entities.contains(arViewModel.sharedAnchorEntity) {
            content.add(arViewModel.sharedAnchorEntity)
        }

        
        for model in modelManager.placedModels {
            guard let entity = model.modelEntity else { continue }
            
            let existing = content.entities.first(where: { candidate in
                
                if let instance = candidate.components[InstanceIDComponent.self]?.id,
                   
                   let modelInstance = entity.components[InstanceIDComponent.self]?.id {
                    return instance == modelInstance
                }
                return candidate === entity
            })

            if existing == nil {
                if entity.parent == nil || entity.parent !== arViewModel.sharedAnchorEntity {
                    arViewModel.sharedAnchorEntity.addChild(entity)
                }
                content.add(entity)
    }
        }
        
        // Remove any entities from the content that are no longer part of the session
        content.entities.removeAll { entity in
            if entity === arViewModel.sharedAnchorEntity {
                return false
            }
            
            let managed = modelManager.placedModels.contains { model in
                guard let candidate = model.modelEntity else { return false }
                if let instance = entity.components[InstanceIDComponent.self]?.id,
                   let modelInstance = candidate.components[InstanceIDComponent.self]?.id {
                    return instance == modelInstance
                }
                return entity === candidate
            }
            if !managed {
                if entity.parent != nil {
                    entity.removeFromParent()
                }
                return true
    }
            return false
        }

        if let manipulationManager = arViewModel.manipulationManager {
            manipulationManager.setupManipulationEventHandlers(for: content)
        }
        modelManager.updatePlacedModels(arViewModel: arViewModel)
    }
    #endif

    
    
    public var sharedAnchorEntity: AnchorEntity {
        arViewModel.sharedAnchorEntity
    }

    
    
// MARK: - Private Helpers

    /// Bind ARViewModel and ModelManager state to controller's properties
    private func bindState() {
        arViewModel.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
            }
            .store(in: &cancellables)

        
        arViewModel.$participantCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.participantCount = count
            }
            .store(in: &cancellables)

        arViewModel.$loadingProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.loadingProgress = progress
            }
            .store(in: &cancellables)

        
        modelManager.$modelTypes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAvailableModels()
            }
            .store(in: &cancellables)

        
        modelManager.$placedModels
            .map { models in
                models.compactMap { model in
                    model.modelType.displayName
                }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$placedModelSummaries)
    }

    
    private func refreshAvailableModels() {
        availableModels = modelManager.modelTypes.map(ModelDescriptor.init)
    }
}


