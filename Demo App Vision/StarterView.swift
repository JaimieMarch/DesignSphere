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

    private enum Sorting: String, CaseIterable, Identifiable {
        case alphabetical = "Alphabetical",
             dateAdded = "Date Added"
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
                        .frame(width: 280)
                        
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(filtered(controller.availableModels)) { descriptor in
                            CatalogCell(name: descriptor.name)
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
            .navigationTitle("Design Sphere")
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
        
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch sortMode {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .dateAdded:
            break
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
                    Label("Save/Load", systemImage: "folder")
                }
                .tag(0)
            
            Color.clear
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)
            
            Color.clear
                .tabItem {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tag(2)
            
            Color.clear
                .tabItem {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .tag(3)
            
            Color.clear
                .tabItem {
                    Label("Focus Mode", systemImage: "eye")
                }
                .tag(4)
            
            Color.clear
                .tabItem {
                    Label("AI Assistant", systemImage: "mic")
                }
                .tag(5)
            
            Color.clear
                .tabItem {
                    Label("Measure", systemImage: "ruler")
                }
                .tag(6)
            
            Color.clear
                .tabItem {
                    Label("SharePlay", systemImage: "person.2")
                }
                .tag(7)
        }
        .frame(width: 80, height: 400)
        .onChange(of: selectedTab) { oldValue, newValue in
            switch newValue {
            case 0: // Save/Load
                showSaveLoadMenu = true
            case 1: // Settings
                showSettings = true
            case 2: // Undo
                performUndo()
            case 3: // Redo
                performRedo()
            case 4: // Focus Mode
                enterFocusMode()
            case 5: // AI Assistant
                activateAIAssistant()
            case 6: // Measure
                showMeasurementOptions = true
            case 7: // SharePlay
                activateSharePlay()
            default:
                break
            }
            selectedTab = oldValue // Reset so button doesn't stay selected
        }
        
        // Save/Load Popover
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
        
        // Settings Sheet
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
        
        // Measurement Options Popover
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
    
    // MARK: - Action Functions (Placeholders)
    
    private func saveProject() {
        print("Save project - NOT YET IMPLEMENTED")
        // TODO: Implement save functionality
    }
    
    private func loadProject() {
        print("Load project - NOT YET IMPLEMENTED")
        // TODO: Implement load functionality
    }
    
    private func performUndo() {
        print("Undo - NOT YET IMPLEMENTED")
        // TODO: Implement undo
    }
    
    private func performRedo() {
        print("Redo - NOT YET IMPLEMENTED")
        // TODO: Implement redo
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
        // TODO: Switch to full VR experience
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
                .frame(height: 32)  // Fixed height for text area
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 200)  // Fixed height instead of minHeight
        .glassBackground(cornerRadius: 20)
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
