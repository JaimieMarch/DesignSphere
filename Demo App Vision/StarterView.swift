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
    /// Set when opening the immersive space failed or was cancelled. Without the
    /// immersive space every placed model is parented to an anchor that is in no
    /// scene, so the app looks alive but nothing can ever appear.
    var immersiveSpaceFailure: String?
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
    var showImportSheet = false
    var showTutorial = false
    var showAIAssistant = false
}

// enforce vision OS 26 or higher
@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        GeometryReader { proxy in
            ZStack {
                // Keep all screens in memory for smooth transitions
                ZStack(alignment: .topLeading) {
                    // Home Screen
                    HomeScreen(
                        controller: controller,
                        favoriteModels: $favoriteModels
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .opacity(navigationState.currentScreen == .home ? navigationState.transitionOpacity : 0)
                    .scaleEffect(screenScale(for: .home))
                    .blur(radius: screenBlur(for: .home))
                    .allowsHitTesting(navigationState.currentScreen == .home)
                    
                    // Details Screen
                    DetailsScreen(controller: controller)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .opacity(navigationState.currentScreen == .details ? navigationState.transitionOpacity : 0)
                        .scaleEffect(screenScale(for: .details))
                        .blur(radius: screenBlur(for: .details))
                        .allowsHitTesting(navigationState.currentScreen == .details)
                    
                    // Settings Screen
                    if AppFeatureFlags.settingsScreenEnabled {
                        SettingsScreen(onModelsImported: { controller.refreshAvailableModels() })
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                            .opacity(navigationState.currentScreen == .settings ? navigationState.transitionOpacity : 0)
                            .scaleEffect(screenScale(for: .settings))
                            .blur(radius: screenBlur(for: .settings))
                            .allowsHitTesting(navigationState.currentScreen == .settings)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                // Reduce Motion gets a plain cross-fade instead of a springy
                // scale-and-blur of the entire window contents.
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.2)
                        : .interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25),
                    value: navigationState.currentScreen
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .interactiveSpring(response: 0.2, dampingFraction: 0.9, blendDuration: 0),
                    value: navigationState.contentScale
                )
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
                        controller: controller,
                        showMeasurementOptions: $sheetState.showMeasurementOptions,
                        showFocusModeSheet: $sheetState.showFocusModeSheet,
                        showImportSheet: $sheetState.showImportSheet,
                        showAIAssistant: $sheetState.showAIAssistant
                    )
                }
            }
        }
        .onAppear {
            sessionState.isImmersiveOpen = false
            loadingState.isLoading = true
            loadFavorites()
            controller.setCollisionMode(appSettings.collisionMode)
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
        .onChange(of: appSettings.collisionMode) { _, mode in
            controller.setCollisionMode(mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.favoritesDidResetNotification)) { _ in
            favoriteModels.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.tutorialReplayRequestedNotification)) { _ in
            sheetState.showTutorial = true
        }
        .onChange(of: sheetState.showMeasurementOptions) { _, isPresented in
            guard isPresented else { return }
            if !AppFeatureFlags.measurementToolsEnabled {
                sheetState.showMeasurementOptions = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                sessionState.isImmersiveOpen = false
            }
        }
        // Sheets for action items
        .sheet(isPresented: $sheetState.showMeasurementOptions) {
            if AppFeatureFlags.measurementToolsEnabled {
                MeasurementSheet(
                    isPresented: $sheetState.showMeasurementOptions,
                    controller: controller
                )
            }
        }
        .sheet(isPresented: $sheetState.showFocusModeSheet) {
            FocusModeSheet(isPresented: $sheetState.showFocusModeSheet, controller: controller)
        }
        .sheet(isPresented: $sheetState.showImportSheet) {
            ImportModelSheet(isPresented: $sheetState.showImportSheet, controller: controller)
        }
        .sheet(isPresented: $sheetState.showAIAssistant) {
            if AppFeatureFlags.aiAssistantEnabled {
                AIAssistantSheet(isPresented: $sheetState.showAIAssistant, controller: controller)
            }
        }
        .sheet(isPresented: $sheetState.showTutorial, onDismiss: {
            appSettings.markOnboardingCompleted()
        }) {
            TutorialHubSheet(isPresented: $sheetState.showTutorial)
        }
        .overlay(alignment: .top) {
            immersiveSpaceFailureBanner
        }
        .overlay {
            LoadingScreen(
                isLoading: $loadingState.isLoading,
                loadingProgress: $loadingState.progress,
                loadingMessage: $loadingState.message
            )
        }
    }

    /// Surfaced when `openImmersiveSpace` reports `.error` or `.userCancelled`.
    /// Silently ignoring those leaves the catalog usable but every placement
    /// invisible, with nothing on screen to explain why.
    @ViewBuilder
    private var immersiveSpaceFailureBanner: some View {
        if let message = sessionState.immersiveSpaceFailure, !loadingState.isLoading {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Immersive space unavailable")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button("Try Again") {
                    Task { await ensureImmersiveSpaceOpened() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Reopens the immersive space so placed models can appear in your room")
            }
            .padding(16)
            .frame(maxWidth: 640)
            .glassBackground(cornerRadius: 20)
            .padding(.top, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Immersive space unavailable. \(message)")
        }
    }

    /// Reduce Motion suppresses the scale/blur depth cue between tabs.
    private func screenScale(for tab: ScreenTab) -> CGFloat {
        guard !reduceMotion else { return 1.0 }
        return navigationState.currentScreen == tab ? navigationState.contentScale : 0.96
    }

    private func screenBlur(for tab: ScreenTab) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return navigationState.currentScreen == tab ? 0 : 1
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
            guard !reduceMotion else {
                // Plain cross-fade: no press-down scale, no spring.
                navigationState.contentScale = 1.0
                navigationState.transitionOpacity = 1.0
                navigationState.currentScreen = newTab
                return
            }

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

        // Point the catalog at the remote manifest (R2) before preloading.
        RemoteCatalogService.shared.configure(
            baseURL: AppFeatureFlags.remoteCatalogBaseURL,
            enabled: AppFeatureFlags.remoteCatalogEnabled
        )
        // The manifest can take many seconds on a slow network. Load it behind
        // the app instead of in front of it: the catalog screen shows its own
        // loading state, and every other screen is usable meanwhile.
        controller.startPreload(strategy: .minimal)

        loadingState.message = "Ready!"
        loadingState.progress = 1.0

        // Hide loading screen after brief delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation {
            loadingState.isLoading = false
        }

        // First run: surface the walkthrough so newcomers learn the key flows.
        if !appSettings.hasCompletedOnboarding {
            sheetState.showTutorial = true
        }
    }
    
    @MainActor
    private func ensureImmersiveSpaceOpened() async {
        guard sessionState.isImmersiveOpen == false else { return }
        let result = await openImmersiveSpace(id: "CollaborativeSpace")
        switch result {
        case .opened:
            sessionState.isImmersiveOpen = true
            sessionState.immersiveSpaceFailure = nil

            // Start world tracking for world anchor persistence
            #if !targetEnvironment(simulator)
            do {
                try await controller.startWorldTracking()
            } catch {
                #if DEBUG
                print("Failed to start world tracking: \(error)")
                #endif
            }
            #endif

        case .userCancelled:
            sessionState.immersiveSpaceFailure =
                "Opening the immersive space was cancelled, so models can't appear in your room yet."

        case .error:
            sessionState.immersiveSpaceFailure =
                "DesignSphere couldn't open its immersive space, so models can't appear in your room."

        @unknown default:
            sessionState.immersiveSpaceFailure =
                "DesignSphere couldn't open its immersive space, so models can't appear in your room."
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
                Section {
                    NavigationLink {
                        InteractiveWalkthroughView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Interactive Walkthrough")
                                    .font(.headline)
                                Text("A quick tour of browsing, placing, customizing, and saving.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.tint)
                        }
                    }

                    // Video tutorials will appear here once bundled.
                } header: {
                    Text("Learn the basics")
                } footer: {
                    Text("You can reopen this anytime from Settings › Tutorial.")
                }
            }
            .navigationTitle("Welcome to DesignSphere")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

private struct InteractiveWalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0

    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let description: String
    }

    private let steps: [Step] = [
        .init(
            id: 0,
            icon: "square.grid.2x2.fill",
            title: "Browse the catalog",
            description: "Explore 180+ furniture and décor models. Search understands intent — type “sofa” to surface every seating piece — and filter by category or by Textured vs Customizable finish."
        ),
        .init(
            id: 1,
            icon: "hand.tap.fill",
            title: "Place a model",
            description: "Tap any model to drop it into your space. It downloads the first time you use it, then appears true-to-scale in front of you."
        ),
        .init(
            id: 2,
            icon: "paintbrush.fill",
            title: "Customize it",
            description: "Tap a placed model to select it, then tap the Edit chip above it to resize, reposition, recolor, and apply materials — ideal for the Customizable (untextured) pieces."
        ),
        .init(
            id: 3,
            icon: "ruler.fill",
            title: "Measure & arrange",
            description: "Show object dimensions, measure the distance between items, or drop a virtual ruler — then arrange your room to scale."
        ),
        .init(
            id: 4,
            icon: "square.and.arrow.down.fill",
            title: "Save your room",
            description: "Save layouts as projects from the Details screen, and reload them whenever you return."
        )
    ]

    private var step: Step { steps[currentStepIndex] }

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 8) {
                ForEach(steps) { dot in
                    Circle()
                        .fill(dot.id == currentStepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)

            Spacer()

            Image(systemName: step.icon)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .frame(height: 96)
                .id(step.id)
                .transition(.opacity)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(step.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { currentStepIndex = max(0, currentStepIndex - 1) }
                }
                .opacity(currentStepIndex == 0 ? 0 : 1)
                .disabled(currentStepIndex == 0)

                Spacer()

                if currentStepIndex < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStepIndex += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Welcome")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { dismiss() }
            }
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
