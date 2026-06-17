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
    var preferredPlacementResolver: ((ModelEntity, ModelType) async -> SurfacePlacement?)?
    var spawnedModelPlacementPostProcessor: ((ModelEntity, ModelType, UUID) async -> Bool)?

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

    #if os(visionOS)
    
    // Backing storage that avoids direct reference to a versioned type in a stored property
    private var _manipulationManagerAny: Any?
    @available(visionOS 26.0, *)
    var manipulationManager: ManipulationManager? {
        get { _manipulationManagerAny as? ManipulationManager }
        set {
            _manipulationManagerAny = newValue
      
            newValue?.arViewModel = self
        }
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

    override init() {
        super.init()
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            self.manipulationManager = ManipulationManager()
        }
        #endif
    }
}

extension ARViewModel {

    // MARK: - Reset Methods

    /// Comprehensive reset of all ARViewModel state for clean restart
    @MainActor
    func resetToCleanState() {
        #if DEBUG
        print("ARViewModel: Resetting to clean state")
        #endif
        selectedModel = nil

        showingParticipantsList = false
   

        loadingProgress = 0.0
        alertItem = nil
        showingParticipantsList = false
        sessionIsActive = false
   
        pendingPlacementPosition = nil
        pendingHeadCenterInstanceID = nil
        headCenterWork = nil

        // Clean up manipulation manager
        if #available(visionOS 26.0, *) {
            manipulationManager?.reset()
            manipulationManager = nil
        }


        // Reset shared anchor entity, clear all children and reset transform
        sharedAnchorEntity.children.removeAll()
        sharedAnchorEntity.transform = Transform(translation: SIMD3<Float>(0, 1.2, -1.2))
     
        sharedAnchorEntity.isEnabled = true


        #if DEBUG
        print("ARViewModel: Clean state reset completed")
        #endif
    }

}
