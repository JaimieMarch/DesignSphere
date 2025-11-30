import Foundation
import ARKit
import RealityKit
import XRShareCollaboration

@MainActor
class ProjectManager: ObservableObject {
    @Published var savedProjects: [ProjectData] = []
    @Published var currentWorldAnchorID: UUID?

    // app data is sandboxed **************************
    private let fileManager = FileManager.default
    private var projectsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("DesignSphereProjects", isDirectory: true)
    }

    init() {
        createProjectsDirectoryIfNeeded()
        loadProjectList()
    }

    // MARK: - Directory Management

    private func createProjectsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            print("Created projects directory at: \(projectsDirectory.path)")
        }
    }

    private func projectFileURL(for roomName: String) -> URL {
        let sanitized = roomName.replacingOccurrences(of: "/", with: "-")
        return projectsDirectory.appendingPathComponent("\(sanitized).json")
    }

    // MARK: - World Anchor Management

    #if os(visionOS)
    /// Creates and saves a persistent world anchor for the current room
    func createWorldAnchor(controller: CollaborativeSessionController) async throws -> UUID {
        // Create a world anchor at the origin
        let worldAnchor = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)

        // Save the anchor ID for persistence
        currentWorldAnchorID = worldAnchor.id

        print("Created world anchor with ID: \(worldAnchor.id)")
        return worldAnchor.id
    }
    #endif

    // MARK: - Save Project

    /// Saves the current scene as a project
    func saveProject(
        roomName: String,
        placedModels: [Model],
        worldAnchorID: UUID?,
        sharedAnchor: AnchorEntity
    ) throws {
        // Create saved models array
        let savedModels = placedModels.compactMap { model -> ProjectData.SavedModel? in
            guard let entity = model.modelEntity else { return nil }

            return ProjectData.SavedModel(
                id: model.id,
                modelTypeName: model.modelType.rawValue,
                position: ProjectData.Vector3(entity.position(relativeTo: sharedAnchor)),
                rotation: ProjectData.Quaternion(entity.orientation(relativeTo: sharedAnchor)),
                scale: ProjectData.Vector3(entity.scale(relativeTo: sharedAnchor))
            )
        }

        // Check if project already exists
        let fileURL = projectFileURL(for: roomName)
        let now = Date()

        let project: ProjectData
        if let existingData = try? Data(contentsOf: fileURL),
           var existingProject = try? JSONDecoder().decode(ProjectData.self, from: existingData) {
            // Update existing project
            existingProject.dateModified = now
            existingProject.models = savedModels
            project = existingProject
            print("Updating existing project: \(roomName)")
        } else {
            // Create new project
            project = ProjectData(
                roomName: roomName,
                worldAnchorID: worldAnchorID,
                dateCreated: now,
                dateModified: now,
                models: savedModels
            )
            print("Creating new project: \(roomName)")
        }

        // Save to JSON file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(project)
        try jsonData.write(to: fileURL)

        print("Saved project '\(roomName)' with \(savedModels.count) models to: \(fileURL.path)")

        // Refresh the project list
        loadProjectList()
    }

    // MARK: - Load Project

    /// Loads a project by room name
    func loadProject(
        roomName: String,
        controller: CollaborativeSessionController,
        sharedAnchor: AnchorEntity
    ) async throws -> UUID? {
        let fileURL = projectFileURL(for: roomName)

        // Read the JSON file
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let project = try decoder.decode(ProjectData.self, from: jsonData)

        // Clear existing models
        controller.removeAllModels()

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 500_000_000)

        print("Loading \(project.models.count) models for project '\(roomName)'")

        // Load each model
        for savedModel in project.models {
            // Find the model type
            guard let modelType = ModelType.allCases().first(where: { $0.rawValue == savedModel.modelTypeName }) else {
                print("Warning: Unknown model type '\(savedModel.modelTypeName)'")
                continue
            }

            // Load the model through the controller with saved transform
            if await controller.loadModelAtPosition(
                modelType: modelType,
                instanceID: savedModel.id,
                position: savedModel.position.simd3,
                rotation: savedModel.rotation.quatf,
                scale: savedModel.scale.simd3
            ) != nil {
                print("Loaded model: \(modelType.displayName) at position: \(savedModel.position.simd3)")
            } else {
                print("Warning: Failed to load model '\(modelType.displayName)'")
            }
        }

        print("Project '\(roomName)' loaded successfully")
        return project.worldAnchorID
    }

    // MARK: - Project List Management

    /// Loads the list of all saved projects
    func loadProjectList() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            savedProjects = fileURLs.compactMap { url in
                guard url.pathExtension == "json",
                      let data = try? Data(contentsOf: url),
                      let project = try? decoder.decode(ProjectData.self, from: data) else {
                    return nil
                }
                return project
            }.sorted { $0.dateModified > $1.dateModified }

            print("Loaded \(savedProjects.count) saved projects")
        } catch {
            print("Error loading project list: \(error)")
            savedProjects = []
        }
    }

    /// Deletes a project by room name
    func deleteProject(roomName: String) throws {
        let fileURL = projectFileURL(for: roomName)
        try fileManager.removeItem(at: fileURL)
        print("Deleted project '\(roomName)'")
        loadProjectList()
    }

    /// Gets a list of all saved project names
    func getProjectNames() -> [String] {
        return savedProjects.map { $0.roomName }
    }

    /// Gets a specific project by room name
    func getProject(named roomName: String) -> ProjectData? {
        return savedProjects.first { $0.roomName == roomName }
    }
}

// MARK: - Errors

enum ProjectError: LocalizedError {
    case projectNotFound
    case worldAnchorNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found"
        case .worldAnchorNotFound:
            return "World anchor not found. Make sure you're in the same physical location."
        case .invalidData:
            return "Invalid project data"
        }
    }
}
