import SwiftUI
import XRShareCollaboration

struct LoadProjectSheet: View {
    @ObservedObject var projectManager: ProjectManager
    let controller: CollaborativeSessionController
    var onLoadProject: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var projectToDelete: String?
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if projectManager.savedProjects.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.tertiary)

                        Text("No Saved Projects")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text("Save your current scene to create a project")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // List of saved projects
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(projectManager.savedProjects, id: \.roomName) { project in
                                ProjectRow(
                                    project: project,
                                    onLoad: {
                                        onLoadProject(project.roomName)
                                    },
                                    onDelete: {
                                        projectToDelete = project.roomName
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Load Project")
            .onAppear { projectManager.loadProjectList() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Project", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let name = projectToDelete {
                        deleteProject(name: name)
                    }
                }
            } message: {
                if let name = projectToDelete {
                    Text("Are you sure you want to delete '\(name)'? This action cannot be undone.")
                }
            }
            .alert("Couldn't delete project", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func deleteProject(name: String) {
        Task {
            do {
                try await projectManager.deleteProject(roomName: name, controller: controller)
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }
}

struct ProjectRow: View {
    let project: ProjectData
    var onLoad: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.roomName)
                    .font(.headline)

                HStack(spacing: 16) {
                    Label("\(project.models.count) models", systemImage: "cube")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(dateFormatter.string(from: project.dateModified), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if project.worldAnchorID != nil {
                    Label("World anchor saved", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: 16) {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete \(project.roomName)")
                .accessibilityHint("Permanently delete this saved project")

                Button(action: onLoad) {
                    Text("Load")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Load \(project.roomName)")
                .accessibilityHint("Load this project into the scene")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}
