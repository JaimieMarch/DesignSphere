// Root view that inits the collaborative session and handles
// immersive space setup, navigation, global UI state

import SwiftUI
import XRShareCollaboration
import AVKit

// MARK: - Consolidated State Structs

/// Manages session-related state
struct SessionState {
    var isImmersiveOpen = false
    var hasInitializedSession = false
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
    var showTutorial = false
}

// enforce vision OS 26 or higher
@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    // Consolidated state structs
    @State private var sessionState = SessionState()
    @State private var loadingState = LoadingState()
    @State private var navigationState = NavigationState()
    @State private var sheetState = SheetVisibilityState()

    // User preferences (kept separate for HomeScreen binding)
    @State private var favoriteModels: Set<String> = []
    
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
                    showImportSheet: $sheetState.showImportSheet
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
        .onChange(of: appSettings.rememberFavoritesEnabled) {
            if appSettings.rememberFavoritesEnabled {
                loadFavorites()
            } else {
                favoriteModels.removeAll()
                appSettings.clearStoredFavorites()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.favoritesDidResetNotification)) { _ in
            favoriteModels.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.tutorialReplayRequestedNotification)) { _ in
            sheetState.showTutorial = true
        }
        .onChange(of: controller.editRequestToken) { _, _ in
            if controller.pendingEditModelID != nil {
                sheetState.showEditSheet = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                sessionState.isImmersiveOpen = false
            }
        }
        // Sheets for action items
        .sheet(isPresented: $sheetState.showMeasurementOptions) {
            if AppFeatureFlags.measurementToolsEnabled && appSettings.labsMeasurementToolsEnabled {
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
        .sheet(isPresented: $sheetState.showTutorial) {
            TutorialHubSheet(isPresented: $sheetState.showTutorial)
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
        guard appSettings.rememberFavoritesEnabled else {
            favoriteModels = []
            return
        }
        if let stored = UserDefaults.standard.array(forKey: AppSettings.favoritesDefaultsKey) as? [String] {
            favoriteModels = Set(stored)
        }
    }
    
    private func saveFavorites(_ favorites: Set<String>) {
        guard appSettings.rememberFavoritesEnabled else { return }
        UserDefaults.standard.set(Array(favorites), forKey: AppSettings.favoritesDefaultsKey)
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
                #if DEBUG
                print("Failed to start world tracking: \(error)")
                #endif
            }
        }
    }
}

#Preview {
    StarterView(controller: CollaborativeSessionController())
        .environmentObject(AppSettings())
}

private struct TutorialHubSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Tutorial Style") {
                    NavigationLink {
                        InteractiveWalkthroughView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Interactive Walkthrough")
                                .font(.headline)
                            Text("Guided overlay-style steps that explain key UI areas.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Video tutorials temporarily removed — videos not yet bundled
                }
            }
            .navigationTitle("Tutorial Center")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") { isPresented = false }
                }
            }
        }
    }
}

private struct InteractiveWalkthroughView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let target: String
        let description: String
    }

    private let steps: [Step] = [
        .init(
            id: 0,
            title: "Navigation Rail",
            target: "Left Navigation Ornament",
            description: "Use Home, Details, and Settings tabs to move between major surfaces."
        ),
        .init(
            id: 1,
            title: "Action Toolbar",
            target: "Bottom Toolbar Ornament",
            description: "Open Focus Mode, Import, Measurement (if enabled), and Edit controls."
        ),
        .init(
            id: 2,
            title: "Model Catalog",
            target: "Home Screen Grid",
            description: "Browse models, apply source/category filters, and mark favorites."
        ),
        .init(
            id: 3,
            title: "Project Controls",
            target: "Details Screen",
            description: "Save, load, and manage room projects and anchors."
        ),
    ]

    private var step: Step { steps[currentStepIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Interactive Walkthrough")
                .font(.largeTitle.bold())

            Text("Step \(currentStepIndex + 1) of \(steps.count)")
                .font(.headline)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(step.title)
                            .font(.title2.bold())
                        Text("Highlight: \(step.target)")
                            .font(.headline)
                        Text(step.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .frame(height: 220)
                .overlay(alignment: .bottomTrailing) {
                    // Simulated spotlight marker for overlay-style onboarding.
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [6]))
                        .foregroundStyle(.yellow)
                        .frame(width: 70, height: 70)
                        .padding(20)
                }

            HStack {
                Button("Back") {
                    currentStepIndex = max(0, currentStepIndex - 1)
                }
                .disabled(currentStepIndex == 0)

                Spacer()

                if currentStepIndex < steps.count - 1 {
                    Button("Next") {
                        currentStepIndex += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Finish") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .navigationTitle("Walkthrough")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Exit") { dismiss() }
            }
        }
        .onAppear {
            appSettings.markOnboardingIncompleteForReplay()
        }
    }
}

private struct VideoTutorialLibraryView: View {
    var body: some View {
        List {
            ForEach(TutorialCatalog.modules) { module in
                NavigationLink {
                    VideoTutorialPlayerView(module: module)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(module.title)
                            .font(.headline)
                        Text(module.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Duration: \(module.durationLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Video Tutorials")
    }
}

private struct VideoTutorialPlayerView: View {
    let module: TutorialVideoModule
    @State private var player: AVPlayer?
    @State private var unavailableReason: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(module.title)
                    .font(.title.bold())
                Text(module.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "video.slash")
                                    .font(.title2)
                                Text(unavailableReason ?? "Video unavailable.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .frame(height: 220)
                }
            }
            .padding(24)
        }
        .navigationTitle(module.title)
        .onAppear(perform: configurePlayerIfPossible)
        .onDisappear {
            player?.pause()
        }
    }

    private func configurePlayerIfPossible() {
        switch module.source {
        case .bundled(let name, let ext):
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                player = nil
                unavailableReason = "This tutorial video is not bundled yet (\(name).\(ext))."
                return
            }
            player = AVPlayer(url: url)
            unavailableReason = nil
        case .remote(let urlString):
            guard let url = URL(string: urlString) else {
                player = nil
                unavailableReason = "Invalid video URL."
                return
            }
            player = AVPlayer(url: url)
            unavailableReason = nil
        }
    }
}
