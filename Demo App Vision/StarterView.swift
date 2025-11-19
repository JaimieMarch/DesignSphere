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
    
    // Navigation states to show which screen is active at a time
    @State private var currentScreen: ScreenTab = .home
    @State private var contentScale: CGFloat = 1.0
    @State private var transitionOpacity: Double = 1.0
    
    // Popover states to control visibility of popovers
    @State private var showMeasurementOptions = false
    @State private var showFocusModeSheet = false
    @State private var showAIAssistantSheet = false
    @State private var showSharePlaySheet = false
    
    // Screen tabs that change the main content
    // see: tabview ornament implementation
    // This represents the state of the active screen
    enum ScreenTab: Int, CaseIterable {
        case home = 0
        case details = 1
        case scanMode = 2
        case settings = 3
        
        var label: String {
            switch self {
            case .home: return "Home"
            case .details: return "Details"
            case .scanMode: return "Scan Mode"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house"
            case .details: return "folder"
            case .settings: return "gearshape"
            case .scanMode: return "vision.pro.and.arrow.forward"
            }
        }
    }
    
    // All views are kept alive at all times
    // - inactive screens gets opacity set to 0
    // - slightly shrunk to improve transition animation
    // - interactions are deactivated
    var body: some View {
        ZStack {
            // Keep all screens in memory for smooth transitions
            ZStack {
                // Home Screen
                HomeScreenContent(
                    controller: controller,
                    favoriteModels: $favoriteModels
                )
                    .opacity(currentScreen == .home ? transitionOpacity : 0)
                    .scaleEffect(
                    currentScreen == .home ? contentScale : 0.96
                )
                    .blur(radius: currentScreen == .home ? 0 : 1)
                    .allowsHitTesting(currentScreen == .home)
                
                // Details Screen
                DetailsScreenContent(controller: controller)
                    .opacity(currentScreen == .details ? transitionOpacity : 0)
                    .scaleEffect(
                        currentScreen == .details ? contentScale : 0.96
                    )
                    .blur(radius: currentScreen == .details ? 0 : 1)
                    .allowsHitTesting(currentScreen == .details)
                
                // Settings Screen
                SettingsScreenContent()
                    .opacity(currentScreen == .settings ? transitionOpacity : 0)
                    .scaleEffect(
                        currentScreen == .settings ? contentScale : 0.96
                    )
                    .blur(radius: currentScreen == .settings ? 0 : 1)
                    .allowsHitTesting(currentScreen == .settings)
                
                // Scan Mode Screen
                ScanModeScreenContent()
                    .opacity(currentScreen == .scanMode ? transitionOpacity : 0)
                    .scaleEffect(
                        currentScreen == .scanMode ? contentScale : 0.96
                    )
                    .blur(radius: currentScreen == .scanMode ? 0 : 1)
                    .allowsHitTesting(currentScreen == .scanMode)
            }
            // animations for page transitions
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
                // tabview ornament tracks pages
                OrnamentView(
                    currentScreen: $currentScreen,
                    onTabWillChange: { newTab in
                        performTabTransition(to: newTab)
                    }
                )
            }
            .ornament (
                visibility: .visible,
                attachmentAnchor: .scene(.bottom),
                contentAlignment: .top
            ) {
                // toolbar ornament tracks tools
                OrnamentView2(
                    showMeasurementOptions: $showMeasurementOptions,
                    showFocusModeSheet: $showFocusModeSheet,
                    showAIAssistantSheet: $showAIAssistantSheet,
                    showSharePlaySheet: $showSharePlaySheet
                )
            }
        }
        .onAppear { isImmersiveOpen = false }
        .task { await prepareExperience() }
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
            FocusModeSheet(isPresented: $showFocusModeSheet)
        }
        .sheet(isPresented: $showAIAssistantSheet) {
            AIAssistantSheet(isPresented: $showAIAssistantSheet)
        }
        .sheet(isPresented: $showSharePlaySheet) {
            SharePlaySheet(isPresented: $showSharePlaySheet)
        }
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
            return
        }
        controller.startLocalSession()
        hasInitializedSession = true
        await controller.preloadIfNeeded()
        await ensureImmersiveSpaceOpened()
    }
    
    private func ensureImmersiveSpaceOpened() async {
        guard isImmersiveOpen == false else { return }
        let result = await openImmersiveSpace(id: "CollaborativeSpace")
        if case .opened = result {
            await MainActor.run { isImmersiveOpen = true }
        }
    }
}

