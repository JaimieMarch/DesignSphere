import Foundation
import RealityKit
import simd
import XCTest
import XRShareCollaboration
@testable import DesignSphere

@MainActor
final class ReleaseDataIntegrityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRestoringSameBackupTwiceKeepsBothProjectsLoadable() async throws {
        let data = try backup(projects: [project(name: "Living / Room")])
        _ = try BackupManager.importBackupData(data, appSettings: AppSettings(), documentsURL: directory)
        _ = try BackupManager.importBackupData(data, appSettings: AppSettings(), documentsURL: directory)
        let projects = directory.appendingPathComponent("DesignSphereProjects")
        let manager = ProjectManager(projectsDirectory: projects)
        XCTAssertEqual(Set(manager.getProjectNames()), ["Living / Room", "Living - Room-imported-1"])
        let controller = CollaborativeSessionController()
        for name in manager.getProjectNames() {
            _ = try await manager.loadProject(roomName: name, controller: controller, sharedAnchor: controller.sharedAnchorEntity)
            XCTAssertEqual(manager.currentProjectName, name)
            XCTAssertFalse(manager.isStreamingProject)
        }
        try await manager.deleteProject(roomName: "Living - Room-imported-1")
        XCTAssertEqual(manager.getProjectNames(), ["Living / Room"])
    }

    func testLegacyRenamedProjectLoadsAndDeletesItsActualFile() async throws {
        let url = directory.appendingPathComponent("renamed-imported-1.json")
        try encode(project(name: "Original Room")).write(to: url)
        let manager = ProjectManager(projectsDirectory: directory)
        let controller = CollaborativeSessionController()
        _ = try await manager.loadProject(roomName: "Original Room", controller: controller, sharedAnchor: controller.sharedAnchorEntity)
        try await manager.deleteProject(roomName: "Original Room")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLegacyDuplicateRoomNamesRemainIndividuallyLoadableAndDeletable() async throws {
        let data = try encode(project(name: "Original Room"))
        try data.write(to: directory.appendingPathComponent("Original Room.json"))
        try data.write(to: directory.appendingPathComponent("Original Room-imported-1.json"))
        let manager = ProjectManager(projectsDirectory: directory)
        let names = manager.getProjectNames()
        XCTAssertEqual(Set(names).count, 2)
        let controller = CollaborativeSessionController()
        for name in names {
            _ = try await manager.loadProject(roomName: name, controller: controller, sharedAnchor: controller.sharedAnchorEntity)
            XCTAssertEqual(manager.currentProjectName, name)
            try await manager.deleteProject(roomName: name)
        }
        XCTAssertTrue(manager.savedProjects.isEmpty)
    }

    func testBackupRemapsCollidingModelsAndFavoritesWithoutOverwritingOriginal() throws {
        let imports = directory.appendingPathComponent("Imports")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let original = imports.appendingPathComponent("audit_cube.usdz")
        try fixture.write(to: original)
        let defaults = UserDefaults.standard
        let previousFavorites = defaults.object(forKey: AppSettings.favoritesDefaultsKey)
        defer { defaults.set(previousFavorites, forKey: AppSettings.favoritesDefaultsKey) }
        let data = try backup(projects: [project(name: "Cube Room", modelName: "audit_cube")], models: [.init(name: "audit_cube.usdz", data: fixture)], favorites: ["Audit Cube"])
        let result = try BackupManager.importBackupData(data, appSettings: AppSettings(), documentsURL: directory)
        XCTAssertEqual(result.importsAdded, 1)
        XCTAssertEqual(try Data(contentsOf: original), fixture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imports.appendingPathComponent("audit_cube-imported-1.usdz").path))
        let manager = ProjectManager(projectsDirectory: directory.appendingPathComponent("DesignSphereProjects"))
        XCTAssertEqual(manager.savedProjects.first?.models.first?.modelTypeName, "audit_cube-imported-1")
        XCTAssertTrue((defaults.array(forKey: AppSettings.favoritesDefaultsKey) as? [String])?.contains("Audit Cube Imported 1") == true)
    }

    func testFailedAnchorWriteRollsBackNewProjects() throws {
        let anchorsURL = directory.appendingPathComponent("DesignSphereAnchors.json")
        try FileManager.default.createDirectory(at: anchorsURL, withIntermediateDirectories: true)
        let data = try backup(projects: [project(name: "Rollback Room")], anchors: Data("[]".utf8))
        XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings(), documentsURL: directory))
        let projectsURL = directory.appendingPathComponent("DesignSphereProjects")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: projectsURL.path), [])
    }

    func testReloadingImportedAnchorsPreservesThemOnNextSave() throws {
        let url = directory.appendingPathComponent("anchors.json")
        let provider = WorldAnchorProvider(fileURL: url)
        let first = UUID()
        provider.saveAnchor(id: first, transform: matrix_identity_float4x4)
        let imported = UUID()
        let other = WorldAnchorProvider(fileURL: url)
        other.saveAnchor(id: imported, transform: matrix_identity_float4x4)
        provider.reloadFromDisk()
        let third = UUID()
        provider.saveAnchor(id: third, transform: matrix_identity_float4x4)
        let restored = WorldAnchorProvider(fileURL: url)
        XCTAssertTrue(restored.hasAnchor(id: first))
        XCTAssertTrue(restored.hasAnchor(id: imported))
        XCTAssertTrue(restored.hasAnchor(id: third))
    }

    func testSavingThenLoadingOriginalAssetDoesNotFlattenItsMaterials() throws {
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [PhysicallyBasedMaterial()])
        let manager = ProjectManager(projectsDirectory: directory)
        XCTAssertNil(manager.extractMaterialData(from: entity))
    }

    func testEditedMaterialIsFoundOnNestedEntity() throws {
        let root = Entity()
        let child = ModelEntity(mesh: .generateBox(size: 1), materials: [PhysicallyBasedMaterial()])
        root.addChild(child)
        root.components.set(MaterialTypeComponent(materialType: "wood"))
        let manager = ProjectManager(projectsDirectory: directory)
        XCTAssertEqual(manager.extractMaterialData(from: root)?.materialType, .wood)
    }

    func testEditorNormalMapsAreBundledAndLoadable() {
        TextureCache.shared.clearCache()
        for name in ["wood_grain", "fabric", "leather"] {
            XCTAssertNotNil(TextureCache.shared.texture(named: name), name)
        }
        XCTAssertEqual(TextureCache.shared.cacheCount, 3)
    }

    func testUnsafeTransformsAndDuplicateInstanceIDsAreRejectedBeforeImport() throws {
        let valid = try encode(project(name: "Invalid Model Room", modelName: "audit_cube"))
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["scale"] = ["x": 0, "y": 1, "z": 1] },
            { $0["scale"] = ["x": -1, "y": 1, "z": 1] },
            { $0["rotation"] = ["x": 0, "y": 0, "z": 0, "w": 0] }
        ]
        for mutate in mutations {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            var models = try XCTUnwrap(json["models"] as? [[String: Any]])
            mutate(&models[0])
            json["models"] = models
            let invalid = try JSONDecoder.projectDecoder.decode(ProjectData.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try invalid.validate())
        }
        var duplicate = project(name: "Duplicate Room", modelName: "audit_cube")
        duplicate.models.append(duplicate.models[0])
        XCTAssertThrowsError(try duplicate.validate())
    }

    func testImportRejectsInvalidUSDZWithoutAddingCatalogFile() async throws {
        let source = directory.appendingPathComponent("broken.usdz")
        try Data("invalid-usdz".utf8).write(to: source)
        let imports = directory.appendingPathComponent("Imports")
        do {
            _ = try await ModelImportManager.importModel(from: source, existingNames: [], directory: imports)
            XCTFail("Malformed USDZ must fail")
        } catch { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imports.path), [])
    }

    func testImportAcceptsValidLocalFileAndRejectsCatalogNameCollision() async throws {
        let source = directory.appendingPathComponent("audit_cube.usdz")
        try fixture.write(to: source)
        let imports = directory.appendingPathComponent("Imports")
        let name = try await ModelImportManager.importModel(from: source, existingNames: [], directory: imports)
        XCTAssertEqual(name, "audit_cube")
        XCTAssertEqual(try Data(contentsOf: imports.appendingPathComponent("audit_cube.usdz")), fixture)
        do {
            _ = try await ModelImportManager.importModel(from: source, existingNames: ["AUDIT_CUBE"], directory: directory.appendingPathComponent("OtherImports"))
            XCTFail("Catalog collision must fail")
        } catch ModelImportManager.ImportError.duplicateName { }
    }

    private func project(name: String, modelName: String? = nil) -> ProjectData {
        ProjectData(roomName: name, worldAnchorID: nil, dateCreated: Date(timeIntervalSince1970: 100), dateModified: Date(timeIntervalSince1970: 200), models: modelName.map {
            [.init(id: UUID(), modelTypeName: $0, position: .init(.zero), rotation: .init(simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))), scale: .init(.one), material: nil, originalBounds: nil)]
        } ?? [])
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func backup(projects: [ProjectData], models: [DesignSphereBackupPayload.BackupFile] = [], favorites: [String]? = nil, anchors: Data? = nil) throws -> Data {
        try encode(DesignSphereBackupPayload(formatVersion: 1, createdAt: Date(), categories: BackupCategory.allCases.map(\.rawValue), projects: try projects.enumerated().map { .init(name: "room-\($0.offset).json", data: try encode($0.element)) }, importedModels: models, worldAnchorsData: anchors, favorites: favorites, preferences: nil))
    }

    // Original, aligned USDZ fixture authored for this test: a one-meter cube.
    private var fixture: Data { Data(base64Encoded: "UEsDBBQAAAAAAAAAIQC/lgfgnQAAAJ0AAAAMABYAZml4dHVyZS51c2Rh/soSAAAAAAAAAAAAAAAAAAAAAAAAACN1c2RhIDEuMAooCiAgICBkZWZhdWx0UHJpbSA9ICJGaXh0dXJlIgogICAgbWV0ZXJzUGVyVW5pdCA9IDEKICAgIHVwQXhpcyA9ICJZIgopCmRlZiBYZm9ybSAiRml4dHVyZSIgewogICAgZGVmIEN1YmUgIkN1YmUiIHsKICAgICAgICBkb3VibGUgc2l6ZSA9IDEKICAgIH0KfQpQSwECFAMUAAAAAAAAACEAv5YH4J0AAACdAAAADAAWAAAAAAAAAAAAgAEAAAAAZml4dHVyZS51c2Rh/soSAAAAAAAAAAAAAAAAAAAAAAAAAFBLBQYAAAAAAQABAFAAAADdAAAAAAA=")! }
}

private extension JSONDecoder {
    static var projectDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
