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
                MinimalOrnament()
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .glassBackground(cornerRadius: 35)
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

@available(visionOS 26.0, *)
private struct MinimalOrnament: View {
    @State private var hoveredButton: String? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            OrnamentButton(icon: "square.grid.2x2", label: "Grid", isHovered: hoveredButton == "grid")
                .onHover { hoveredButton = $0 ? "grid" : nil }
            
            OrnamentButton(icon: "slider.horizontal.3", label: "Settings", isHovered: hoveredButton == "settings")
                .onHover { hoveredButton = $0 ? "settings" : nil }
            
            OrnamentButton(icon: "person.2", label: "Share", isHovered: hoveredButton == "share")
                .onHover { hoveredButton = $0 ? "share" : nil }
        }
        .padding(4)
    }
}

private struct OrnamentButton: View {
    let icon: String
    let label: String
    let isHovered: Bool
    
    var body: some View {
        TabView {
                    Text("List")
                        .tabItem {
                            Label("List", systemImage: "checklist")
                        }
                    
                    Text("Favorites")
                        .tabItem {
                            Label("Favorites", systemImage: "star")
                        }
                }
//        Button(action: {}) {
//            VStack(spacing: 4) {
//                Image(systemName: icon)
//                    .imageScale(.small)
//                    .frame(width: 16, height: 16)
//                
//                if isHovered {
//                    Text(label)
//                        .font(.caption2)
//                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
//                }
//            }
//            .padding(.horizontal, 6)
//            .padding(.vertical, isHovered ? 8 : 6)
//            .contentShape(Rectangle())
//        }
//        .buttonStyle(.plain)
//        .background {
//            if isHovered {
//                RoundedRectangle(cornerRadius: 8, style: .continuous)
//                    .fill(.quaternary)
//            }
//        }
//        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

private struct CatalogCell: View {
    let name: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .frame(height: 90)
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140)
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