// MARK: - ORNAMENT VIEW 2 (Toolbar)
private struct OrnamentView2: View {
    @Binding var showMeasurementOptions: Bool
    @Binding var showFocusModeSheet: Bool
    @Binding var showAIAssistantSheet: Bool
    @Binding var showSharePlaySheet: Bool
    
    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack(spacing: 8) {
                        Button {
                            showFocusModeSheet = true
                        } label: {
                            Image(systemName: "eye")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        
                        Button {
                            showAIAssistantSheet = true
                        } label: {
                            Image(systemName: "microphone")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        
                        Button {
                            showMeasurementOptions = true
                        } label: {
                            Image(systemName: "ruler")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        
                        Button {
                            showSharePlaySheet = true
                        } label: {
                            Image(systemName: "person.2")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        
                        Menu {
                            Button("Item 1"){}
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                    }
                }
            }
    }
}

// MARK: - Ornament View (Navigation Tabs)
private struct OrnamentView: View {
    @Binding var currentScreen: StarterView.ScreenTab
    
    var onTabWillChange: ((StarterView.ScreenTab) -> Void)?
    
    // Internal state for TabView
    @State private var selectedTab: Int = 0
    @State private var isChangingTab = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Screen tabs (0-3)
            ForEach(StarterView.ScreenTab.allCases, id: \.rawValue) { screen in
                Color.clear
                    .tabItem {
                        Label(screen.label, systemImage: screen.icon)
                    }
                    .tag(screen.rawValue)
            }
        }
        .frame(width: 80, height: 450)
        .onAppear {
            selectedTab = currentScreen.rawValue
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            guard !isChangingTab else { return }
            handleTabChange(oldValue, newValue)
        }
        .onChange(of: currentScreen) { oldValue, newValue in
            // Sync the tab selection when screen changes programmatically
            if selectedTab != newValue.rawValue {
                isChangingTab = true
                selectedTab = newValue.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isChangingTab = false
                }
            }
        }
    }
    
    private func handleTabChange(_ oldValue: Int, _ newValue: Int) {
        // Check if it's a screen tab (0-3)
        if let screenTab = StarterView.ScreenTab(rawValue: newValue) {
            // Only trigger animation if actually changing screens
            if oldValue != newValue {
                onTabWillChange?(screenTab)
            }
        }
    }
}

// MARK: - Screen Contents
private struct HomeScreenContent: View {
    @ObservedObject var controller: CollaborativeSessionController
    @Binding var favoriteModels: Set<String>
    
    private enum Sorting: String, CaseIterable, Identifiable {
        case alphabetical = "Alphabetical"
        case dateAdded = "Date Added"
        case favorites = "Favorites"
        var id: String { rawValue }
    }
    
    private enum Category: String, CaseIterable, Identifiable {
        case seating = "Seating"
        case all = "All"
        case beds = "Beds"
        case storage = "Storage"
        case lighting = "Lighting"
        var id: String { rawValue }
    }
    
    private enum Source: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case scans = "Scans"
        case imports = "Imports"
        var id: String { rawValue }
    }
    
    @State private var selectedSource: Source = .presets
    @State private var sortMode: Sorting = .alphabetical
    @State private var selectedCategory: Category = .all
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Catalog").font(.largeTitle.bold())
                Spacer()
                
                HStack(spacing: 12) {
                    Picker("", selection: $selectedSource) {
                        ForEach(Source.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    
                    Picker("", selection: $sortMode) {
                        ForEach(Sorting.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 385)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(filtered(controller.availableModels)) { descriptor in
                        CatalogCell(
                            name: descriptor.name,
                            isFavorite: favoriteModels.contains(descriptor.name),
                            onFavoriteToggle: {
                                if favoriteModels.contains(descriptor.name) {
                                    favoriteModels.remove(descriptor.name)
                                } else {
                                    favoriteModels.insert(descriptor.name)
                                }
                            }
                        )
                        .onTapGesture { controller.addModel(descriptor) }
                        .contextMenu {
                            Button("Add") { controller.addModel(descriptor) }
                        }
                    }
                }
                .padding(16)
            }
            .glassBackground(cornerRadius: 24)
            .shadow(radius: 10)
        }
        .padding(24)
    }
    
    private func filtered(
        _ input: [CollaborativeSessionController.ModelDescriptor]
    ) -> [CollaborativeSessionController.ModelDescriptor] {
        var result = input
        
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch sortMode {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .dateAdded:
            break
        case .favorites:
            result = result.filter { favoriteModels.contains($0.name) }
        }
        return result
    }
}



private struct DetailsScreenContent: View {
    @ObservedObject var controller: CollaborativeSessionController
    @State private var roomName: String = ""
    
