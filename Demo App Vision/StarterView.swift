import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var isImmersiveOpen = false

    @State private var hasInitializedSession = false
    @State private var isActivatingSharePlay = false
    @State private var sharePlayError: String?
    @State private var favoriteModels: Set<String> = []
    @State private var selectedTab = -1

    private enum Sorting: String, CaseIterable, Identifiable {
        case alphabetical = "Alphabetical",
             dateAdded = "Date Added",
             favorites = "Favorites"
        var id: String { rawValue }
    }
    private enum Category: String, CaseIterable, Identifiable {
        case seating = "Seating",
             all = "All",
             beds = "Beds",
             storage = "Storage",
             lighting = "Lighting"
        var id: String { rawValue }
    }
    private enum Source: String, CaseIterable, Identifiable {
            case presets = "Presets",
                 scans = "Scans",
                 imports = "Imports"
            var id: String { rawValue }
        }
    private enum UtilityPanel: Equatable { case none, save, load, settings, measure, scan }

    @State private var selectedSource: Source = .presets
    @State private var openPanel: UtilityPanel = .none
    @State private var sortMode: Sorting = .alphabetical
    @State private var selectedCategory: Category = .all
    @State private var searchText: String = ""

    var body: some View {
        ZStack {
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
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.tertiary)
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
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.leading),
                contentAlignment: .leading
            ) {
                OrnamentView()
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

    private func filtered(
        _ input: [CollaborativeSessionController.ModelDescriptor]
    ) -> [CollaborativeSessionController.ModelDescriptor] {
        var result = input
        
        switch selectedSource {
        case .presets, .scans, .imports:
            break
        }
        
        /// TODO: potentially add category search integration via ML
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch sortMode {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .dateAdded: /// TODO: discuss potentially removing date added functionality altogether?
            break
        case .favorites:
            result = result.filter { favoriteModels.contains($0.name) }
        }
        return result
    }
}

private struct OrnamentView: View {
    @State private var selectedTab = 0
    @State private var showSaveLoadMenu = false
    @State private var showSettings = false
    @State private var showMeasurementOptions = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Color.clear
                .tabItem {
                    Label("Details", systemImage: "folder")
                }
                .tag(0)
            
            Color.clear
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(1)
            
            Color.clear
                .tabItem {
                    Label("Scan Mode", systemImage: "vision.pro.and.arrow.forward")
                }
                .tag(2)
            
            Color.clear
                .tabItem {
                    Label("Focus Mode", systemImage: "eye")
                }
                .tag(3)
            
            Color.clear
                .tabItem {
                    Label("Assistant", systemImage: "microphone")
                }
                .tag(4)
            
            Color.clear
                .tabItem {
                    Label("Measure", systemImage: "ruler")
                }
                .tag(5)
            
            Color.clear
                .tabItem {
                    Label("SharePlay", systemImage: "person.2")
                }
                .tag(6)
        }
        .frame(width: 80, height: 400)
        .onChange(of: selectedTab) { oldValue, newValue in
            guard newValue >= 0 else { return }
            switch newValue {
            case 0: // saveload
                showSaveLoadMenu = true
            case 1: // Settings
                showSettings = true
            case 2: // Scan mode
                scanMode()
            case 3: // Focus Mode
                enterFocusMode()
            case 4: // AI Assistant
                activateAIAssistant()
            case 5: // Measure
                showMeasurementOptions = true
            case 6: // SharePlay
                activateSharePlay()
            default:
                break
            }
            selectedTab = -1
        }
        
        .popover(isPresented: $showSaveLoadMenu) {
            VStack(spacing: 16) {
                Text("Save/Load")
                    .font(.headline)
                
                Button(action: { saveProject() }) {
                    Label("Save Project", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: { loadProject() }) {
                    Label("Load Project", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 250, height: 150)
        }
        
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title)
                
                Text("Settings panel content goes here")
                    .foregroundStyle(.secondary)
                
                Button("Close") {
                    showSettings = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 400, height: 500)
        }
        
        .popover(isPresented: $showMeasurementOptions) {
            VStack(spacing: 16) {
                Text("Measurement Tools")
                    .font(.headline)
                
                Button(action: { spawnRuler() }) {
                    Label("Spawn Ruler", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: { toggleMeasurements() }) {
                    Label("Show Dimensions", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 250, height: 150)
        }
    }
    
    private func saveProject() {
        print("Save project - NOT YET IMPLEMENTED")
        // TODO: Implement save functionality
    }
    
    private func loadProject() {
        print("Load project - NOT YET IMPLEMENTED")
        // TODO: Implement load functionality
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
        // TODO: Switch to full VR experience
    }
    
    private func scanMode() {
        print("SCAN MODE _ NOT IMPLEMENTED")
        // TODO: Implement scan mode
    }
    
    private func activateAIAssistant() {
        print("AI Assistant - NOT YET IMPLEMENTED")
        // TODO: Activate voice/AI assistant
    }
    
    private func spawnRuler() {
        print("Spawn Ruler - NOT YET IMPLEMENTED")
        // TODO: Spawn virtual ruler in scene
    }
    
    private func toggleMeasurements() {
        print("Toggle Measurements - NOT YET IMPLEMENTED")
        // TODO: Show/hide measurements on furniture
    }
    
    private func activateSharePlay() {
        print("SharePlay - NOT YET IMPLEMENTED")
        // TODO: Activate SharePlay session
    }
}

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
