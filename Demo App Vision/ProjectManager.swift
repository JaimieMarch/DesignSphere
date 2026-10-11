import Foundation
import ARKit
import RealityKit
import XRShareCollaboration
import UIKit

@MainActor
class ProjectManager: ObservableObject {
    enum AnchorRestoreStatus {
        case noneSaved
        case restored(UUID)
        case fallbackTransform(UUID)
        case missing(UUID)
    }

    /// How much of a saved project actually made it back into the scene.
    ///
    /// Restoring is best-effort: a saved model whose type is no longer in the
    /// catalog (removed from the manifest, or an import the user deleted), or
    /// whose usdz fails to download, cannot come back. The caller needs this to
    /// avoid reporting unconditional success over a half-empty — or entirely
    /// empty — room.
    struct LoadSummary: Equatable {
        var requested: Int = 0
        var restored: Int = 0
        var missingModelNames: [String] = []

        var skipped: Int { max(requested - restored, 0) }
        var isComplete: Bool { skipped == 0 }

        /// Nil when everything came back; otherwise a sentence to append to the
        /// success message.
        var shortfallDescription: String? {
            guard !isComplete else { return nil }
            if restored == 0 {
                return requested == 1
                    ? "The saved model could not be restored."
                    : "None of the \(requested) saved models could be restored."
            }
            return "\(restored) of \(requested) models restored; \(skipped) unavailable."
        }
    }

    /// Name → type table used to restore a saved project, keyed case-insensitively.
    ///
    /// The live catalog takes precedence; locally discoverable types (bundle
    /// resources and `Documents/Imports`) only fill gaps, so a user import that
    /// isn't in the remote manifest still restores.
    static func modelTypeLookup(
        catalog: [ModelType],
        local: [ModelType] = ModelType.allCases()
    ) -> [String: ModelType] {
        var table: [String: ModelType] = [:]
        for modelType in catalog {
            table[modelType.rawValue.lowercased()] = modelType
        }
        for modelType in local where table[modelType.rawValue.lowercased()] == nil {
            table[modelType.rawValue.lowercased()] = modelType
        }
        return table
    }

    @Published var savedProjects: [ProjectData] = []
    /// Result of the most recent `loadProject` call.
    @Published private(set) var lastLoadSummary: LoadSummary?
    @Published var currentWorldAnchorID: UUID?
    @Published var currentProjectName: String?
    @Published var isStreamingProject: Bool = false
    @Published var streamingProgress: Double = 0

    // app data is sandboxed **************************
    private let fileManager = FileManager.default
    private let anchorProvider = WorldAnchorProvider.shared
    private let projectsDirectoryOverride: URL?
    private var projectURLsByName: [String: URL] = [:]
    private var recoveredNamesByURL: [URL: String] = [:]
    private var projectsDirectory: URL {
        if let projectsDirectoryOverride { return projectsDirectoryOverride }
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("DesignSphereProjects", isDirectory: true)
    }

    init(projectsDirectory: URL? = nil) {
        projectsDirectoryOverride = projectsDirectory
        createProjectsDirectoryIfNeeded()
        loadProjectList()
    }

    // MARK: - Directory Management