    var body: some View {
        VStack(spacing: 14) {
            // Header with room name
            HStack {
                Text("Project Details").font(.largeTitle.bold())
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { saveProject() }) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { loadProject() }) {
                        Label("Load", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Room Name Section (fixed, non-scrolling)
            VStack(alignment: .leading, spacing: 12) {
                Text("Room Name")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                TextField("Enter room name", text: $roomName)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Placed Models Section (scrollable)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Placed Models")
                        .font(.headline)
                    Spacer()
                    if !controller.placedModelSummaries.isEmpty {
                        Text("\(controller.placedModelSummaries.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.quaternary)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                if controller.placedModelSummaries.isEmpty {
                    // Empty state (non-scrolling when empty)
                    VStack(spacing: 16) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                        
                        Text("No models in scene")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        Text("Add models from the catalog to get started")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    // Models grid with scroll view
                    ScrollView {
                        VStack(spacing: 12) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                ForEach(controller.placedModelSummaries, id: \.self) { modelName in
                                    PlacedModelCard(
                                        name: modelName,
                                        onRemove: {
                                            controller.removeModel(named: modelName)
                                        }
                                    )
                                }
                            }
                            
                            // Remove all button
                            Button(action: { controller.removeAllModels() }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Clear All Models")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                        .padding(16)
                    }
                }
            }
            .glassBackground(cornerRadius: 24)
            .shadow(radius: 10)
        }
        .padding(24)
    }
    
    private func saveProject() {
        print("Save project: \(roomName) - NOT YET IMPLEMENTED")
        // TODO: Implement save functionality
    }
    
    private func loadProject() {
        print("Load project - NOT YET IMPLEMENTED")
        // TODO: Implement load functionality
    }
}

// MARK: - Placed Model Card
private struct PlacedModelCard: View {
    let name: String
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .frame(height: 100)
                
                // Remove button appears on hover
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .glassBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}


private struct SettingsScreenContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.largeTitle.bold())
            
            Spacer()
            
            Text("Settings will appear here")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(cornerRadius: 24)
        .padding(24)
    }
}

private struct ScanModeScreenContent: View {
    @State private var isScanningActive = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Scan Mode")
                .font(.largeTitle.bold())
            
            Image(systemName: "vision.pro.and.arrow.forward")
                .font(.system(size: 100))
                .foregroundStyle(.secondary)
            
            Text("Position your device to scan furniture and objects")
                .font(.title2)
                .multilineTextAlignment(.center)
            
            Button(action: {
                isScanningActive.toggle()
            }) {
                Label(
                    isScanningActive ? "Stop Scanning" : "Start Scanning",
                    systemImage: isScanningActive ? "stop.fill" : "play.fill"
                )
                .font(.title3)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            // TODO: Add actual scanning interface
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(cornerRadius: 24)
        .padding(24)
    }
}

// MARK: - Sheet Contents
private struct MeasurementSheet: View {
    @Binding var isPresented: Bool
    @State private var measurementUnit = "inches"
    @State private var showDimensions = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Measurement Tools")
                .font(.title)
                .bold()
            
            VStack(spacing: 20) {
                Picker("Unit", selection: $measurementUnit) {
                    Text("Inches").tag("inches")
                    Text("Feet").tag("feet")
                    Text("Centimeters").tag("cm")
                    Text("Meters").tag("m")
                }
                .pickerStyle(.segmented)
                
                Toggle("Show Dimensions on Objects", isOn: $showDimensions)
                    .padding(.vertical, 8)
                
                Button(action: { spawnRuler() }) {
                    Label("Spawn Virtual Ruler", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: { measureDistance() }) {
                    Label("Measure Distance", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer()
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 400)
    }
    
    private func spawnRuler() {
        print("Spawn Ruler - NOT YET IMPLEMENTED")
    }
    
    private func measureDistance() {
        print("Measure Distance - NOT YET IMPLEMENTED")
    }
}

private struct FocusModeSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Focus Mode")
                .font(.title)
                .bold()
            
            Image(systemName: "eye")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Enter an immersive environment to focus on your design without distractions")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button(action: {
                enterFocusMode()
                isPresented = false
            }) {
                Label("Enter Focus Mode", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 350)
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
    }
}

private struct AIAssistantSheet: View {
    @Binding var isPresented: Bool
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("AI Design Assistant")
                .font(.title)
                .bold()
            
            Image(systemName: "microphone")
                .font(.system(size: 60))
                .foregroundStyle(isListening ? .blue : .secondary)
                .symbolEffect(.variableColor.iterative, value: isListening)
            
            Text(isListening ? "Listening..." : "Tap to speak your design request")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Button(action: {
                isListening.toggle()
            }) {
                Label(
                    isListening ? "Stop Listening" : "Start Listening",
                    systemImage: isListening ? "stop.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 350)
    }
}

private struct SharePlaySheet: View {
    @Binding var isPresented: Bool
    @State private var sessionCode = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Text("SharePlay")
                .font(.title)
                .bold()
            
            Image(systemName: "person.2")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Collaborate with others in real-time")
                .font(.body)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                Button(action: { startSharePlay() }) {
                    Label("Start New Session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                HStack {
                    TextField("Session Code", text: $sessionCode)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Join") {
                        joinSharePlay()
                    }
                    .buttonStyle(.bordered)
                    .disabled(sessionCode.isEmpty)
                }
            }
            
            Spacer()
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 400)
    }
    
    private func startSharePlay() {
        print("Start SharePlay - NOT YET IMPLEMENTED")
    }
    
    private func joinSharePlay() {
        print("Join SharePlay with code: \(sessionCode) - NOT YET IMPLEMENTED")
    }
}

// MARK: - Supporting Views
private struct CatalogCell: View {
    let name: String
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .frame(height: 130)
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .glassBackground(cornerRadius: 20)
        .overlay(alignment: .topTrailing) {
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}

private extension View {
    func glassBackground(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

#Preview {
    StarterView(controller: CollaborativeSessionController())
}
