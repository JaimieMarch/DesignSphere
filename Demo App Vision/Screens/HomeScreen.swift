// Main catalog screen shown the app
// Displays all available models
// Provides sorting, category filtering, search, marking items as favorites
// Tapping a model places it into the AR scene via the XRShare controller
// Uses CatalogCell to display each model with name and thumbnail

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

    @State private var selectedSource: CollaborativeSessionController.ModelSource = .all
    @State private var sortMode: Sorting = .alphabetical
    @State private var selectedCategory: CollaborativeSessionController.ModelCategory = .all
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Catalog").font(.largeTitle.bold())
                Spacer()
                
                HStack(spacing: 12) {
                    Picker("Model source", selection: $selectedSource) {
                        ForEach(CollaborativeSessionController.ModelSource.allCases, id: \.self) { source in
                            if source != .unknown {
                                Text(source.label).tag(source)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .accessibilityLabel("Model source filter")
                    .accessibilityHint("Filter models by presets, scans, or imports")

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CollaborativeSessionController.ModelCategory.allCases, id: \.self) { category in
                            if category != .unknown {
                                Text(category.label).tag(category)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    .accessibilityLabel("Category")
                    .accessibilityHint("Filter models by furniture category")

                    Picker("Sort order", selection: $sortMode) {
                        ForEach(Sorting.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .accessibilityLabel("Sort order")
                    .accessibilityHint("Sort models alphabetically, by date, or show favorites only")

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                            .accessibilityLabel("Search models")
                            .accessibilityHint("Type to filter models by name")
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
                        let isFavorite = favoriteModels.contains(descriptor.name)
                        CatalogCell(
                            name: descriptor.name,
                            isFavorite: isFavorite,
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
                        .accessibilityLabel("\(descriptor.name)\(isFavorite ? ", favorited" : "")")
                        .accessibilityHint("Tap to add \(descriptor.name) to your design")
                        .accessibilityAddTraits(.isButton)
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
        
        if selectedSource != .all {
            result = result.filter { $0.source == selectedSource }
        }

        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch sortMode {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .dateAdded:
            result.sort { lhs, rhs in
                (lhs.dateAdded ?? .distantPast) > (rhs.dateAdded ?? .distantPast)
            }
        case .favorites:
            result = result.filter { favoriteModels.contains($0.name) }
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return result
    }
}
