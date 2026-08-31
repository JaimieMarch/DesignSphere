// The project details screen shown from main UI
// Displays the project name, placed models, and actions like save/load/export
// Shows a grid of all models currently placed in AR scene
// Provides options to remove individual models or clear them all

import SwiftUI
import XRShareCollaboration

struct DetailsScreen: View {
    @ObservedObject var controller: CollaborativeSessionController
    @StateObject private var projectManager = ProjectManager()
    @State private var roomName: String = ""
    @State private var showLoadSheet: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showOverwriteConfirmation: Bool = false
    @State private var showClearAllConfirmation: Bool = false
    @State private var pendingSaveRoomName: String = ""

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Projects")
                                .font(.largeTitle.bold())
                                .lineLimit(1)
                                .accessibilityAddTraits(.isHeader)

                            Text(projectSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 12) {
                            Button(action: { saveProject() }) {
                                Label("Save", systemImage: "square.and.arrow.down")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(roomName.isEmpty)
                            .accessibilityLabel("Save project")
                            .accessibilityHint("Save the current scene as a project")

                            Button(action: { showLoadSheet = true }) {
                                Label("Load", systemImage: "square.and.arrow.up")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Load project")
                            .accessibilityHint("Open a previously saved project")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Project Name")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)

                        TextField("Enter project name", text: $roomName)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.thinMaterial)
                            )
                            .accessibilityLabel("Project name")
                            .accessibilityHint("Enter a name for your room project")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Placed Models")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text("Manage the models currently in your scene.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !controller.placedModelDescriptors.isEmpty {
                            Text("\(controller.placedModelDescriptors.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.quaternary)
                                )
                                .accessibilityLabel("\(controller.placedModelDescriptors.count) models in scene")
                        }
                    }
                    .padding(16)

                    Divider()

                    if projectManager.isStreamingProject {
                        VStack(spacing: 8) {
                            ProgressView(value: projectManager.streamingProgress)
                            Text("Restoring models \(Int(projectManager.streamingProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }

                    ScrollView {
                        if controller.placedModelDescriptors.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "cube.transparent")
                                    .font(.largeTitle)
                                    .imageScale(.large)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)

                                Text("No models in scene")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                Text("Add models from the catalog to get started")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                        } else {
                            LazyVGrid(columns: gridColumns(for: proxy.size.width), spacing: 14) {
                                ForEach(controller.placedModelDescriptors) { descriptor in
                                    CatalogCell(
                                        name: descriptor.name,
                                        isFavorite: false,
                                        onFavoriteToggle: {},
                                        modelType: descriptor.type,
                                        showRemove: true,
                                        onRemove: {
                                            controller.removeModelById(withInstanceID: descriptor.id)
                                        }
                                    )
                                    .accessibilityElement(children: .contain)
                                    .accessibilityLabel(descriptor.name)
                                }
                            }
                            .padding(16)
                        }
                    }

                    if !controller.placedModelDescriptors.isEmpty {
                        Divider()

                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear All Models")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(16)
                        .accessibilityLabel("Clear all models")
                        .accessibilityHint("Remove all placed models from the scene")
                    }
                }
                .glassBackground(cornerRadius: 24)
                .shadow(radius: 10)
            }
            .padding(24)
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadProjectSheet(
                projectManager: projectManager,
                controller: controller,
                onLoadProject: { selectedRoomName in
                    showLoadSheet = false
                    loadProject(roomName: selectedRoomName)
                }
            )
        }
        .alert("Project", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Overwrite Project?", isPresented: $showOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingSaveRoomName = ""
            }
            Button("Overwrite", role: .destructive) {
                performSave(roomName: pendingSaveRoomName, skipCheck: true)
                pendingSaveRoomName = ""
            }
        } message: {
            Text("A project named '\(pendingSaveRoomName)' already exists. Do you want to overwrite it?")
        }
        .confirmationDialog(
            "Clear All Models?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Models", role: .destructive) {
                Task { await controller.removeAllModels() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every model from the scene. This action cannot be undone.")
        }
    }

    private var projectSummary: String {
        if controller.placedModelDescriptors.isEmpty {
            return "No models placed yet"
        }
        return "\(controller.placedModelDescriptors.count) model\(controller.placedModelDescriptors.count == 1 ? "" : "s") in the current scene"
    }

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let minColumnWidth: CGFloat = availableWidth > 1200 ? 220 : 200
        return [GridItem(.adaptive(minimum: minColumnWidth, maximum: 280), spacing: 14)]
    }

    private func saveProject() {
        guard !roomName.isEmpty else {
            alertMessage = "Please enter a room name"
            showAlert = true
            return
        }

        performSave(roomName: roomName, skipCheck: false)
    }

    private func performSave(roomName: String, skipCheck: Bool) {
        // Check if project already exists and we haven't confirmed overwrite
        if !skipCheck && projectManager.getProject(named: roomName) != nil {
            pendingSaveRoomName = roomName
            showOverwriteConfirmation = true
            return
        }

        Task {
            do {
                #if os(visionOS)
                // Create or get the world anchor for this room
                let worldAnchorID: UUID?
                if let existingAnchorID = projectManager.currentWorldAnchorID {
                    worldAnchorID = existingAnchorID
                } else {
                    worldAnchorID = try await projectManager.createWorldAnchor(controller: controller)
                }

                // Save the project to JSON
                try projectManager.saveProject(
                    roomName: roomName,
                    placedModels: controller.currentPlacedModels,
                    worldAnchorID: worldAnchorID,
                    sharedAnchor: controller.sharedAnchorEntity
                )

                alertMessage = "Project '\(roomName)' saved successfully!"
                showAlert = true
                // Keep the room name after save so user can easily update the project
                #else
                alertMessage = "World anchor saving is only available on visionOS"
                showAlert = true
                #endif
            } catch {
                alertMessage = "Failed to save project: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func loadProject(roomName: String) {
        Task {
            do {
                // Load the project from JSON
                let anchorStatus = try await projectManager.loadProject(
                    roomName: roomName,
                    controller: controller,
                    sharedAnchor: controller.sharedAnchorEntity
                )

                // Keep the loaded project name in the field so save/update remains immediate.
                self.roomName = roomName

                switch anchorStatus {
                case .noneSaved:
                    alertMessage = "Project '\(roomName)' loaded successfully."
                case .restored(let anchorID):
                    alertMessage = "Project '\(roomName)' loaded and relocalized to world anchor \(anchorID.uuidString.prefix(8))..."
                case .fallbackTransform(let anchorID):
                    alertMessage = "Project '\(roomName)' loaded using the last saved anchor transform because world anchor \(anchorID.uuidString.prefix(8))... could not be relocalized."
                case .missing(let anchorID):
                    alertMessage = "Project '\(roomName)' loaded, but world anchor \(anchorID.uuidString.prefix(8))... was unavailable. Models were restored without room relocalization."
                }

                // Restoring is best-effort: a saved model whose type left the
                // catalog, or whose usdz will not download, cannot come back.
                // Never report plain success over a half-empty room.
                if let shortfall = projectManager.lastLoadSummary?.shortfallDescription {
                    alertMessage += " \(shortfall)"
                }

                showAlert = true
            } catch {
                alertMessage = "Failed to load project: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
