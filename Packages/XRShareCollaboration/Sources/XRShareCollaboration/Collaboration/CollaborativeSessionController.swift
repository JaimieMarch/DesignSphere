import SwiftUI
import Combine
import RealityKit
#if os(visionOS)
import QuartzCore
#endif
#if canImport(ARKit)
import ARKit
#endif

@MainActor

/// Main controller for local and shareplay sessions
@available(visionOS 26.0, *)
public final class CollaborativeSessionController: ObservableObject {
    public enum ModelSource: String, CaseIterable, Hashable, Sendable {
        case all
        case presets
        case scans
        case imports
        case unknown

        public var label: String {
            switch self {
            case .all:
                return "All"
            case .presets:
                return "Presets"
            case .scans:
                return "Scans"
            case .imports:
                return "Imports"
            case .unknown:
                return "Other"
            }
        }
    }

    public enum ModelCategory: String, CaseIterable, Hashable, Sendable {
        case all
        case seating
        case beds
        case storage
        case lighting
        case decor
        case media
        case tables
        case unknown

        public var label: String {
            switch self {
            case .all:
                return "All"
            case .seating:
                return "Seating"
            case .beds:
                return "Beds"
            case .storage:
                return "Storage"
            case .lighting:
                return "Lighting"
            case .decor:
                return "Decor"
            case .media:
                return "Media"
            case .tables:
                return "Tables"
            case .unknown:
                return "Other"
            }
        }
    }

    public enum PreloadStrategy: Sendable {
        case minimal
        case aggressive
    }
    
    /// Model descriptor for models that can be placed
    public struct ModelDescriptor: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let type: ModelType
        public let source: ModelSource
        public let category: ModelCategory
        public let dateAdded: Date?

        fileprivate init(type: ModelType, source: ModelSource, category: ModelCategory, dateAdded: Date?) {
            self.id = type.id
            self.name = type.displayName
            self.type = type
            self.source = source
            self.category = category
            self.dateAdded = dateAdded
        }
    }

    /// Descriptor for models that have been placed in the scene
    public struct PlacedModelDescriptor: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let type: ModelType

        fileprivate init(id: UUID, name: String, type: ModelType) {
            self.id = id
            self.name = name
            self.type = type
        }
    }

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var participantCount: Int = 0
    @Published public private(set) var availableModels: [ModelDescriptor] = []
    @Published public private(set) var placedModelSummaries: [String] = []
    @Published public private(set) var placedModelDescriptors: [PlacedModelDescriptor] = []
    @Published public private(set) var loadingProgress: Float = 0.0
    @Published public private(set) var isFocusModeActive: Bool = false
    @Published public private(set) var focusRoomDimensions: FocusModeManager.FocusRoomDimensions = FocusModeManager.FocusRoomDimensions(width: 7.0, depth: 7.0, height: 3.2)
    @Published public private(set) var collisionMode: FurnitureCollisionMode = .warn
    @Published public private(set) var collisionWarningCount: Int = 0
    @Published public private(set) var canUndo: Bool = false
    @Published public private(set) var canRedo: Bool = false
    @Published public var selectedModelID: String? = nil
    @Published public var selectedModelInstanceID: UUID? = nil
    @Published public private(set) var expandedEditModelID: UUID? = nil
    private var activeEditModelInstanceID: UUID? = nil
    private var activeEditTransactionNeedsForceRecord: Bool = false

        
    public var selectedModelIDVar: ModelType? {
            modelManager.selectedModelID
        }

    public var selectedModelInstanceIDVar: UUID? {
            modelManager.selectedModelInstanceID
        }

    public var expandedEditModelInstanceIDVar: UUID? {
        expandedEditModelID
    }

    public var sessionName: String {
        get { arViewModel.sessionName }
        set { arViewModel.sessionName = newValue}
    }

    public var currentPlacedModels: [Model] {
            modelManager.placedModels
        }
    
    public var sessionID: String {
        get {arViewModel.sessionID }
        set { arViewModel.sessionID = newValue }
    }

    private let arViewModel: ARViewModel
    private let historyManager = SceneHistoryManager()
    public let modelManager: ModelManager
    #if os(visionOS)
    private weak var editMenuAttachmentEntity: Entity?
    public let immersiveSession: ARKitSession
    public let focusModeManager: FocusModeManager
    public let measurementManager: MeasurementManager
    public let selectionIndicatorManager: SelectionIndicatorManager
    private var worldTrackingProvider: WorldTrackingProvider?
    private var planeDetectionProvider: PlaneDetectionProvider?
    private var roomTrackingProvider: Any?
    private var isSessionRunning: Bool = false
    private var worldAnchorUpdatesTask: Task<Void, Never>?
    private var planeAnchorUpdatesTask: Task<Void, Never>?
    private var roomAnchorUpdatesTask: Task<Void, Never>?
    private var trackedWorldAnchors: [UUID: WorldAnchor] = [:]
    private var trackedPlaneAnchors: [UUID: PlaneAnchor] = [:]
    private var trackedRoomAnchors: [UUID: Any] = [:]
    private var roomPlaneIDsByRoomID: [UUID: Set<UUID>] = [:]
    private var currentProjectWorldAnchorID: UUID?
    private var currentRoomAnchorID: UUID?
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
        self.focusModeManager = FocusModeManager()
        self.measurementManager = MeasurementManager()
        self.selectionIndicatorManager = SelectionIndicatorManager()
        #endif
        arViewModel.preferredPlacementResolver = { [weak self] entity, modelType in
            await self?.resolvePreferredPlacement(for: entity, modelType: modelType)
        }
        arViewModel.spawnedModelPlacementPostProcessor = { [weak self] entity, modelType, instanceID in
            await self?.finalizeSpawnedModelPlacement(entity: entity, modelType: modelType, instanceID: instanceID) ?? false
        }
        modelManager.onModelDidAdd = { [weak self] model in
            self?.handleModelDidAdd(model)
        }
        modelManager.onModelWillRemove = { [weak self] model in
            self?.handleModelWillRemove(model)
        }
        bindState()
        refreshAvailableModels()
        #if os(visionOS)
        focusModeManager.setSharedAnchor(arViewModel.sharedAnchorEntity)
        measurementManager.setSharedAnchor(arViewModel.sharedAnchorEntity)
        measurementManager.setManipulationManager(arViewModel.manipulationManager)
        selectionIndicatorManager.setSharedAnchor(arViewModel.sharedAnchorEntity)
        if #available(visionOS 26.0, *),
           let manipulationManager = arViewModel.manipulationManager {
            manipulationManager.onManipulationWillBegin = { [weak self] entity, instanceID in
                self?.beginManipulationHistory(for: entity, instanceID: instanceID)
            }
            manipulationManager.onSceneUpdate = { [weak self] in
                guard let self else { return }
                EditAffordanceFactory.syncEditAffordances(
                    for: self.modelManager.placedModels,
                    relativeTo: self.arViewModel.sharedAnchorEntity,
                    selectedInstanceID: self.modelManager.selectedModelInstanceID,
                    expandedInstanceID: self.expandedEditModelID
                )
                self.selectionIndicatorManager.updateIndicatorPosition()
                self.updateEditMenuAttachmentPosition()
            }
            manipulationManager.onManipulationDidEnd = { [weak self] entity, instanceID in
                await self?.snapManipulatedEntity(entity, instanceID: instanceID)
            }
        }
        #endif
    }