    private func createProjectsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            try? fileManager.createDirectory(
                at: projectsDirectory,
                withIntermediateDirectories: true,
                attributes: attributes
            )
            #if DEBUG
            print("Created projects directory at: \(projectsDirectory.path)")
            #endif
        }
    }

    private func projectDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func projectFileURL(for roomName: String) -> URL {
        if let existing = projectURLsByName[roomName] { return existing }
        let stem = ProjectData.fileStem(for: roomName)
        return projectsDirectory.appendingPathComponent("\(stem).json")
    }

    // MARK: - Material Helpers

    /// Extracts material data from an entity for saving
    func extractMaterialData(from entity: Entity) -> ProjectData.SavedMaterial? {
        // Only edited materials should replace the asset's original textures.
        guard entity.components[MaterialTypeComponent.self] != nil else { return nil }
        return extractEditedMaterialData(from: entity, materialType: entity.components[MaterialTypeComponent.self]?.materialType)
    }

    private func extractEditedMaterialData(from entity: Entity, materialType materialTypeName: String?) -> ProjectData.SavedMaterial? {
        // Check if entity has a ModelComponent with materials
        guard let modelComponent = entity.components[ModelComponent.self],
              !modelComponent.materials.isEmpty else {
            return entity.children.lazy.compactMap {
                self.extractEditedMaterialData(from: $0, materialType: materialTypeName)
            }.first
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
        if let materialTypeName {
            // Map string to enum
            switch materialTypeName {
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
                if let texture = TextureCache.shared.texture(named: "wood_grain") {
                    mat.normal = .init(texture: .init(texture))
                }
            case .metal:
                materialTypeString = "metal"
                // Metal has no normal texture, just metallic properties (already restored above)
            case .fabric:
                materialTypeString = "fabric"
                if let texture = TextureCache.shared.texture(named: "fabric") {
                    mat.normal = .init(texture: .init(texture))
                }
            case .leather:
                materialTypeString = "leather"
                if let texture = TextureCache.shared.texture(named: "leather") {
                    mat.normal = .init(texture: .init(texture))
                }
            case .custom:
                materialTypeString = "custom"
                // Custom color only, no texture
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
    /// Creates a persistent ARKit world anchor for the current room and stores a fallback transform.
    func createWorldAnchor(controller: CollaborativeSessionController) async throws -> UUID {
        let anchorID = try await controller.createPersistentWorldAnchor()
        anchorProvider.saveAnchor(id: anchorID, transform: controller.sharedAnchorEntity.transform.matrix)
        currentWorldAnchorID = anchorID
        #if DEBUG
        print("Created persistent world anchor with ID: \(anchorID)")
        #endif
        return anchorID
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
        guard !isStreamingProject else { throw ProjectError.operationInProgress }
        guard ProjectData.isValidName(roomName) else { throw ProjectError.invalidData }
        loadProjectList()
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

        if let anchorID = worldAnchorID {
            anchorProvider.saveAnchor(id: anchorID, transform: sharedAnchor.transform.matrix)
        }

        let project: ProjectData
        if let existingData = try? Data(contentsOf: fileURL),
           let existingProject = try? projectDecoder().decode(ProjectData.self, from: existingData) {
            let resolvedWorldAnchorID = worldAnchorID ?? existingProject.worldAnchorID
            // Update existing project
            project = ProjectData(
                roomName: roomName,
                worldAnchorID: resolvedWorldAnchorID,
                dateCreated: existingProject.dateCreated,
                dateModified: now,
                models: savedModels
            )
            #if DEBUG
            print("Updating existing project: \(roomName)")
            #endif
        } else {
            // Create new project
            project = ProjectData(
                roomName: roomName,
                worldAnchorID: worldAnchorID,
                dateCreated: now,
                dateModified: now,
                models: savedModels
            )
            #if DEBUG
            print("Creating new project: \(roomName)")
            #endif
        }

        // Save to JSON file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try project.validate()
        let jsonData = try encoder.encode(project)
        try jsonData.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        #if DEBUG
        print("Saved project '\(roomName)' with \(savedModels.count) models to: \(fileURL.path)")
        #endif

        // Refresh the project list
        loadProjectList()
        currentProjectName = roomName
    }

    // MARK: - Load Project

    /// Loads a project by room name
    func loadProject(
        roomName: String,
        controller: CollaborativeSessionController,
        sharedAnchor: AnchorEntity
    ) async throws -> AnchorRestoreStatus {
        guard !isStreamingProject else { throw ProjectError.operationInProgress }
        loadProjectList()
        let fileURL = projectFileURL(for: roomName)

        // Read the JSON file
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= BackupManager.maximumProjectFileBytes else { throw ProjectError.invalidData }
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let project = try decoder.decode(ProjectData.self, from: jsonData)
        try project.validate()
        isStreamingProject = true
        streamingProgress = 0
        defer {
            isStreamingProject = false
            streamingProgress = 0
        }

        var summary = LoadSummary(requested: project.models.count)
        lastLoadSummary = nil

        // The live catalog is the source of truth for what can be placed. The
        // shipping app bundles no usdz files, so `ModelType.allCases()` — which
        // only scans the bundle and Documents/Imports — cannot resolve a remote
        // model at all; looking up there first made every restore silently
        // no-op. Keep it as a fallback for locally imported models that aren't
        // in the catalog list yet.
        let catalogTypes = Self.modelTypeLookup(catalog: controller.availableModels.map(\.type))

        // Clear existing models
        controller.beginHistoryRecordingSuppression()
        defer {
            controller.endHistoryRecordingSuppression()
        }
        await controller.removeAllModels()

        let anchorRestoreStatus: AnchorRestoreStatus
        if let anchorID = project.worldAnchorID {
            if await controller.restorePersistentWorldAnchor(id: anchorID) {
                anchorProvider.saveAnchor(id: anchorID, transform: controller.sharedAnchorEntity.transform.matrix)
                currentWorldAnchorID = anchorID
                anchorRestoreStatus = .restored(anchorID)
            } else if let anchorTransform = anchorProvider.transform(for: anchorID) {
                controller.clearPersistentWorldAnchor()
                sharedAnchor.transform = Transform(matrix: anchorTransform)
                currentWorldAnchorID = nil
                anchorRestoreStatus = .fallbackTransform(anchorID)
                #if DEBUG
                print("World anchor \(anchorID) could not be relocalized; loaded using cached fallback transform")
                #endif
            } else {
                controller.clearPersistentWorldAnchor(resetSharedAnchorTransform: true)
                currentWorldAnchorID = nil
                anchorRestoreStatus = .missing(anchorID)
                #if DEBUG
                print("World anchor \(anchorID) was not found and no fallback transform exists")
                #endif
            }
        } else {
            controller.clearPersistentWorldAnchor(resetSharedAnchorTransform: true)
            currentWorldAnchorID = nil
            anchorRestoreStatus = .noneSaved
        }

        #if DEBUG
        print("Loading \(project.models.count) models for project '\(roomName)'")
        #endif

        // Load each model
        for (index, savedModel) in project.models.enumerated() {
            defer {
                let progress = Double(index + 1) / Double(max(project.models.count, 1))
                self.streamingProgress = progress
            }

            // Find the model type
            guard let modelType = catalogTypes[savedModel.modelTypeName.lowercased()] else {
                #if DEBUG
                print("Warning: Unknown model type '\(savedModel.modelTypeName)'")
                #endif
                summary.missingModelNames.append(savedModel.modelTypeName)
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
                #if DEBUG
                print("Loaded model: \(modelType.displayName) at position: \(savedModel.position.simd3)")
                #endif

                // Restore original bounds if saved (for accurate dimension editing)
                if let originalBounds = savedModel.originalBounds,
                   let entity = loadedModel.modelEntity {
                    entity.components.set(OriginalBoundsComponent(originalSize: originalBounds.simd3))
                    #if DEBUG
                    print("Restored original bounds for \(modelType.displayName): \(originalBounds.simd3)")
                    #endif
                }

                // Restore material if saved
                if let savedMaterial = savedModel.material,
                   let entity = loadedModel.modelEntity {
                    applyMaterialData(savedMaterial, to: entity)
                    #if DEBUG
                    print("Restored custom material for \(modelType.displayName)")
                    #endif
                }

                summary.restored += 1
            } else {
                #if DEBUG
                print("Warning: Failed to load model '\(modelType.displayName)'")
                #endif
                summary.missingModelNames.append(modelType.displayName)
            }

        }

        #if DEBUG
        print("Project '\(roomName)' loaded: \(summary.restored)/\(summary.requested) models restored")
        #endif
        lastLoadSummary = summary
        currentProjectName = roomName
        return anchorRestoreStatus
    }

    // MARK: - Project List Management

    /// Loads the list of all saved projects
    func loadProjectList() {
        projectURLsByName.removeAll()
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let records: [(project: ProjectData, url: URL)] = fileURLs.compactMap { url in
                guard url.pathExtension.lowercased() == "json",
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= BackupManager.maximumProjectFileBytes,
                      let data = try? Data(contentsOf: url),
                      let project = try? decoder.decode(ProjectData.self, from: data),
                      (try? project.validate()) != nil else {
                    return nil
                }
                return (project, url)
            }.sorted {
                $0.project.dateModified == $1.project.dateModified
                    ? $0.url.lastPathComponent < $1.url.lastPathComponent
                    : $0.project.dateModified > $1.project.dateModified
            }
            var names = Set<String>()
            savedProjects = records.map { record in
                var project = record.project
                if let recoveredName = recoveredNamesByURL[record.url] {
                    project.roomName = recoveredName
                }
                if names.contains(project.roomName.lowercased()) {
                    let base = ProjectData.fileStem(for: record.url.deletingPathExtension().lastPathComponent)
                    project.roomName = base
                    var suffix = 1
                    while names.contains(project.roomName.lowercased()) {
                        project.roomName = "\(base)-recovered-\(suffix)"
                        suffix += 1
                    }
                    recoveredNamesByURL[record.url] = project.roomName
                }
                names.insert(project.roomName.lowercased())
                projectURLsByName[project.roomName] = record.url
                return project
            }

        } catch {
            #if DEBUG
            print("Error loading project list: \(error)")
            #endif
            savedProjects = []
        }
    }

    /// Deletes a project by room name
    func deleteProject(roomName: String, controller: CollaborativeSessionController? = nil) async throws {
        let fileURL = projectFileURL(for: roomName)
        let deletedProject = (try? Data(contentsOf: fileURL)).flatMap {
            try? projectDecoder().decode(ProjectData.self, from: $0)
        }
        try fileManager.removeItem(at: fileURL)
        recoveredNamesByURL[fileURL] = nil
        loadProjectList()
        if let anchorID = deletedProject?.worldAnchorID,
           !savedProjects.contains(where: { $0.worldAnchorID == anchorID }) {
            if let controller {
                await controller.removePersistentWorldAnchor(id: anchorID)
            }
            anchorProvider.removeAnchor(id: anchorID)
        }
        #if DEBUG
        print("Deleted project '\(roomName)'")
        #endif
        if currentProjectName == roomName {
            currentProjectName = nil
            currentWorldAnchorID = nil
        }
    }

    /// Gets a list of all saved project names
    func getProjectNames() -> [String] {
        return savedProjects.map { $0.roomName }
    }

    /// Gets a specific project by room name
    func getProject(named roomName: String) -> ProjectData? {
        let targetURL = projectFileURL(for: roomName)
        return savedProjects.first {
            $0.roomName == roomName
                || projectURLsByName[$0.roomName]?.path.lowercased() == targetURL.path.lowercased()
        }
    }
}

// MARK: - Errors

enum ProjectError: LocalizedError {
    case projectNotFound
    case worldAnchorNotFound
    case invalidData
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found"
        case .worldAnchorNotFound:
            return "World anchor not found. Make sure you're in the same physical location."
        case .invalidData:
            return "The project contains invalid or unsupported data."
        case .operationInProgress:
            return "Wait for the current project to finish loading."
        }
    }
}
