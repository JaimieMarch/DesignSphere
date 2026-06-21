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

    private let searchEngine = ModelSearchEngine()

    @ObservedObject private var downloads = RemoteDownloadProgress.shared

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ScrollView {
                    LazyVGrid(columns: gridColumns(for: proxy.size.width), spacing: 14) {
                        ForEach(filteredModels) { descriptor in
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
                                modelType: descriptor.type,
                                downloadFraction: downloads.fraction(for: descriptor.id)
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
                .scrollIndicators(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .glassBackground(cornerRadius: 24)
                .shadow(radius: 10)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var filteredModels: [CollaborativeSessionController.ModelDescriptor] {
        filtered(controller.availableModels)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Catalog")
                    .font(.largeTitle.bold())
                    .lineLimit(1)

                Text("\(filteredModels.count) items available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                sourceFilter
                categoryFilter
                sortFilter
                searchField
            }
            .frame(maxWidth: 860, alignment: .trailing)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Search models", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .accessibilityLabel("Search models")
                .accessibilityHint("Type to filter models by name")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private var sourceFilter: some View {
        Menu {
            ForEach(CollaborativeSessionController.ModelSource.allCases, id: \.self) { source in
                if source != .unknown {
                    Button {
                        selectedSource = source
                    } label: {
                        if selectedSource == source {
                            Label(source.label, systemImage: "checkmark")
                        } else {
                            Text(source.label)
                        }
                    }
                }
            }
        } label: {
            filterCapsule(title: "Source", value: selectedSource.label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model source filter")
        .accessibilityHint("Filter models by presets, scans, or imports")
    }

    private var categoryFilter: some View {
        Menu {
            ForEach(CollaborativeSessionController.ModelCategory.allCases, id: \.self) { category in
                if category != .unknown {
                    Button {
                        selectedCategory = category
                    } label: {
                        if selectedCategory == category {
                            Label(category.label, systemImage: "checkmark")
                        } else {
                            Text(category.label)
                        }
                    }
                }
            }
        } label: {
            filterCapsule(title: "Category", value: selectedCategory.label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Category")
        .accessibilityHint("Filter models by furniture category")
    }

    private var sortFilter: some View {
        Menu {
            ForEach(Sorting.allCases) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if sortMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            filterCapsule(title: "Sort", value: sortMode.rawValue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort order")
        .accessibilityHint("Sort models alphabetically, by date, or show favorites only")
    }

    private func filterCapsule(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 132, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let minColumnWidth: CGFloat = availableWidth > 1200 ? 220 : 200
        return [GridItem(.adaptive(minimum: minColumnWidth, maximum: 280), spacing: 14)]
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

        // When searching, the engine both filters and orders by intent relevance,
        // so we preserve that ranking instead of re-sorting alphabetically.
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            result = searchEngine.search(searchText, in: result)
        }

        switch sortMode {
        case .alphabetical:
            if !isSearching {
                result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        case .dateAdded:
            if !isSearching {
                result.sort { lhs, rhs in
                    (lhs.dateAdded ?? .distantPast) > (rhs.dateAdded ?? .distantPast)
                }
            }
        case .favorites:
            result = result.filter { favoriteModels.contains($0.name) }
            if !isSearching {
                result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        }
        return result
    }
}
