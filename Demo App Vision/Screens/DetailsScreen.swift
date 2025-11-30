import SwiftUI
import XRShareCollaboration

struct DetailsScreen: View {
    @ObservedObject var controller: CollaborativeSessionController
    @StateObject private var projectManager = ProjectManager()
    @State private var roomName: String = ""
    @State private var showLoadSheet: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

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

                    Button(action: { showLoadSheet = true }) {
                        Label("Load", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { exportProject() }) {
                        Label("Export", systemImage: "mediastick")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
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

                // Scrollable Content Area
                ScrollView {
                    if controller.placedModelDescriptors.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 64))
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
                                        controller.removeModel(named: descriptor.name)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }

                if !controller.placedModelDescriptors.isEmpty {
                    Divider()

                    Button(action: { controller.removeAllModels() }) {
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
                }
            }
            .glassBackground(cornerRadius: 24)
            .shadow(radius: 10)
        }
        .padding(24)
        .sheet(isPresented: $showLoadSheet) {
            LoadProjectSheet(
                projectManager: projectManager,
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
    }

    private func saveProject() {
        guard !roomName.isEmpty else {
            alertMessage = "Please enter a room name"
            showAlert = true
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
                let worldAnchorID = try await projectManager.loadProject(
                    roomName: roomName,
                    controller: controller,
                    sharedAnchor: controller.sharedAnchorEntity
                )

                // Update the room name field
                self.roomName = roomName

                if let anchorID = worldAnchorID {
                    alertMessage = "Project '\(roomName)' loaded! World anchor ID: \(anchorID.uuidString.prefix(8))..."
                } else {
                    alertMessage = "Project '\(roomName)' loaded successfully!"
                }

                showAlert = true
            } catch {
                alertMessage = "Failed to load project: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func exportProject() {
        print("Export project - NOT YET IMPLEMENTED")
    }
}
