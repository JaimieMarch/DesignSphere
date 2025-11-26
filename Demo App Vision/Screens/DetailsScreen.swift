import SwiftUI
import XRShareCollaboration

struct DetailsScreen: View {
    @ObservedObject var controller: CollaborativeSessionController
    @State private var roomName: String = ""
    
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
                    
                    Button(action: { loadProject() }) {
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(controller.placedModelDescriptors) { descriptor in
                                PlacedModelCard(
                                    name: descriptor.name,
                                    modelType: descriptor.type,
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
    }
    
    private func saveProject() {
        print("Save project: \(roomName) - NOT YET IMPLEMENTED")
    }
    
    private func loadProject() {
        print("Load project - NOT YET IMPLEMENTED")
    }
    
    private func exportProject() {
        print("Export project - NOT YET IMPLEMENTED")
    }
}
