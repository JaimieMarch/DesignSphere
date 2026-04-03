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
    @State private var pendingSaveRoomName: String = ""

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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Room Name Section
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
                    .accessibilityLabel("Room name")
                    .accessibilityHint("Enter a name for your room project")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            VStack(spacing: 0) {
                HStack {
                    Text("Placed Models")
                        .font(.headline)
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
                }

                // Scrollable Content Area
                ScrollView {
                    if controller.placedModelDescriptors.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "cube.transparent")
                                .font(.largeTitle)
                                .imageScale(.large)
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
                        .padding(.vertical, 80)
                    } else {
                        // Models grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
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
                            }
                        }
                        .padding(16)
                    }
                }

                if !controller.placedModelDescriptors.isEmpty {
                    Divider()

                    Button(action: {
                        Task { await controller.removeAllModels() }
                    }) {
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

                // Update the room name field
                self.roomName = ""

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

                showAlert = true
            } catch {
                alertMessage = "Failed to load project: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
