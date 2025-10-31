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
                contentAlignment: .trailing
            ) {
                OrnamentView()
                    .padding()
                    .glassBackgroundEffect()
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
    @State private var hoveredButton: String? = nil
    @State private var showSaveLoadMenu = false
    @State private var showSettings = false
    @State private var showMeasurementOptions = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Details button
            HoverButton(
                icon: "folder",
                label: "Details",
                isHovered: hoveredButton == "details"
            ) {
                showSaveLoadMenu = true
            }
            .onHover { hoveredButton = $0 ? "details" : nil }
            .popover(isPresented: $showSaveLoadMenu, attachmentAnchor: .point(.trailing)) {
                SaveLoadMenu()
            }
            
            /// I give up :)
            Button {   } label: {
                Label("Trashcan", systemImage: "trash")
            }
            
            // Settings button
            HoverButton(
                icon: "gearshape",
                label: "Settings",
                isHovered: hoveredButton == "settings"
            ) {
                showSettings = true
            }
            .onHover { hoveredButton = $0 ? "settings" : nil }
            .sheet(isPresented: $showSettings) {
                SettingsPanel(isPresented: $showSettings)
            }
            
            // Scan Mode button
            HoverButton(
                icon: "vision.pro.and.arrow.forward",
                label: "Scan Mode",
                isHovered: hoveredButton == "scan"
            ) {
                scanMode()
            }
            .onHover { hoveredButton = $0 ? "scan" : nil }
            
            // Focus Mode button
            HoverButton(
                icon: "eye",
                label: "Focus Mode",
                isHovered: hoveredButton == "focus"
            ) {
                enterFocusMode()
            }
            .onHover { hoveredButton = $0 ? "focus" : nil }
            
            // Assistant button
            HoverButton(
                icon: "microphone",
                label: "Assistant",
                isHovered: hoveredButton == "assistant"
            ) {
                activateAIAssistant()
            }
            .onHover { hoveredButton = $0 ? "assistant" : nil }
            
            // Measure button
            HoverButton(
                icon: "ruler",
                label: "Measure",
                isHovered: hoveredButton == "measure"
            ) {
                showMeasurementOptions = true
            }
            .onHover { hoveredButton = $0 ? "measure" : nil }
            .popover(isPresented: $showMeasurementOptions, attachmentAnchor: .point(.trailing)) {
                MeasurementMenu()
            }
            
            // SharePlay button
            HoverButton(
                icon: "person.2",
                label: "SharePlay",
                isHovered: hoveredButton == "shareplay"
            ) {
                activateSharePlay()
            }
            .onHover { hoveredButton = $0 ? "shareplay" : nil }
        }
    }
    
    private func saveProject() {
        print("Save project - NOT YET IMPLEMENTED")
    }
    
    private func loadProject() {
        print("Load project - NOT YET IMPLEMENTED")
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
    }
    
    private func scanMode() {
        print("SCAN MODE - NOT IMPLEMENTED")
    }
    
    private func activateAIAssistant() {
        print("AI Assistant - NOT YET IMPLEMENTED")
    }
    
    private func spawnRuler() {
        print("Spawn Ruler - NOT YET IMPLEMENTED")
    }
    
    private func toggleMeasurements() {
        print("Toggle Measurements - NOT YET IMPLEMENTED")
    }
    
    private func activateSharePlay() {
        print("SharePlay - NOT YET IMPLEMENTED")
    }
}

// MARK: - Hover Button Component

private struct HoverButton: View {
    let icon: String
    let label: String
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 24, height: 24)
                
                if isHovered {
                    Text(label)
                        .font(.caption)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isHovered ? 12 : 8)
            .padding(.vertical, 8)
            .frame(minWidth: isHovered ? nil : 40, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Popup Views

private struct SaveLoadMenu: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Save/Load")
                .font(.headline)
            
            Button(action: { print("Save") }) {
                Label("Save Project", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(action: { print("Load") }) {
                Label("Load Project", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 250, height: 150)
    }
}

private struct SettingsPanel: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
            
            Text("Settings panel content goes here")
                .foregroundStyle(.secondary)
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

private struct MeasurementMenu: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Measurement Tools")
                .font(.headline)
            
            Button(action: { print("Spawn Ruler") }) {
                Label("Spawn Ruler", systemImage: "ruler")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(action: { print("Toggle Measurements") }) {
                Label("Show Dimensions", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 250, height: 150)
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