// MARK: - Session Helpers
    
    /// Start a local session
    public func startLocalSession(named name: String = "Local Session") {
        sessionName = name
        sessionID = UUID().uuidString
    }

    #if os(visionOS)
    /// Start ARKit session with world tracking 
    public func startWorldTracking() async throws {
        guard !isSessionRunning else {
            #if DEBUG
            print("ARKit session already running")
            #endif
            return
        }

        guard WorldTrackingProvider.isSupported else {
            throw NSError(
                domain: "CollaborativeSessionController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "World tracking is not supported on this device."]
            )
        }

        let worldProvider = WorldTrackingProvider()
        let planeProvider = PlaneDetectionProvider(alignments: [.horizontal, .vertical])

        var providers: [any DataProvider] = [worldProvider, planeProvider]
        var requiredAuthorizations = Set(WorldTrackingProvider.requiredAuthorizations)
        requiredAuthorizations.formUnion(PlaneDetectionProvider.requiredAuthorizations)

        worldTrackingProvider = worldProvider
        planeDetectionProvider = planeProvider

        if #available(visionOS 2.0, *), RoomTrackingProvider.isSupported {
            let roomProvider = RoomTrackingProvider()
            roomTrackingProvider = roomProvider
            providers.append(roomProvider)
            requiredAuthorizations.formUnion(RoomTrackingProvider.requiredAuthorizations)
        } else {
            roomTrackingProvider = nil
        }

        let authorizationResults = await immersiveSession.requestAuthorization(for: Array(requiredAuthorizations))
        for authorization in requiredAuthorizations where authorizationResults[authorization] != .allowed {
            throw NSError(
                domain: "CollaborativeSessionController",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Missing ARKit authorization: \(authorization.description)"]
            )
        }

        // Run the session with world tracking
        try await immersiveSession.run(providers)
        isSessionRunning = true
        observeWorldAnchors(using: worldProvider)
        observePlaneAnchors(using: planeProvider)
        await refreshTrackedWorldAnchors(using: worldProvider)
        await refreshTrackedPlaneAnchors(using: planeProvider)
        if #available(visionOS 2.0, *),
           let roomProvider = roomTrackingProvider as? RoomTrackingProvider {
            observeRoomAnchors(using: roomProvider)
            await refreshTrackedRoomAnchors(using: roomProvider)
        }

        #if DEBUG
        print("Started ARKit session with world, plane, and room tracking")
        #endif
    }

    /// Stop the ARKit session
    public func stopWorldTracking() async {
        guard isSessionRunning else { return }

        worldAnchorUpdatesTask?.cancel()
        planeAnchorUpdatesTask?.cancel()
        roomAnchorUpdatesTask?.cancel()
        worldAnchorUpdatesTask = nil
        planeAnchorUpdatesTask = nil
        roomAnchorUpdatesTask = nil
        immersiveSession.stop()
        worldTrackingProvider = nil
        planeDetectionProvider = nil
        roomTrackingProvider = nil
        isSessionRunning = false
        trackedWorldAnchors.removeAll()
        trackedPlaneAnchors.removeAll()
        trackedRoomAnchors.removeAll()
        roomPlaneIDsByRoomID.removeAll()
        currentProjectWorldAnchorID = nil
        currentRoomAnchorID = nil

        #if DEBUG
        print("Stopped ARKit session and WorldTracking")
        #endif
    }

    public func createPersistentWorldAnchor() async throws -> UUID {
        guard let provider = worldTrackingProvider else {
            throw NSError(
                domain: "CollaborativeSessionController",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "World tracking has not started yet."]
            )
        }

        if let currentID = currentProjectWorldAnchorID,
           await restorePersistentWorldAnchor(id: currentID) {
            return currentID
        }

        let worldAnchor = WorldAnchor(originFromAnchorTransform: arViewModel.sharedAnchorEntity.transform.matrix)
        try await provider.addAnchor(worldAnchor)
        trackedWorldAnchors[worldAnchor.id] = worldAnchor
        currentProjectWorldAnchorID = worldAnchor.id

        #if DEBUG
        print("Created persistent world anchor: \(worldAnchor.id)")
        #endif

        return worldAnchor.id
    }

    public func restorePersistentWorldAnchor(id: UUID) async -> Bool {
        guard let provider = worldTrackingProvider else { return false }
        guard let worldAnchor = await resolveWorldAnchor(id: id, using: provider) else {
            #if DEBUG
            print("World anchor \(id) is not currently available")
            #endif
            return false
        }

        trackedWorldAnchors[worldAnchor.id] = worldAnchor
        currentProjectWorldAnchorID = worldAnchor.id
        applyWorldAnchorTransform(worldAnchor.originFromAnchorTransform)

        #if DEBUG
        print("Restored persistent world anchor: \(worldAnchor.id)")
        #endif

        return true
    }

    public func clearPersistentWorldAnchor(resetSharedAnchorTransform: Bool = false) {
        currentProjectWorldAnchorID = nil
        if resetSharedAnchorTransform {
            arViewModel.sharedAnchorEntity.transform = Transform(
                translation: SIMD3<Float>(0, 1.2, -1.2)
            )
        }
    }

    public func removePersistentWorldAnchor(id: UUID) async {
        guard let provider = worldTrackingProvider else {
            trackedWorldAnchors.removeValue(forKey: id)
            if currentProjectWorldAnchorID == id {
                currentProjectWorldAnchorID = nil
            }
            return
        }

        if let worldAnchor = await resolveWorldAnchor(id: id, using: provider) {
            do {
                try await provider.removeAnchor(worldAnchor)
            } catch {
                #if DEBUG
                print("Failed to remove world anchor \(id): \(error)")
                #endif
            }
        }

        trackedWorldAnchors.removeValue(forKey: id)
        if currentProjectWorldAnchorID == id {
            currentProjectWorldAnchorID = nil
        }
    }
    #endif

// MARK: - Focus Mode

    /// Surrounds the user with a neutral virtual room that occludes the real world
    public func enterFocusMode() {
        #if os(visionOS)
        focusModeManager.enterFocusMode()
        #endif
    }

    /// Restores passthrough viewing and removes the focus environment.
    public func exitFocusMode() {
        #if os(visionOS)
        focusModeManager.exitFocusMode()
        #endif
    }

    /// Update the room dimensions (meters). Clamped to reasonable bounds for comfort.
    public func updateFocusRoomDimensions(width: Float, depth: Float, height: Float) {
        #if os(visionOS)
        focusModeManager.updateFocusRoomDimensions(width: width, depth: depth, height: height)
        #endif
    }

    /// Manually recenter the focus mode room around the user's current position.
    public func recenterFocusMode() {
        #if os(visionOS)
        focusModeManager.recenterFocusMode()
        #endif
    }

// MARK: - Collision

    public func setCollisionMode(_ mode: FurnitureCollisionMode) {
        collisionMode = mode
        if mode == .off {
            collisionWarningCount = 0
        } else {
            collisionWarningCount = countCurrentCollisions()
        }
    }

