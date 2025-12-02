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

        // Read material type from component (set explicitly in EditModelView)
        var materialType: ProjectData.MaterialType? = nil
        if let materialTypeComp = entity.components[MaterialTypeComponent.self] {
            // Map string to enum
            switch materialTypeComp.materialType {
            case "wood":
                materialType = .wood
            case "metal":
                materialType = .metal
            case "fabric":
                materialType = .fabric
            case "leather":
                materialType = .leather
            case "custom":
                materialType = .custom
            default:
                materialType = nil
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
            materialType: materialType
        )
    }

    /// Extracts original unscaled bounds from entity for dimension tracking
    private func extractOriginalBounds(from entity: Entity) -> ProjectData.Vector3? {
        // Get bounds relative to the entity itself (unscaled)
        let bounds = entity.visualBounds(relativeTo: entity)
        let size = bounds.max - bounds.min

        // Only save if bounds are valid
        guard size.x > 0 && size.y > 0 && size.z > 0 else {
            return nil
        }

        return ProjectData.Vector3(size)
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

        // Restore material type and texture based on explicit type
        var materialTypeString: String? = nil
        if let materialType = savedMaterial.materialType {
            switch materialType {
            case .wood:
                materialTypeString = "wood"
                do {
                    let texture = try TextureResource.load(named: "wood_grain")
                    mat.normal = .init(texture: .init(texture))
                } catch {
                    print("Warning: Failed to load wood texture: \(error)")
                }
            case .metal:
                materialTypeString = "metal"
                // Metal has no normal texture, just metallic properties (already restored above)
                break
            case .fabric:
                materialTypeString = "fabric"
                do {
                    let texture = try TextureResource.load(named: "fabric")
                    mat.normal = .init(texture: .init(texture))
                } catch {
                    print("Warning: Failed to load fabric texture: \(error)")
                }
            case .leather:
                materialTypeString = "leather"
                do {
                    let texture = try TextureResource.load(named: "leather")
                    mat.normal = .init(texture: .init(texture))
                } catch {
                    print("Warning: Failed to load leather texture: \(error)")
                }
            case .custom:
                materialTypeString = "custom"
                // Custom color only, no texture
                break
            }
        }

        // Apply the material using the existing replaceAndStoreOldMaterials method
        entity.replaceAndStoreOldMaterials(material: mat)

        // Set the MaterialTypeComponent so future saves don't need epsilon detection
        if let typeString = materialTypeString {
            entity.components.set(MaterialTypeComponent(materialType: typeString))
        }
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

            // Extract original unscaled bounds for accurate dimension editing
            let originalBounds = extractOriginalBounds(from: entity)

            return ProjectData.SavedModel(
                id: model.id,
                modelTypeName: model.modelType.rawValue,
                position: ProjectData.Vector3(entity.position(relativeTo: sharedAnchor)),
                rotation: ProjectData.Quaternion(entity.orientation(relativeTo: sharedAnchor)),
                scale: ProjectData.Vector3(entity.scale(relativeTo: sharedAnchor)),
                material: savedMaterial,
                originalBounds: originalBounds
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

                // Restore original bounds if saved (for accurate dimension editing)
                if let originalBounds = savedModel.originalBounds,
                   let entity = loadedModel.modelEntity {
                    entity.components.set(OriginalBoundsComponent(originalSize: originalBounds.simd3))
                    print("Restored original bounds for \(modelType.displayName): \(originalBounds.simd3)")
                }

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
