import SwiftUI
import XRShareCollaboration

struct HomeScreen: View {
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
                            },
                            modelType: descriptor.type
                        )
                        .onTapGesture { controller.addModel(descriptor) }
                        .contextMenu {
                            Button("Add") { controller.addModel(descriptor) }
                        }
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
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
