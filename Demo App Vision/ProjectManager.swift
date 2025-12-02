import Foundation
import ARKit
import RealityKit
import XRShareCollaboration
import UIKit

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

    // MARK: - Material Helpers

    /// Extracts material data from an entity for saving
    private func extractMaterialData(from entity: Entity) -> ProjectData.SavedMaterial? {
        // Check if entity has a ModelComponent with materials
        guard let modelComponent = entity.components[ModelComponent.self],
              !modelComponent.materials.isEmpty else {
            return nil
        }

        // Get the first material (typically all materials are the same after editing)
        guard let pbrMaterial = modelComponent.materials.first as? PhysicallyBasedMaterial else {
            return nil
        }

        // Extract base color
        let baseColor = pbrMaterial.baseColor.tint
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Extract roughness, metallic, and specular
        let roughness = pbrMaterial.roughness.scale
        let metallic = pbrMaterial.metallic.scale
        let specular = pbrMaterial.specular.scale

        // Identify material type based on roughness/metallic values (from EditModelView)
        // Wood: roughness=0.6, metallic=0.0
        // Metal: roughness=0.2, metallic=1.0
        // Fabric: roughness=0.85, metallic=0.0
        // Leather: roughness=0.8, metallic=0.2
        var textureName: String? = nil
        if pbrMaterial.normal.texture != nil {
            let epsilon: Float = 0.01
            if abs(roughness - 0.6) < epsilon && abs(metallic - 0.0) < epsilon {
                textureName = "wood_grain"
            } else if abs(roughness - 0.85) < epsilon && abs(metallic - 0.0) < epsilon {
                textureName = "fabric"
            } else if abs(roughness - 0.8) < epsilon && abs(metallic - 0.2) < epsilon {
                textureName = "leather"
            }
        }

        return ProjectData.SavedMaterial(
            baseColorR: Float(r),
            baseColorG: Float(g),
            baseColorB: Float(b),
            baseColorA: Float(a),
            roughness: roughness,
            metallic: metallic,
            specular: specular,
            normalTextureName: textureName
        )
    }

    /// Applies saved material data to an entity
    private func applyMaterialData(_ savedMaterial: ProjectData.SavedMaterial, to entity: Entity) {
        // Reconstruct the PhysicallyBasedMaterial from saved data
        var mat = PhysicallyBasedMaterial()

        // Restore base color
        let color = UIColor(
            red: CGFloat(savedMaterial.baseColorR),
            green: CGFloat(savedMaterial.baseColorG),
            blue: CGFloat(savedMaterial.baseColorB),
            alpha: CGFloat(savedMaterial.baseColorA)
        )
        mat.baseColor = .init(tint: color)

        // Restore roughness, metallic, and specular if available
        if let roughness = savedMaterial.roughness {
            mat.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        }
        if let metallic = savedMaterial.metallic {
            mat.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
        }
        if let specular = savedMaterial.specular {
            mat.specular = PhysicallyBasedMaterial.Specular(floatLiteral: specular)
        }

        // Restore normal texture if available
        if let textureName = savedMaterial.normalTextureName {
            do {
                let texture = try TextureResource.load(named: textureName)
                mat.normal = .init(texture: .init(texture))
            } catch {
                print("Warning: Failed to load texture '\(textureName)': \(error)")
            }
        }

        // Apply the material using the existing replaceAndStoreOldMaterials method
        entity.replaceAndStoreOldMaterials(material: mat)
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

            // Extract material data if entity has custom materials
            let savedMaterial = extractMaterialData(from: entity)

            return ProjectData.SavedModel(
                id: model.id,
                modelTypeName: model.modelType.rawValue,
                position: ProjectData.Vector3(entity.position(relativeTo: sharedAnchor)),
                rotation: ProjectData.Quaternion(entity.orientation(relativeTo: sharedAnchor)),
                scale: ProjectData.Vector3(entity.scale(relativeTo: sharedAnchor)),
                material: savedMaterial
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
            if let loadedModel = await controller.loadModelAtPosition(
                modelType: modelType,
                instanceID: savedModel.id,
                position: savedModel.position.simd3,
                rotation: savedModel.rotation.quatf,
                scale: savedModel.scale.simd3
            ) {
                print("Loaded model: \(modelType.displayName) at position: \(savedModel.position.simd3)")

                // Restore material if saved
                if let savedMaterial = savedModel.material,
                   let entity = loadedModel.modelEntity {
                    applyMaterialData(savedMaterial, to: entity)
                    print("Restored custom material for \(modelType.displayName)")
                }
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
