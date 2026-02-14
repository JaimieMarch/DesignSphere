// Root view that inits the collaborative session and handles
// immersive space setup, navigation, global UI state

import SwiftUI
import XRShareCollaboration

// MARK: - Consolidated State Structs

/// Manages session-related state
struct SessionState {
    var isImmersiveOpen = false
    var hasInitializedSession = false
    var isActivatingSharePlay = false
    var sharePlayError: String?
}

/// Manages loading screen state
struct LoadingState {
    var isLoading = true
    var progress: Float = 0.0
    var message = "Initializing..."
}

/// Manages navigation and transition animation state
struct NavigationState {
    var currentScreen: StarterView.ScreenTab = .home
    var contentScale: CGFloat = 1.0
    var transitionOpacity: Double = 1.0
}

/// Manages sheet visibility state
struct SheetVisibilityState {
    var showMeasurementOptions = false
    var showFocusModeSheet = false
    var showEditSheet = false
    var showImportSheet = false
}

// enforce vision OS 26 or higher
@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    // Consolidated state structs
    @State private var sessionState = SessionState()
    @State private var loadingState = LoadingState()
    @State private var navigationState = NavigationState()
    @State private var sheetState = SheetVisibilityState()

    // User preferences (kept separate as it's persisted)
    @State private var favoriteModels: Set<String> = []
    private let favoritesDefaultsKey = "favoriteModels"
    
    // Screen tabs that change the main content
    enum ScreenTab: Int, CaseIterable {
        case home = 0
        case details = 1
        case settings = 2

        static var enabledCases: [ScreenTab] {
            allCases.filter(\.isEnabled)
        }

        var isEnabled: Bool {
            switch self {
            case .home, .details:
                return true
            case .settings:
                return AppFeatureFlags.settingsScreenEnabled
            }
        }

        var label: String {
            switch self {
            case .home: return "Home"
            case .details: return "Details"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house"
            case .details: return "folder"
            case .settings: return "gearshape"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Keep all screens in memory for smooth transitions
            ZStack {
                // Home Screen
                HomeScreen(
                    controller: controller,
                    favoriteModels: $favoriteModels
                )
                .opacity(navigationState.currentScreen == .home ? navigationState.transitionOpacity : 0)
                .scaleEffect(navigationState.currentScreen == .home ? navigationState.contentScale : 0.96)
                .blur(radius: navigationState.currentScreen == .home ? 0 : 1)
                .allowsHitTesting(navigationState.currentScreen == .home)
                
                // Details Screen
                DetailsScreen(controller: controller)
                    .opacity(navigationState.currentScreen == .details ? navigationState.transitionOpacity : 0)
                    .scaleEffect(navigationState.currentScreen == .details ? navigationState.contentScale : 0.96)
                    .blur(radius: navigationState.currentScreen == .details ? 0 : 1)
                    .allowsHitTesting(navigationState.currentScreen == .details)
                
                // Settings Screen
                if AppFeatureFlags.settingsScreenEnabled {
                    SettingsScreen()
                        .opacity(navigationState.currentScreen == .settings ? navigationState.transitionOpacity : 0)
                        .scaleEffect(navigationState.currentScreen == .settings ? navigationState.contentScale : 0.96)
                        .blur(radius: navigationState.currentScreen == .settings ? 0 : 1)
                        .allowsHitTesting(navigationState.currentScreen == .settings)
                }
            }
            .animation(.interactiveSpring(
                response: 0.35,
                dampingFraction: 0.86,
                blendDuration: 0.25
            ), value: navigationState.currentScreen)
            .animation(.interactiveSpring(
                response: 0.2,
                dampingFraction: 0.9,
                blendDuration: 0
            ), value: navigationState.contentScale)
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.leading),
                contentAlignment: .leading
            ) {
                NavigationOrnament(
                    currentScreen: $navigationState.currentScreen,
                    onTabWillChange: { newTab in
                        performTabTransition(to: newTab)
                    }
                )
            }
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.bottom),
                contentAlignment: .top
            ) {
                ToolbarOrnament(
                    showMeasurementOptions: $sheetState.showMeasurementOptions,
                    showFocusModeSheet: $sheetState.showFocusModeSheet,
                    showEditSheet: $sheetState.showEditSheet,
                    showImportSheet: $sheetState.showImportSheet,
                    controller: controller
                )
            }
        }
        .onAppear {
            sessionState.isImmersiveOpen = false
            loadingState.isLoading = true
            loadFavorites()
        }
        .task { await prepareExperience() }
        .onChange(of: favoriteModels) {
            saveFavorites(favoriteModels)
        }
        .alert("SharePlay", isPresented: Binding(
            get: { sessionState.sharePlayError != nil },
            set: { if !$0 { sessionState.sharePlayError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = sessionState.sharePlayError { Text(message) }
        }
        
        // Sheets for action items
        .sheet(isPresented: $sheetState.showMeasurementOptions) {
            if AppFeatureFlags.measurementToolsEnabled {
                MeasurementSheet(isPresented: $sheetState.showMeasurementOptions)
            }
        }
        .sheet(isPresented: $sheetState.showFocusModeSheet) {
            FocusModeSheet(isPresented: $sheetState.showFocusModeSheet, controller: controller)
        }
        .sheet(isPresented: $sheetState.showEditSheet) {
            EditModelSheet(isPresented: $sheetState.showEditSheet, controller: controller)
        }
        .sheet(isPresented: $sheetState.showImportSheet) {
            ImportModelSheet(isPresented: $sheetState.showImportSheet, controller: controller)
        }
        .overlay {
            LoadingScreen(
                isLoading: $loadingState.isLoading,
                loadingProgress: $loadingState.progress,
                loadingMessage: $loadingState.message
            )
        }
    }
    
    private func loadFavorites() {
        if let stored = UserDefaults.standard.array(forKey: favoritesDefaultsKey) as? [String] {
            favoriteModels = Set(stored)
        }
    }
    
    private func saveFavorites(_ favorites: Set<String>) {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesDefaultsKey)
    }
    
    private func performTabTransition(to newTab: ScreenTab) {
        Task { @MainActor in
            // Press down effect
            withAnimation(.easeOut(duration: 0.08)) {
                navigationState.contentScale = 0.98
                navigationState.transitionOpacity = 0.95
            }

            // Change screen
            navigationState.currentScreen = newTab

            // Spring back
            withAnimation(.interactiveSpring(
                response: 0.28,
                dampingFraction: 0.78,
                blendDuration: 0
            )) {
                navigationState.contentScale = 1.0
                navigationState.transitionOpacity = 1.0
            }
        }
    }
    
    @MainActor
    private func prepareExperience() async {
        guard sessionState.hasInitializedSession == false else {
            await ensureImmersiveSpaceOpened()
            loadingState.isLoading = false
            return
        }

        loadingState.message = "Starting session..."
        loadingState.progress = 0.1
        controller.startLocalSession()
        sessionState.hasInitializedSession = true

        loadingState.message = "Opening immersive space..."
        loadingState.progress = 0.5
        await ensureImmersiveSpaceOpened()

        loadingState.message = "Loading models..."
        loadingState.progress = 0.7
        // Preload models AFTER opening immersive space for faster perceived startup
        await controller.preloadIfNeeded(strategy: .minimal)

        loadingState.message = "Ready!"
        loadingState.progress = 1.0

        // Hide loading screen after brief delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation {
            loadingState.isLoading = false
        }
    }
    
    private func ensureImmersiveSpaceOpened() async {
        guard sessionState.isImmersiveOpen == false else { return }
        let result = await openImmersiveSpace(id: "CollaborativeSpace")
        if case .opened = result {
            await MainActor.run { sessionState.isImmersiveOpen = true }

            // Start world tracking for world anchor persistence
            do {
                try await controller.startWorldTracking()
            } catch {
                print("Failed to start world tracking: \(error)")
            }
        }
    }
}

#Preview {
    StarterView(controller: CollaborativeSessionController())
}
