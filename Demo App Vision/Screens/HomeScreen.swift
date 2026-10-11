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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private enum Sorting: String, CaseIterable, Identifiable {
        case alphabetical = "Alphabetical"
        case dateAdded = "Date Added"
        case favorites = "Favorites"
        var id: String { rawValue }
    }

    /// Textured models ship with their own materials; "Customizable" ones are
    /// blank geometry the user colors/textures in the editor.
    private enum Finish: String, CaseIterable, Identifiable {
        case all = "All"
        case textured = "Textured"
        case customizable = "Customizable"
        var id: String { rawValue }
    }

    @State private var selectedSource: CollaborativeSessionController.ModelSource = .all
    @State private var sortMode: Sorting = .alphabetical
    @State private var selectedCategory: CollaborativeSessionController.ModelCategory = .all
    @State private var selectedFinish: Finish = .all
    @State private var searchText: String = ""
    @State private var catalogLoadingSince: Date?

    private let searchEngine = ModelSearchEngine()

    @ObservedObject private var downloads = RemoteDownloadProgress.shared

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                headerSection(availableWidth: proxy.size.width)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ScrollView {
                    if controller.remoteCatalogState == .unavailable && controller.availableModels.isEmpty {
                        catalogUnavailableView
                    } else if controller.remoteCatalogState == .loading && controller.availableModels.isEmpty {
                        // Show the loading state even when a stale list is still
                        // in `availableModels` — those entries are not
                        // placeable while the catalog is being refetched.
                        catalogLoadingView
                    } else if filteredModels.isEmpty {
                        catalogNoResultsView
                    } else {
                    if controller.remoteCatalogState == .unavailable {
                        catalogUnavailableView
                    }
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
                                downloadFraction: downloads.fraction(for: descriptor.id),
                                downloadFailed: downloads.isFailed(descriptor.id),
                                downloadUnavailable: downloads.isPermanentlyFailed(descriptor.id),
                                retryDate: downloads.retryDate(for: descriptor.id),
                                onRetry: {
                                    downloads.clearFailure(descriptor.id)
                                    controller.addModel(descriptor)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { controller.addModel(descriptor) }
                            .contextMenu {
                                Button("Add") { controller.addModel(descriptor) }
                            }
                            // The cell holds several accessible children (favorite
                            // button, retry button). `.contain` keeps them
                            // reachable while still giving the tile a name of its
                            // own, and the explicit action makes the tap gesture
                            // available to assistive technologies.
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(descriptor.name)\(isFavorite ? ", favorited" : "")")
                            .accessibilityHint(accessibilityHint(for: descriptor))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { controller.addModel(descriptor) }
                        }
                    }
                    .padding(16)
                    }
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

    private func accessibilityHint(
        for descriptor: CollaborativeSessionController.ModelDescriptor
    ) -> String {
        if let size = descriptor.type.remoteDownloadSizeLabel {
            return "Tap to download \(size) on first use and add \(descriptor.name) to your design"
        }
        return "Tap to add \(descriptor.name) to your design"
    }

    private var catalogLoadingView: some View {
        // A slow network can hold this for many seconds; after a few, say so,
        // rather than leaving a spinner that reads as a hang.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let waited = context.date.timeIntervalSince(catalogLoadingSince ?? context.date)
            VStack(spacing: 14) {
                ProgressView()
                Text(waited >= 4 ? "Still connecting to the furniture catalog…" : "Loading catalog…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .accessibilityElement(children: .combine)
        }
        .onAppear { catalogLoadingSince = Date() }
        .onDisappear { catalogLoadingSince = nil }
    }

    private var catalogCountText: String {
        let shown = filteredModels.count
        let total = controller.availableModels.count
        if shown == total {
            return "\(total) models"
        }
        return "\(shown) of \(total) models"
    }

    /// Sources/categories actually present in the catalog, so filter menus don't
    /// offer options that would always come up empty.
    private var availableSources: Set<CollaborativeSessionController.ModelSource> {
        Set(controller.availableModels.map { $0.source })
    }

    private var availableCategories: Set<CollaborativeSessionController.ModelCategory> {
        Set(controller.availableModels.map { $0.category })
    }

    private var hasActiveFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedSource != .all
            || selectedCategory != .all
            || selectedFinish != .all
    }

    private func clearFilters() {
        searchText = ""
        selectedSource = .all
        selectedCategory = .all
        selectedFinish = .all
        if sortMode == .favorites { sortMode = .alphabetical }
    }

    @ViewBuilder
    private var catalogNoResultsView: some View {
        let isFavorites = sortMode == .favorites && !hasActiveFilter
        VStack(spacing: 14) {
            Image(systemName: isFavorites ? "star" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(isFavorites ? "No favorites yet" : "No models match")
                .font(.title3.weight(.semibold))
            Text(isFavorites
                 ? "Tap the star on any model to add it to your favorites."
                 : "Try a different search, or clear your filters to see the full catalog.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if isFavorites {
                Button { sortMode = .alphabetical } label: {
                    Label("Browse all", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { clearFilters() } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
    }

    private var catalogUnavailableView: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Catalog unavailable")
                .font(.title3.weight(.semibold))
            Text("Couldn't load the model catalog. Check your connection and try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                Task { await controller.loadRemoteCatalog() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: controller.availableModels.isEmpty ? 280 : 160)
        .padding(24)
    }

    private func headerSection(availableWidth: CGFloat) -> some View {
        let needsFilterRow = dynamicTypeSize.isAccessibilitySize || availableWidth < 1100
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Catalog")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(catalogCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if needsFilterRow {
                    searchField
                } else {
                    filterControls(includingSearch: true)
                }
            }
            if needsFilterRow {
                ScrollView(.horizontal) { filterControls(includingSearch: false) }
                    .scrollIndicators(.hidden)
            }
        }
    }

    private func filterControls(includingSearch: Bool) -> some View {
        HStack(spacing: 12) {
            sourceFilter
            categoryFilter
            finishFilter
            sortFilter
            if includingSearch { searchField }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Search models", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 280 : 180)
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
                if source == .all || availableSources.contains(source) {
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
        .accessibilityHint("Filter models by presets or your imports")
    }

    private var categoryFilter: some View {
        Menu {
            ForEach(CollaborativeSessionController.ModelCategory.allCases, id: \.self) { category in
                if category == .all || availableCategories.contains(category) {
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

    private var finishFilter: some View {
        Menu {
            ForEach(Finish.allCases) { finish in
                Button {
                    selectedFinish = finish
                } label: {
                    if selectedFinish == finish {
                        Label(finish.rawValue, systemImage: "checkmark")
                    } else {
                        Text(finish.rawValue)
                    }
                }
            }
        } label: {
            filterCapsule(title: "Finish", value: selectedFinish.rawValue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finish")
        .accessibilityHint("Show textured models, or customizable (untextured) ones")
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

        switch selectedFinish {
        case .all:
            break
        case .textured:
            result = result.filter { $0.type.hasBakedMaterials }
        case .customizable:
            result = result.filter { !$0.type.hasBakedMaterials }
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