// MARK: - Selection Indicator

    /// Update the selection indicator to show the currently selected model
    public func updateSelectionIndicator() {
        #if os(visionOS)
        guard let selectedID = modelManager.selectedModelInstanceID else {
            selectionIndicatorManager.hideSelectionIndicator()
            return
        }

        // Find the selected model entity
        if let selectedModel = modelManager.placedModels.first(where: { $0.id == selectedID }),
           let entity = selectedModel.modelEntity {
            selectionIndicatorManager.showSelectionIndicator(for: entity)
        } else {
            selectionIndicatorManager.hideSelectionIndicator()
        }
        #endif
    }

    /// Request that the editor opens for the given model instance.
    public func requestEditModel(instanceID: UUID) {
        guard modelManager.placedModels.contains(where: { $0.id == instanceID }) else { return }

        if expandedEditModelID == instanceID {
            collapseEditMenu()
            return
        }

        commitSelectedModelEditTransaction()
        modelManager.selectModel(instanceID: instanceID)
        expandedEditModelID = instanceID
    }

    public func collapseEditMenu() {
        commitSelectedModelEditTransaction()
        expandedEditModelID = nil
        editMenuAttachmentEntity?.removeFromParent()
    }

    /// Handle a spatial tap in the immersive scene.
    public func handleSpatialTap(on entity: Entity) {
        #if os(visionOS)
        if let affordanceEntity = entity.ancestorOrSelf(with: EditAffordanceComponent.self),
           let affordance = affordanceEntity.components[EditAffordanceComponent.self] {
            requestEditModel(instanceID: affordance.instanceID)
            return
        }

        if measurementManager.handleSpatialTap(on: entity, modelsByID: modelManager.modelDict) {
            return
        }

        if #available(visionOS 26.0, *),
           let modelEntity = entity.ancestorOrSelf(with: InstanceIDComponent.self) {
            commitSelectedModelEditTransaction()
            expandedEditModelID = nil
            modelManager.selectModel(entity: modelEntity)
        }
        #endif
    }

    /// Handle a tap that missed all entities in the immersive scene.
    public func handleEmptySpatialTap() {
        if measurementManager.isAwaitingSelection {
            measurementManager.cancelDistanceSelection()
            return
        }
        deselectModel()
    }

    /// Deselect the currently selected model
    public func deselectModel() {
        commitSelectedModelEditTransaction()
        expandedEditModelID = nil
        modelManager.deselectModel()
    }

    public func returnSelectedModel() -> Model? {
        guard let instanceID = modelManager.selectedModelInstanceID else { return nil }
        return modelManager.placedModels.first { $0.id == instanceID }
    }

    private func handleModelDidAdd(_ model: Model) {
        guard !historyManager.isApplyingHistory,
              !historyManager.isRecordingSuspended,
              let snapshot = snapshot(for: model) else { return }
        historyManager.recordAdd(snapshot)
    }

    private func handleModelWillRemove(_ model: Model) {
        guard !historyManager.isApplyingHistory,
              !historyManager.isRecordingSuspended,
              let snapshot = snapshot(for: model) else { return }
        if expandedEditModelID == snapshot.instanceID {
            expandedEditModelID = nil
            editMenuAttachmentEntity?.removeFromParent()
        }
        if activeEditModelInstanceID == snapshot.instanceID {
            activeEditModelInstanceID = nil
            activeEditTransactionNeedsForceRecord = false
        }
        historyManager.recordRemove(snapshot)
    }

    private func beginManipulationHistory(for entity: Entity, instanceID: UUID) {
        guard !historyManager.isApplyingHistory,
              let model = modelManager.modelDict[instanceID],
              let snapshot = snapshot(for: model) else { return }
        historyManager.beginTransactionIfNeeded(with: snapshot)
    }

    private enum HistoryDirection {
        case undo
        case redo
    }

    private struct EntityPoseState {
        let localPosition: SIMD3<Float>
        let worldOrientation: simd_quatf
        let snapState: SnapStateComponent?
    }

    private func applyHistoryEntry(
        _ entry: SceneHistoryEntry,
        direction: HistoryDirection
    ) async throws {
        switch (direction, entry) {
        case (.undo, .add(let snapshot)):
            removeModelFromHistory(instanceID: snapshot.instanceID)
        case (.undo, .remove(let snapshot)):
            try await restoreModelFromHistory(snapshot)
        case (.undo, .update(let before, _)):
            try await applySnapshotFromHistory(before)
        case (.redo, .add(let snapshot)):
            try await restoreModelFromHistory(snapshot)
        case (.redo, .remove(let snapshot)):
            removeModelFromHistory(instanceID: snapshot.instanceID)
        case (.redo, .update(_, let after)):
            try await applySnapshotFromHistory(after)
        }
    }

    private func snapshot(for model: Model) -> ModelSnapshot? {
        guard let entity = model.modelEntity else { return nil }
        guard let modelComponent = entity.components[ModelComponent.self] else { return nil }

        let materialType = entity.components[MaterialTypeComponent.self]?.materialType
        let originalBounds = entity.components[OriginalBoundsComponent.self]?.originalSize
        let snapState = entity.components[SnapStateComponent.self]

        return ModelSnapshot(
            instanceID: model.id,
            modelType: model.modelType,
            position: entity.position(relativeTo: sharedAnchorEntity),
            rotation: entity.orientation(relativeTo: sharedAnchorEntity),
            scale: entity.scale(relativeTo: sharedAnchorEntity),
            materials: modelComponent.materials,
            materialType: materialType,
            originalBounds: originalBounds,
            snapState: snapState
        )
    }

    private func restoreModelFromHistory(_ snapshot: ModelSnapshot) async throws {
        guard modelManager.modelDict[snapshot.instanceID] == nil else {
            try await applySnapshotFromHistory(snapshot)
            return
        }

        guard let model = await loadModelAtPosition(
            modelType: snapshot.modelType,
            instanceID: snapshot.instanceID,
            position: snapshot.position,
            rotation: snapshot.rotation,
            scale: snapshot.scale
        ) else {
            throw NSError(
                domain: "CollaborativeSessionController",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Failed to restore model \(snapshot.modelType.displayName)"]
            )
        }

        applySnapshotComponents(snapshot, to: model)
        modelManager.selectModel(instanceID: snapshot.instanceID)
    }

    private func applySnapshotFromHistory(_ snapshot: ModelSnapshot) async throws {
        if let model = modelManager.modelDict[snapshot.instanceID] {
            applySnapshotComponents(snapshot, to: model)
            modelManager.selectModel(instanceID: snapshot.instanceID)
            return
        }

        try await restoreModelFromHistory(snapshot)
    }

    private func applySnapshotComponents(_ snapshot: ModelSnapshot, to model: Model) {
        guard let entity = model.modelEntity else { return }

        entity.setPosition(snapshot.position, relativeTo: sharedAnchorEntity)
        entity.setOrientation(snapshot.rotation, relativeTo: sharedAnchorEntity)
        entity.setScale(snapshot.scale, relativeTo: sharedAnchorEntity)

        if var modelComponent = entity.components[ModelComponent.self] {
            modelComponent.materials = snapshot.materials
            entity.components.set(modelComponent)
        }

        if let materialType = snapshot.materialType {
            entity.components.set(MaterialTypeComponent(materialType: materialType))
        } else {
            entity.components.remove(MaterialTypeComponent.self)
        }

        if let originalBounds = snapshot.originalBounds {
            entity.components.set(OriginalBoundsComponent(originalSize: originalBounds))
        } else {
            entity.components.remove(OriginalBoundsComponent.self)
        }

        if let snapState = snapshot.snapState {
            entity.components.set(snapState)
        } else {
            entity.components.remove(SnapStateComponent.self)
        }

        #if os(visionOS)
        selectionIndicatorManager.updateIndicatorPosition()
        #endif
    }

    private func removeModelFromHistory(instanceID: UUID) {
        guard let model = modelManager.modelDict[instanceID] else { return }
        historyManager.discardTransaction(for: instanceID)
        if expandedEditModelID == instanceID {
            expandedEditModelID = nil
            editMenuAttachmentEntity?.removeFromParent()
        }
        if activeEditModelInstanceID == instanceID {
            activeEditModelInstanceID = nil
            activeEditTransactionNeedsForceRecord = false
        }
        modelManager.removeModel(model, broadcast: false)
    }
    
    
