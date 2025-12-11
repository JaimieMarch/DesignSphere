// Root view that inits the collaborative session and handles
// immersive space setup, navigation, global UI state

import SwiftUI
import XRShareCollaboration

// enforce vision OS 26 or higher
@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    // States to keep track of
    @State private var isImmersiveOpen = false
    @State private var hasInitializedSession = false
    @State private var isActivatingSharePlay = false
    @State private var sharePlayError: String?
    @State private var favoriteModels: Set<String> = []
    private let favoritesDefaultsKey = "favoriteModels"

    // Loading states
    @State private var isLoading = true
    @State private var loadingProgress: Float = 0.0
    @State private var loadingMessage = "Initializing..."

    // Navigation states to show which screen is active at a time
    @State private var currentScreen: ScreenTab = .home
    @State private var contentScale: CGFloat = 1.0
    @State private var transitionOpacity: Double = 1.0
    
    // Popover states to control visibility of popovers
    @State private var showMeasurementOptions = false
    @State private var showFocusModeSheet = false
    @State private var showEditSheet = false
    @State private var showImportSheet = false
    
    // Screen tabs that change the main content
    enum ScreenTab: Int, CaseIterable {
        case home = 0
        case details = 1
        case settings = 2

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
                .opacity(currentScreen == .home ? transitionOpacity : 0)
                .scaleEffect(currentScreen == .home ? contentScale : 0.96)
                .blur(radius: currentScreen == .home ? 0 : 1)
                .allowsHitTesting(currentScreen == .home)
                
                // Details Screen
                DetailsScreen(controller: controller)
                    .opacity(currentScreen == .details ? transitionOpacity : 0)
                    .scaleEffect(currentScreen == .details ? contentScale : 0.96)
                    .blur(radius: currentScreen == .details ? 0 : 1)
                    .allowsHitTesting(currentScreen == .details)
                
                // Settings Screen
                SettingsScreen()
                    .opacity(currentScreen == .settings ? transitionOpacity : 0)
                    .scaleEffect(currentScreen == .settings ? contentScale : 0.96)
                    .blur(radius: currentScreen == .settings ? 0 : 1)
                    .allowsHitTesting(currentScreen == .settings)
            }
            .animation(.interactiveSpring(
                response: 0.35,
                dampingFraction: 0.86,
                blendDuration: 0.25
            ), value: currentScreen)
            .animation(.interactiveSpring(
                response: 0.2,
                dampingFraction: 0.9,
                blendDuration: 0
            ), value: contentScale)
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.leading),
                contentAlignment: .leading
            ) {
                NavigationOrnament(
                    currentScreen: $currentScreen,
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
                    showMeasurementOptions: $showMeasurementOptions,
                    showFocusModeSheet: $showFocusModeSheet,
                    showEditSheet: $showEditSheet,
                    showImportSheet: $showImportSheet,
                    controller: controller
                )
            }
        }
        .onAppear {
            isImmersiveOpen = false
            isLoading = true
            loadFavorites()
        }
        .task { await prepareExperience() }
        .onChange(of: favoriteModels) {
            saveFavorites(favoriteModels)
        }
        .alert("SharePlay", isPresented: Binding(
            get: { sharePlayError != nil },
            set: { if !$0 { sharePlayError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = sharePlayError { Text(message) }
        }
        
        // Sheets for action items
        .sheet(isPresented: $showMeasurementOptions) {
            MeasurementSheet(isPresented: $showMeasurementOptions)
        }
        .sheet(isPresented: $showFocusModeSheet) {
            FocusModeSheet(isPresented: $showFocusModeSheet, controller: controller)
        }
        .sheet(isPresented: $showEditSheet) {
            EditModelSheet(isPresented: $showEditSheet, controller: controller)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportModelSheet(isPresented: $showImportSheet, controller: controller)
        }
        .overlay {
            LoadingScreen(
                isLoading: $isLoading,
                loadingProgress: $loadingProgress,
                loadingMessage: $loadingMessage
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
                contentScale = 0.98
                transitionOpacity = 0.95
            }
            
            // Change screen
            currentScreen = newTab
            
            // Spring back
            withAnimation(.interactiveSpring(
                response: 0.28,
                dampingFraction: 0.78,
                blendDuration: 0
            )) {
                contentScale = 1.0
                transitionOpacity = 1.0
            }
        }
    }
    
    @MainActor
    private func prepareExperience() async {
        guard hasInitializedSession == false else {
            await ensureImmersiveSpaceOpened()
            isLoading = false
            return
        }

        loadingMessage = "Starting session..."
        loadingProgress = 0.1
        controller.startLocalSession()
        hasInitializedSession = true

        loadingMessage = "Opening immersive space..."
        loadingProgress = 0.5
        await ensureImmersiveSpaceOpened()

        loadingMessage = "Loading models..."
        loadingProgress = 0.7
        // Preload models AFTER opening immersive space for faster perceived startup
        await controller.preloadIfNeeded()

        loadingMessage = "Ready!"
        loadingProgress = 1.0

        // Hide loading screen after brief delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation {
            isLoading = false
        }
    }
    
    private func ensureImmersiveSpaceOpened() async {
        guard isImmersiveOpen == false else { return }
        let result = await openImmersiveSpace(id: "CollaborativeSpace")
        if case .opened = result {
            await MainActor.run { isImmersiveOpen = true }

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