//
//    /// Host shareplay session
//    public func startSharePlayHosting(named name: String) {
//        sessionName = name
//        
//        Task {
//            await preloadIfNeeded()
//            await arViewModel.startSharePlaySession(name: name)
//        }
//    }

//    
//    /// Join existing shareplay session
//    public func joinSharePlaySession() {
//        Task {
//            await preloadIfNeeded()
//           // await arViewModel.joinSharePlaySession()
//        }
//    }
    
    

//    /// Host shareplay session
//    public func startSharePlayHosting(named name: String) {
//        sessionName = name
//        
//        Task {
//            await preloadIfNeeded()
//            //await arViewModel.startSharePlaySession(name: name)
//        }
//    }
//
//    
//    /// Join existing shareplay session
//    public func joinSharePlaySession() {
//        Task {
//            await preloadIfNeeded()
//            //await arViewModel.joinSharePlaySession()
//        }
//    }
//
//    
//    /// Leave the current sharepaly session
//    public func leaveSharePlaySession() {
//        //arViewModel.leaveSharePlaySession()
//    }

    
    /// Clears everything in the session
    public func resetScene() {
        Task { await removeAllModels() }
    }
    

// MARK: - Model Helpers

    
    /// Add a model to the session
    public func addModel(_ descriptor: ModelDescriptor) {
        modelManager.loadModel(for: descriptor.type, arViewModel: arViewModel)
    }

    /// Load a model at specific position, rotation, and scale
    public func loadModelAtPosition(
        modelType: ModelType,
        instanceID: UUID,
        position: SIMD3<Float>,
        rotation: simd_quatf,
        scale: SIMD3<Float>,
        notifyDidAdd: Bool = true
    ) async -> Model? {
        let model = await Model.load(modelType: modelType, arViewModel: arViewModel)

        guard let entity = model.modelEntity else {
            #if DEBUG
            print("Warning: Failed to load entity for '\(modelType.displayName)'")
            #endif
            return nil
        }

        // Configure interactivity (gestures, physics, collision, etc.)
        modelManager.configureInteractivity(for: entity, arViewModel: arViewModel)
        model.id = instanceID

        // Set the instance ID for each individual model
        entity.components.set(InstanceIDComponent(id: instanceID.uuidString))

        // Add to the shared anchor
        sharedAnchorEntity.addChild(entity)

        // Apply the saved transform relative to shared anchor
        // Apple natively uses SIMD to store vector data for 3d entities
        // see: realitykit entity definition from developer docs
        entity.setPosition(position, relativeTo: sharedAnchorEntity)
        entity.setOrientation(rotation, relativeTo: sharedAnchorEntity)
        entity.setScale(scale, relativeTo: sharedAnchorEntity)
        entity.components.set(CollisionStateComponent(lastValidPosition: position))

        // Add to model manager
        modelManager.placedModels.append(model)
        modelManager.modelDict[model.id] = model
        if notifyDidAdd {
            modelManager.onModelDidAdd?(model)
        }

        return model
    }


    /// Remove all the models from the session
    public func removeAllModels() async {
        await MainActor.run {
            self.beginHistoryRecordingSuppression()
            defer {
                self.endHistoryRecordingSuppression()
            }

            self.activeEditModelInstanceID = nil
            self.activeEditTransactionNeedsForceRecord = false
            self.expandedEditModelID = nil
            self.editMenuAttachmentEntity?.removeFromParent()
            self.measurementManager.reset()
            self.historyManager.clear()
            self.modelManager.reset(broadcast: true)
        }
    }

    public func beginHistoryRecordingSuppression() {
        historyManager.beginRecordingSuppression()
    }

    public func endHistoryRecordingSuppression() {
        historyManager.endRecordingSuppression()
    }

    
    /// Remove a single model from the session
    public func removeModel(named name: String) {
        commitSelectedModelEditTransaction()
        if let model = modelManager.placedModels.first(where: { $0.modelType.displayName == name }) {
            modelManager.removeModel(model, broadcast: true)
        }
    }
    
    public func removeModelById(withInstanceID id: UUID) {
        commitSelectedModelEditTransaction()
        if let model = modelManager.placedModels.first(where: { $0.id == id }) {
            modelManager.removeModel(model, broadcast: true)
        }
    }

    public func clearHistory() {
        activeEditModelInstanceID = nil
        activeEditTransactionNeedsForceRecord = false
        expandedEditModelID = nil
        editMenuAttachmentEntity?.removeFromParent()
        historyManager.clear()
    }

    public func undo() {
        guard let entry = historyManager.prepareUndo() else { return }

        Task { @MainActor in
            do {
                try await applyHistoryEntry(entry, direction: .undo)
                historyManager.finishUndo(entry)
            } catch {
                historyManager.cancelUndo(entry)
                #if DEBUG
                print("Undo failed: \(error)")
                #endif
            }
        }
    }

    public func redo() {
        guard let entry = historyManager.prepareRedo() else { return }

        Task { @MainActor in
            do {
                try await applyHistoryEntry(entry, direction: .redo)
                historyManager.finishRedo(entry)
            } catch {
                historyManager.cancelRedo(entry)
                #if DEBUG
                print("Redo failed: \(error)")
                #endif
            }
        }
    }

    public func beginSelectedModelEditTransactionIfNeeded() {
        guard let model = returnSelectedModel(),
              let snapshot = snapshot(for: model) else { return }
        if let activeEditModelInstanceID,
           activeEditModelInstanceID != model.id {
            commitSelectedModelEditTransaction()
        }
        guard activeEditModelInstanceID != model.id else { return }
        historyManager.beginTransactionIfNeeded(with: snapshot)
        activeEditModelInstanceID = model.id
        activeEditTransactionNeedsForceRecord = false
    }

    public func commitSelectedModelEditTransaction() {
        guard let instanceID = activeEditModelInstanceID else { return }
        guard let model = modelManager.modelDict[instanceID],
              let snapshot = snapshot(for: model) else {
            historyManager.discardTransaction(for: instanceID)
            activeEditModelInstanceID = nil
            activeEditTransactionNeedsForceRecord = false
            return
        }

        historyManager.commitTransaction(
            for: instanceID,
            after: snapshot,
            forceRecord: activeEditTransactionNeedsForceRecord
        )
        activeEditModelInstanceID = nil
        activeEditTransactionNeedsForceRecord = false
    }

    public func discardSelectedModelEditTransaction() {
        guard let instanceID = activeEditModelInstanceID else { return }
        historyManager.discardTransaction(for: instanceID)
        activeEditModelInstanceID = nil
        activeEditTransactionNeedsForceRecord = false
    }

    public func updateSelectedModelScale(_ scale: SIMD3<Float>) {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }
        beginSelectedModelEditTransactionIfNeeded()
        entity.scale = scale
    }

    public func updateSelectedModelPosition(_ position: SIMD3<Float>) {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }
        beginSelectedModelEditTransactionIfNeeded()
        entity.position = position
        #if os(visionOS)
        selectionIndicatorManager.updateIndicatorPosition()
        #endif
    }

    public func applyMaterialToSelectedModel(_ material: any RealityKit.Material, materialType: String?) {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }
        beginSelectedModelEditTransactionIfNeeded()
        activeEditTransactionNeedsForceRecord = true
        entity.replaceAndStoreOldMaterials(material: material)
        if let materialType {
            entity.components.set(MaterialTypeComponent(materialType: materialType))
        } else {
            entity.components.remove(MaterialTypeComponent.self)
        }
    }

    public func restoreSelectedModelMaterials() {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }
        beginSelectedModelEditTransactionIfNeeded()
        activeEditTransactionNeedsForceRecord = true
        entity.restoreOriginalMaterials()
        entity.components.remove(MaterialTypeComponent.self)
    }

    public func rotateSelectedModelByQuarterTurn(clockwise: Bool = true) {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }

        beginSelectedModelEditTransactionIfNeeded()
        let angle: Float = clockwise ? -.pi / 2 : .pi / 2
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        entity.orientation = rotation * entity.orientation
        #if os(visionOS)
        finalizeDiscreteTransformEdit(for: model, entity: entity)
        #else
        commitSelectedModelEditTransaction()
        #endif
    }

    public func nudgeSelectedModel(by offset: SIMD3<Float>) {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity else { return }

        beginSelectedModelEditTransactionIfNeeded()
        entity.position += offset
        #if os(visionOS)
        finalizeDiscreteTransformEdit(for: model, entity: entity)
        #else
        commitSelectedModelEditTransaction()
        #endif
    }

    public func duplicateSelectedModel() {
        guard let model = returnSelectedModel(),
              let entity = model.modelEntity,
              let snapshot = snapshot(for: model) else { return }

        commitSelectedModelEditTransaction()
        let duplicateID = UUID()
        let duplicatePosition = duplicatedPosition(for: entity)

        Task { @MainActor in
            guard let duplicatedModel = await self.loadModelAtPosition(
                modelType: snapshot.modelType,
                instanceID: duplicateID,
                position: duplicatePosition,
                rotation: snapshot.rotation,
                scale: snapshot.scale,
                notifyDidAdd: false
            ) else {
                return
            }

            self.applyDuplicatedVisualState(from: snapshot, to: duplicatedModel)
            self.modelManager.selectModel(instanceID: duplicateID)
            self.expandedEditModelID = duplicateID

            if let duplicateEntity = duplicatedModel.modelEntity {
                #if os(visionOS)
                await self.snapManipulatedEntity(duplicateEntity, instanceID: duplicateID)
                #else
                self.commitSelectedModelEditTransaction()
                #endif
            }

            if let addSnapshot = self.snapshot(for: duplicatedModel) {
                self.historyManager.recordAdd(addSnapshot)
            }
        }
    }

    public func syncEditMenuAttachment(_ attachment: Entity?) {
        if editMenuAttachmentEntity !== attachment {
            editMenuAttachmentEntity?.removeFromParent()
            editMenuAttachmentEntity = attachment
        }

        guard let attachment else { return }

        if #available(visionOS 2.0, *),
           attachment.components[BillboardComponent.self] == nil {
            var billboard = BillboardComponent()
            billboard.blendFactor = 1.0
            attachment.components.set(billboard)
        }

        attachment.scale = SIMD3<Float>(repeating: 0.001)
        updateEditMenuAttachmentPosition()
    }

    
    /// Makes sure that models/thumbnails are available without stalling first render.
    public func preloadIfNeeded(strategy: PreloadStrategy = .minimal) async {
        await arViewModel.loadModels()

        switch strategy {
        case .minimal:
            let previewModels = Array(modelManager.modelTypes.prefix(8))
            await ThumbnailCache.shared.preloadThumbnails(for: previewModels)
        case .aggressive:
            if ModelCache.shared.preloadingComplete == false {
                await ModelCache.shared.preloadAllModels()
            }
            if ThumbnailCache.shared.preloadingComplete == false {
                await ThumbnailCache.shared.preloadAllThumbnails()
            }
        }
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
//        if let shareSession = arViewModel.sharePlayCoordinator?.session {
//            
//            
//            if arViewModel.spatialCoordinator == nil {
//                
//                let coordinator = VisionOSSpatialCoordinator(session: shareSession)
//                coordinator.onAnchorTransformUpdated = { [weak arViewModel] transform in
//                    Task { @MainActor in
//                        
//                        arViewModel?.sharedAnchorEntity.transform = Transform(matrix: transform)
//                    }
//                }
//                
//                arViewModel.spatialCoordinator = coordinator
//                Task {
//                    try? await coordinator.configureWithARKitSession(session)
//                    await coordinator.createSharedWorldAnchor()
//                }
//    }
//        }
    }

    
    @available(visionOS 26.0, *)
    /// Keep the RealityView content in sync
    public func updateRealityContent(_ content: RealityViewContent) {
        if !content.entities.contains(arViewModel.sharedAnchorEntity) {
            content.add(arViewModel.sharedAnchorEntity)
        }

        
        for model in modelManager.placedModels {
            guard let entity = model.modelEntity else { continue }
            if entity.parent !== arViewModel.sharedAnchorEntity {
                arViewModel.sharedAnchorEntity.addChild(entity)
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
        if #available(visionOS 26.0, *) {
            EditAffordanceFactory.syncEditAffordances(
                for: modelManager.placedModels,
                relativeTo: arViewModel.sharedAnchorEntity,
                selectedInstanceID: modelManager.selectedModelInstanceID,
                expandedInstanceID: expandedEditModelID
            )
        }
        updateEditMenuAttachmentPosition()
        selectionIndicatorManager.updateIndicatorPosition()
        measurementManager.setManipulationManager(arViewModel.manipulationManager)
        measurementManager.syncScene(with: modelManager.placedModels)
        collisionWarningCount = countCurrentCollisions()
        modelManager.updatePlacedModels(arViewModel: arViewModel)
    }
    #endif

    
    
    public var sharedAnchorEntity: AnchorEntity {
        arViewModel.sharedAnchorEntity
    }

    public var worldTrackingDeviceTransform: simd_float4x4? {
        #if os(visionOS)
        return worldTrackingProvider?
            .queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?
            .originFromAnchorTransform
        #else
        return nil
        #endif
    }

    #if os(visionOS)
    private func observeWorldAnchors(using provider: WorldTrackingProvider) {
        worldAnchorUpdatesTask?.cancel()
        worldAnchorUpdatesTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                await self?.handleWorldAnchorUpdate(update)
            }
        }
    }

    private func observePlaneAnchors(using provider: PlaneDetectionProvider) {
        planeAnchorUpdatesTask?.cancel()
        planeAnchorUpdatesTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                await self?.handlePlaneAnchorUpdate(update)
            }
        }
    }

    private func observeRoomAnchors(using provider: RoomTrackingProvider) {
        roomAnchorUpdatesTask?.cancel()
        roomAnchorUpdatesTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                await self?.handleRoomAnchorUpdate(update)
            }
        }
    }

    private func refreshTrackedWorldAnchors(using provider: WorldTrackingProvider) async {
        guard #available(visionOS 2.0, *),
              let anchors = await provider.allAnchors else { return }
        trackedWorldAnchors = Dictionary(uniqueKeysWithValues: anchors.map { ($0.id, $0) })

        if let currentID = currentProjectWorldAnchorID,
           let currentAnchor = trackedWorldAnchors[currentID] {
            applyWorldAnchorTransform(currentAnchor.originFromAnchorTransform)
        }
    }

    private func refreshTrackedPlaneAnchors(using provider: PlaneDetectionProvider) async {
        guard #available(visionOS 2.0, *) else { return }
        trackedPlaneAnchors = Dictionary(uniqueKeysWithValues: provider.allAnchors.map { ($0.id, $0) })
    }

    private func refreshTrackedRoomAnchors(using provider: RoomTrackingProvider) async {
        trackedRoomAnchors = Dictionary(
            uniqueKeysWithValues: provider.allAnchors.map { ($0.id, $0) }
        )
        roomPlaneIDsByRoomID = Dictionary(
            uniqueKeysWithValues: provider.allAnchors.map { ($0.id, Set($0.planeAnchorIDs)) }
        )
        if let currentRoom = provider.allAnchors.first(where: { $0.isCurrentRoom }) {
            currentRoomAnchorID = currentRoom.id
        }
    }

    private func resolveWorldAnchor(id: UUID, using provider: WorldTrackingProvider) async -> WorldAnchor? {
        if let anchor = trackedWorldAnchors[id] {
            return anchor
        }

        guard #available(visionOS 2.0, *),
              let anchors = await provider.allAnchors else { return nil }
        if let anchor = anchors.first(where: { $0.id == id }) {
            trackedWorldAnchors[anchor.id] = anchor
            return anchor
        }
        return nil
    }

    private func handleWorldAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) {
        switch update.event {
        case .added, .updated:
            trackedWorldAnchors[update.anchor.id] = update.anchor

            if update.anchor.id == currentProjectWorldAnchorID {
                applyWorldAnchorTransform(update.anchor.originFromAnchorTransform)
            }
        case .removed:
            trackedWorldAnchors.removeValue(forKey: update.anchor.id)

            if update.anchor.id == currentProjectWorldAnchorID {
                currentProjectWorldAnchorID = nil
            }
        }
    }

    private func handlePlaneAnchorUpdate(_ update: AnchorUpdate<PlaneAnchor>) {
        switch update.event {
        case .added, .updated:
            trackedPlaneAnchors[update.anchor.id] = update.anchor
        case .removed:
            trackedPlaneAnchors.removeValue(forKey: update.anchor.id)
        }
    }

    private func handleRoomAnchorUpdate(_ update: AnchorUpdate<RoomAnchor>) {
        switch update.event {
        case .added, .updated:
            trackedRoomAnchors[update.anchor.id] = update.anchor
            roomPlaneIDsByRoomID[update.anchor.id] = Set(update.anchor.planeAnchorIDs)
            if update.anchor.isCurrentRoom {
                currentRoomAnchorID = update.anchor.id
            }
        case .removed:
            trackedRoomAnchors.removeValue(forKey: update.anchor.id)
            roomPlaneIDsByRoomID.removeValue(forKey: update.anchor.id)
            if currentRoomAnchorID == update.anchor.id {
                currentRoomAnchorID = nil
            }
        }
    }

    private func applyWorldAnchorTransform(_ transform: simd_float4x4) {
        arViewModel.sharedAnchorEntity.transform = Transform(matrix: transform)
        arViewModel.sharedAnchorEntity.isEnabled = true
    }

    private func resolvePreferredPlacement(for entity: ModelEntity, modelType: ModelType) async -> SurfacePlacement? {
        guard let worldTrackingProvider else { return nil }
        let deviceAnchor = worldTrackingProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        guard let deviceAnchor, deviceAnchor.isTracked else { return nil }

        if #available(visionOS 2.0, *),
           let currentRoomAnchor {
            if let placement = RoomMeshPlacementEngine.placementForSpawn(
                entity: entity,
                modelType: modelType,
                sharedAnchor: arViewModel.sharedAnchorEntity,
                deviceTransform: deviceAnchor.originFromAnchorTransform,
                roomAnchor: currentRoomAnchor
            ) {
                return placement
            }
        }

        return SurfaceSnappingEngine.placementForSpawn(
            entity: entity,
            modelType: modelType,
            sharedAnchor: arViewModel.sharedAnchorEntity,
            deviceTransform: deviceAnchor.originFromAnchorTransform,
            planeAnchors: Array(trackedPlaneAnchors.values),
            allowedPlaneIDs: currentRoomPlaneIDs
        )
    }

    private func finalizeSpawnedModelPlacement(
        entity: Entity,
        modelType: ModelType,
        instanceID: UUID
    ) async -> Bool {
        guard entity.parent === arViewModel.sharedAnchorEntity else { return false }

        let collisionResult = resolveCollisionIfNeeded(
            for: entity,
            instanceID: instanceID,
            modelType: modelType,
            positionValidator: collisionSupportValidator(for: entity, modelType: modelType)
        )

        if collisionMode == .prevent,
           collisionResult.hasOverlap,
           collisionResult.resolvedPosition == nil {
            collisionWarningCount = countCurrentCollisions()
            return false
        }

        refreshCollisionState(for: entity, instanceID: instanceID, modelType: modelType)
        selectionIndicatorManager.updateIndicatorPosition()
        return true
    }

    private func snapManipulatedEntity(_ entity: Entity, instanceID: UUID) async {
        guard let model = modelManager.modelDict[instanceID] else { return }
        guard entity.parent === arViewModel.sharedAnchorEntity else { return }
        let previousPose = capturePoseState(for: entity)
        let snapOptions = manipulationSnapOptions(for: entity)
        let viewerWorldPosition: SIMD3<Float>
        if let deviceTransform = worldTrackingProvider?
            .queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?
            .originFromAnchorTransform {
            viewerWorldPosition = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )
        } else {
            viewerWorldPosition = entity.position(relativeTo: nil)
        }

        if #available(visionOS 2.0, *),
           let currentRoomAnchor,
           let placement = RoomMeshPlacementEngine.placementForManipulation(
               entity: entity,
               modelType: model.modelType,
               sharedAnchor: arViewModel.sharedAnchorEntity,
               viewerWorldPosition: viewerWorldPosition,
               roomAnchor: currentRoomAnchor,
               options: snapOptions
           ) {
            entity.setPosition(placement.localPosition, relativeTo: arViewModel.sharedAnchorEntity)
            if let worldOrientation = placement.worldOrientation {
                entity.setOrientation(worldOrientation, relativeTo: nil)
            }
            applySnapState(from: placement, to: entity, phase: "manipulation")
            let collisionResult = resolveCollisionIfNeeded(
                for: entity,
                instanceID: model.id,
                modelType: model.modelType,
                positionValidator: collisionSupportValidator(for: entity, modelType: model.modelType)
            )
            if collisionMode == .prevent,
               collisionResult.hasOverlap,
               collisionResult.resolvedPosition == nil {
                restorePoseState(previousPose, on: entity)
            }
            refreshCollisionState(for: entity, instanceID: model.id, modelType: model.modelType)
            if let snapshot = snapshot(for: model) {
                historyManager.commitTransaction(for: model.id, after: snapshot, forceRecord: false)
            }
            selectionIndicatorManager.updateIndicatorPosition()
            return
        }

        guard let placement = SurfaceSnappingEngine.placementForManipulation(
            entity: entity,
            modelType: model.modelType,
            sharedAnchor: arViewModel.sharedAnchorEntity,
            planeAnchors: Array(trackedPlaneAnchors.values),
            allowedPlaneIDs: currentRoomPlaneIDs,
            viewerWorldPosition: viewerWorldPosition,
            options: snapOptions
        ) else {
            clearSnapState(
                on: entity,
                phase: "manipulation",
                reason: "no compatible room-mesh or plane surface survived snap and footprint thresholds"
            )
            let collisionResult = resolveCollisionIfNeeded(
                for: entity,
                instanceID: model.id,
                modelType: model.modelType
            )
            if collisionMode == .prevent,
               collisionResult.hasOverlap,
               collisionResult.resolvedPosition == nil {
                restorePoseState(previousPose, on: entity)
            }
            refreshCollisionState(for: entity, instanceID: model.id, modelType: model.modelType)
            if let snapshot = snapshot(for: model) {
                historyManager.commitTransaction(for: model.id, after: snapshot, forceRecord: false)
            }
            selectionIndicatorManager.updateIndicatorPosition()
            return
        }

        entity.setPosition(placement.localPosition, relativeTo: arViewModel.sharedAnchorEntity)
        if let worldOrientation = placement.worldOrientation {
            entity.setOrientation(worldOrientation, relativeTo: nil)
        }
        applySnapState(from: placement, to: entity, phase: "manipulation")
        let collisionResult = resolveCollisionIfNeeded(
            for: entity,
            instanceID: model.id,
            modelType: model.modelType,
            positionValidator: collisionSupportValidator(for: entity, modelType: model.modelType)
        )
        if collisionMode == .prevent,
           collisionResult.hasOverlap,
           collisionResult.resolvedPosition == nil {
            restorePoseState(previousPose, on: entity)
        }
        refreshCollisionState(for: entity, instanceID: model.id, modelType: model.modelType)
        if let snapshot = snapshot(for: model) {
            historyManager.commitTransaction(for: model.id, after: snapshot, forceRecord: false)
        }
        selectionIndicatorManager.updateIndicatorPosition()
    }

    private func manipulationSnapOptions(for entity: Entity) -> SurfaceSnappingEngine.Options {
        if entity.components[SnapStateComponent.self] != nil {
            return .manipulation.withHysteresis()
        }
        return .manipulation
    }

    private func applySnapState(from placement: SurfacePlacement, to entity: Entity, phase: String) {
        entity.components.set(
            SnapStateComponent(
                source: placement.source.kind,
                surfaceID: placement.source.surfaceID,
                classification: placement.classification,
                score: placement.score
            )
        )

        #if DEBUG
        let classification = placement.classification ?? "unclassified"
        print("Snap[\(phase)] source=\(placement.source.label) classification=\(classification) score=\(String(format: "%.3f", placement.score))")
        #endif
    }

    private func clearSnapState(on entity: Entity, phase: String, reason: String) {
        guard entity.components[SnapStateComponent.self] != nil else { return }
        entity.components[SnapStateComponent.self] = nil

        #if DEBUG
        print("Snap[\(phase)] cleared: \(reason)")
        #endif
    }

    private var currentRoomPlaneIDs: Set<UUID>? {
        guard let currentRoomAnchorID,
              let ids = roomPlaneIDsByRoomID[currentRoomAnchorID] else {
            return nil
        }
        return ids.isEmpty ? nil : ids
    }

    private var currentRoomAnchor: RoomAnchor? {
        guard let currentRoomAnchorID else { return nil }
        return trackedRoomAnchors[currentRoomAnchorID] as? RoomAnchor
    }

    private func updateEditMenuAttachmentPosition() {
        guard let attachment = editMenuAttachmentEntity else { return }
        guard let expandedEditModelID,
              let model = modelManager.modelDict[expandedEditModelID],
              let modelEntity = model.modelEntity,
              modelEntity.parent != nil else {
            attachment.removeFromParent()
            return
        }

        if attachment.parent !== arViewModel.sharedAnchorEntity {
            arViewModel.sharedAnchorEntity.addChild(attachment)
        }

        let bounds = modelEntity.visualBounds(relativeTo: arViewModel.sharedAnchorEntity)
        let size = bounds.extents
        let maxDimension = max(size.x, max(size.y, size.z))
        let verticalOffset = min(max(maxDimension * 0.24, 0.14), 0.26)
        let lateralOffset = min(max(size.x * 0.78, 0.28), 0.48)
        let forwardOffset: Float = min(max(maxDimension * 0.10, 0.06), 0.12)

        var sideSign: Float = 1
        var viewerLocalPosition: SIMD3<Float>? = nil
        if let deviceTransform = worldTrackingProvider?
            .queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?
            .originFromAnchorTransform {
            let viewerWorldPosition = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )
            viewerLocalPosition = arViewModel.sharedAnchorEntity.convert(
                position: viewerWorldPosition,
                from: nil
            )
            if let viewerLocalPosition {
                sideSign = viewerLocalPosition.x >= bounds.center.x ? -1 : 1
            }
        }

        let panelCenter = SIMD3<Float>(bounds.center.x, bounds.center.y, bounds.center.z)
        let viewerOffset: SIMD3<Float>
        if let viewerLocalPosition {
            let rawDirection = viewerLocalPosition - panelCenter
            let horizontalDirection = SIMD3<Float>(rawDirection.x, 0, rawDirection.z)
            if simd_length_squared(horizontalDirection) > 0.0001 {
                viewerOffset = simd_normalize(horizontalDirection) * forwardOffset
            } else {
                viewerOffset = SIMD3<Float>(0, 0, forwardOffset)
            }
        } else {
            viewerOffset = SIMD3<Float>(0, 0, forwardOffset)
        }

        attachment.setPosition(
            SIMD3<Float>(
                bounds.center.x + (lateralOffset * sideSign) + viewerOffset.x,
                bounds.max.y + verticalOffset,
                bounds.center.z + viewerOffset.z
            ),
            relativeTo: arViewModel.sharedAnchorEntity
        )
        attachment.isEnabled = true
    }

    private func resolveCollisionIfNeeded(
        for entity: Entity,
        instanceID: UUID,
        modelType: ModelType,
        positionValidator: ((SIMD3<Float>) -> Bool)? = nil
    ) -> FurnitureCollisionEngine.Result {
        guard entity.parent === arViewModel.sharedAnchorEntity else {
            return FurnitureCollisionEngine.Result(overlaps: [], resolvedPosition: nil)
        }

        let lastValidPosition = entity.components[CollisionStateComponent.self]?.lastValidPosition
        let result = FurnitureCollisionEngine.resolve(
            entity: entity,
            instanceID: instanceID,
            modelType: modelType,
            relativeTo: arViewModel.sharedAnchorEntity,
            among: modelManager.placedModels,
            mode: collisionMode,
            lastValidPosition: lastValidPosition,
            positionValidator: positionValidator
        )

        if collisionMode == .prevent,
           result.hasOverlap,
           let resolvedPosition = result.resolvedPosition {
            entity.setPosition(resolvedPosition, relativeTo: arViewModel.sharedAnchorEntity)
        }

        return result
    }

    private func capturePoseState(for entity: Entity) -> EntityPoseState {
        EntityPoseState(
            localPosition: entity.position(relativeTo: arViewModel.sharedAnchorEntity),
            worldOrientation: entity.orientation(relativeTo: nil),
            snapState: entity.components[SnapStateComponent.self]
        )
    }

    private func restorePoseState(_ poseState: EntityPoseState, on entity: Entity) {
        entity.setPosition(poseState.localPosition, relativeTo: arViewModel.sharedAnchorEntity)
        entity.setOrientation(poseState.worldOrientation, relativeTo: nil)

        if let snapState = poseState.snapState {
            entity.components.set(snapState)
        } else {
            entity.components.remove(SnapStateComponent.self)
        }
    }

    private func collisionSupportValidator(
        for entity: Entity,
        modelType: ModelType
    ) -> ((SIMD3<Float>) -> Bool)? {
        guard let snapState = entity.components[SnapStateComponent.self] else {
            return nil
        }

        let worldOrientation = entity.orientation(relativeTo: nil)

        switch snapState.source {
        case .plane:
            let requiredPlaneID = snapState.surfaceID
            let requiredClassification = snapState.classification
            let planeAnchors = Array(trackedPlaneAnchors.values)
            guard planeAnchors.contains(where: { $0.id == requiredPlaneID }) else {
                return { _ in false }
            }

            return { candidatePosition in
                SurfaceSnappingEngine.supportsPosition(
                    entity: entity,
                    modelType: modelType,
                    worldPosition: candidatePosition,
                    worldOrientation: worldOrientation,
                    planeAnchors: planeAnchors,
                    requiredPlaneID: requiredPlaneID,
                    requiredClassification: requiredClassification
                )
            }
        case .roomMesh:
            guard #available(visionOS 2.0, *),
                  let currentRoomAnchor,
                  currentRoomAnchor.id == snapState.surfaceID else {
                return { _ in false }
            }

            let requiredClassification = snapState.classification
            return { candidatePosition in
                RoomMeshPlacementEngine.supportsPosition(
                    entity: entity,
                    modelType: modelType,
                    worldPosition: candidatePosition,
                    worldOrientation: worldOrientation,
                    roomAnchor: currentRoomAnchor,
                    requiredClassification: requiredClassification
                )
            }
        }
    }

    private func refreshCollisionState(
        for entity: Entity,
        instanceID: UUID,
        modelType: ModelType
    ) {
        let stillOverlapping = FurnitureCollisionEngine.hasOverlap(
            entity: entity,
            instanceID: instanceID,
            modelType: modelType,
            relativeTo: arViewModel.sharedAnchorEntity,
            among: modelManager.placedModels
        )

        if !stillOverlapping {
            entity.components.set(
                CollisionStateComponent(
                    lastValidPosition: entity.position(relativeTo: arViewModel.sharedAnchorEntity)
                )
            )
        }

        collisionWarningCount = countCurrentCollisions()
    }

    private func countCurrentCollisions() -> Int {
        guard collisionMode != .off else { return 0 }

        return modelManager.placedModels.reduce(into: 0) { count, model in
            guard let entity = model.modelEntity,
                  FurnitureCollisionEngine.hasOverlap(
                    entity: entity,
                    instanceID: model.id,
                    modelType: model.modelType,
                    relativeTo: arViewModel.sharedAnchorEntity,
                    among: modelManager.placedModels
                  ) else {
                return
            }
            count += 1
        }
    }

    private func finalizeDiscreteTransformEdit(for model: Model, entity: Entity) {
        selectionIndicatorManager.updateIndicatorPosition()
        measurementManager.syncScene(with: modelManager.placedModels)
        Task { @MainActor in
            await self.snapManipulatedEntity(entity, instanceID: model.id)
        }
    }

    private func duplicatedPosition(for entity: Entity) -> SIMD3<Float> {
        let bounds = entity.visualBounds(relativeTo: sharedAnchorEntity)
        let horizontalSpacing = max(bounds.extents.x + 0.18, 0.35)

        if let deviceTransform = worldTrackingProvider?
            .queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?
            .originFromAnchorTransform {
            let viewerWorldPosition = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )
            let viewerLocalPosition = sharedAnchorEntity.convert(position: viewerWorldPosition, from: nil)
            let sideSign: Float = viewerLocalPosition.x >= bounds.center.x ? -1 : 1
            return entity.position(relativeTo: sharedAnchorEntity) + SIMD3<Float>(horizontalSpacing * sideSign, 0, 0)
        }

        return entity.position(relativeTo: sharedAnchorEntity) + SIMD3<Float>(horizontalSpacing, 0, 0)
    }

    private func applyDuplicatedVisualState(from snapshot: ModelSnapshot, to model: Model) {
        guard let entity = model.modelEntity else { return }

        if var modelComponent = entity.components[ModelComponent.self] {
            modelComponent.materials = snapshot.materials
            entity.components.set(modelComponent)
        }

        if let materialType = snapshot.materialType {
            entity.components.set(MaterialTypeComponent(materialType: materialType))
        } else {
            entity.components.remove(MaterialTypeComponent.self)
        }

        if let originalBounds = snapshot.originalBounds {
            entity.components.set(OriginalBoundsComponent(originalSize: originalBounds))
        }

        entity.components.remove(SnapStateComponent.self)
    }
    #endif

    
    
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

        modelManager.$placedModels
            .map { models in
                models.map { model in
                    PlacedModelDescriptor(
                        id: model.id,
                        name: model.modelType.displayName,
                        type: model.modelType
                    )
                }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$placedModelDescriptors)

        modelManager.$selectedModelID
                        .map { $0?.id }
                        .receive(on: DispatchQueue.main)
                        .assign(to: &$selectedModelID)

        modelManager.$selectedModelInstanceID
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedModelInstanceID)

        historyManager.$canUndo
            .receive(on: DispatchQueue.main)
            .assign(to: &$canUndo)

        historyManager.$canRedo
            .receive(on: DispatchQueue.main)
            .assign(to: &$canRedo)

        // Bind focus mode manager state
        #if os(visionOS)
        focusModeManager.$isFocusModeActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isFocusModeActive)

        focusModeManager.$focusRoomDimensions
            .receive(on: DispatchQueue.main)
            .assign(to: &$focusRoomDimensions)

        // Update selection indicator when selection changes
        modelManager.$selectedModelInstanceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSelectionIndicator()
            }
            .store(in: &cancellables)
        #endif
    }


    public func refreshAvailableModels() {
        availableModels = modelManager.modelTypes.map { modelType in
            ModelDescriptor(
                type: modelType,
                source: source(for: modelType),
                category: category(for: modelType),
                dateAdded: dateAdded(for: modelType)
            )
        }
    }

    private func source(for modelType: ModelType) -> ModelSource {
        guard let modelURL = Bundle.xrShareLocateUSDZ(named: modelType.rawValue) else {
            return .unknown
        }

        let pathComponents = Set(modelURL.pathComponents.map { $0.lowercased() })
        if pathComponents.contains("imports") {
            return .imports
        }
        if pathComponents.contains("scans") {
            return .scans
        }
        return .presets
    }

    private func dateAdded(for modelType: ModelType) -> Date? {
        guard let modelURL = Bundle.xrShareLocateUSDZ(named: modelType.rawValue),
              let values = try? modelURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        else {
            return nil
        }
        return values.creationDate ?? values.contentModificationDate
    }

    private func category(for modelType: ModelType) -> ModelCategory {
        let key = modelType.rawValue.lowercased()

        if key.contains("chair") || key.contains("sofa") || key.contains("couch") || key.contains("stool") {
            return .seating
        }
        if key.contains("bed") {
            return .beds
        }
        if key.contains("closet") || key.contains("cabinet") || key.contains("shelf") || key.contains("storage") {
            return .storage
        }
        if key.contains("lamp") || key.contains("light") || key.contains("chandelier") {
            return .lighting
        }
        if key.contains("table") {
            return .tables
        }
        if key.contains("tv") || key.contains("monitor") {
            return .media
        }
        if key.contains("vase") || key.contains("decor") {
            return .decor
        }
        return .unknown
    }
}

private extension Entity {
    func ancestorOrSelf<T: Component>(with componentType: T.Type) -> Entity? {
        var current: Entity? = self
        while let candidate = current {
            if candidate.components[componentType] != nil {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }
}
