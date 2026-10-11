import Foundation
import RealityKit
import UniformTypeIdentifiers
import XRShareCollaboration

enum BackupCategory: String, CaseIterable, Identifiable, Hashable {
    case projects
    case importedModels
    case worldAnchors
    case favorites
    case appPreferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects:
            return "Saved Projects"
        case .importedModels:
            return "Imported Models"
        case .worldAnchors:
            return "World Anchors"
        case .favorites:
            return "Favorites"
        case .appPreferences:
            return "App Preferences"
        }
    }

    var detail: String {
        switch self {
        case .projects:
            return "Room/project JSON files."
        case .importedModels:
            return "User-imported USDZ files."
        case .worldAnchors:
            return "Saved world-anchor transforms."
        case .favorites:
            return "Favorited catalog items."
        case .appPreferences:
            return "Accessibility/privacy/labs toggles."
        }
    }
}

struct BackupImportSummary {
    var projectsAdded = 0
    var importsAdded = 0
    var anchorsAdded = 0
    var favoritesAdded = 0
    var appliedPreferences = false

    var summaryText: String {
        "Imported: \(projectsAdded) projects, \(importsAdded) models, \(anchorsAdded) anchors, \(favoritesAdded) favorites."
            + (appliedPreferences ? " Applied app preferences." : "")
    }
}

enum BackupManagerError: LocalizedError {
    case missingDocumentsDirectory
    case invalidBackupFile
    case unsupportedBackupVersion(Int)
    case backupTooLarge(maximumBytes: Int64)
    case tooManyEmbeddedFiles(maximumCount: Int)
    case embeddedFileTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .missingDocumentsDirectory:
            return "Unable to locate the app's documents directory."
        case .invalidBackupFile:
            return "The selected backup file is invalid."
        case .unsupportedBackupVersion(let version):
            return "Backup format version \(version) is not supported."
        case .backupTooLarge(let maximumBytes):
            return "The selected backup exceeds the \(maximumBytes / 1_048_576) MB size limit."
        case .tooManyEmbeddedFiles(let maximumCount):
            return "The selected backup contains more than \(maximumCount) files."
        case .embeddedFileTooLarge(let maximumBytes):
            return "A file in the selected backup exceeds the \(maximumBytes / 1_048_576) MB size limit."
        }
    }
}

struct DesignSphereBackupPayload: Codable {
    struct BackupFile: Codable {
        let name: String
        let data: Data
    }

    struct PreferencesSnapshot: Codable {
        let highContrastTextEnabled: Bool
        let rememberFavoritesEnabled: Bool
        let collisionMode: String?
    }

    let formatVersion: Int
    let createdAt: Date
    let categories: [String]
    let projects: [BackupFile]
    let importedModels: [BackupFile]
    let worldAnchorsData: Data?
    let favorites: [String]?
    let preferences: PreferencesSnapshot?
}

enum BackupManager {
    private static let formatVersion = 1
    static let maximumBackupFileBytes: Int64 = 512 * 1_024 * 1_024
    static let maximumProjectFileBytes = 10 * 1_024 * 1_024
    private static let maximumImportedModelFileBytes = 150 * 1_024 * 1_024
    private static let maximumAnchorFileBytes = 5 * 1_024 * 1_024
    private static let maximumTotalEmbeddedBytes = 384 * 1_024 * 1_024
    private static let maximumEmbeddedFileCount = 500
    private static let maximumProjectModelCount = 10_000
    private static let maximumAnchorCount = 10_000
    private static let maximumFavoriteCount = 10_000
    private static let maximumNameLength = 255

    private struct BackupAnchorRecord: Codable {
        let id: UUID
        let matrix: [Float]
    }

    @MainActor
    static func createBackupData(categories: Set<BackupCategory>, appSettings: AppSettings) throws -> Data {
        let files = FileManager.default
        let documentsURL = try documentsDirectory()
        let projectsURL = documentsURL.appendingPathComponent("DesignSphereProjects", isDirectory: true)
        let importsURL = documentsURL.appendingPathComponent("Imports", isDirectory: true)
        let anchorsURL = documentsURL.appendingPathComponent("DesignSphereAnchors.json")

        let projectFiles: [DesignSphereBackupPayload.BackupFile]
        if categories.contains(.projects) {
            projectFiles = try loadFiles(at: projectsURL, allowedExtension: "json")
        } else {
            projectFiles = []
        }

        let importedFiles: [DesignSphereBackupPayload.BackupFile]
        if categories.contains(.importedModels) {
            importedFiles = try loadFiles(at: importsURL, allowedExtension: "usdz")
        } else {
            importedFiles = []
        }

        let worldAnchorsData: Data?
        if categories.contains(.worldAnchors), files.fileExists(atPath: anchorsURL.path) {
            worldAnchorsData = try Data(contentsOf: anchorsURL)
        } else {
            worldAnchorsData = nil
        }

        let favorites: [String]?
        if categories.contains(.favorites) {
            favorites = UserDefaults.standard.array(forKey: AppSettings.favoritesDefaultsKey) as? [String]
        } else {
            favorites = nil
        }

        let preferences: DesignSphereBackupPayload.PreferencesSnapshot?
        if categories.contains(.appPreferences) {
            preferences = .init(
                highContrastTextEnabled: appSettings.highContrastTextEnabled,
                rememberFavoritesEnabled: appSettings.rememberFavoritesEnabled,
                collisionMode: appSettings.collisionMode.rawValue
            )
        } else {
            preferences = nil
        }

        let payload = DesignSphereBackupPayload(
            formatVersion: formatVersion,
            createdAt: Date(),
            categories: categories.map(\.rawValue).sorted(),
            projects: projectFiles,
            importedModels: importedFiles,
            worldAnchorsData: worldAnchorsData,
            favorites: favorites,
            preferences: preferences
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try validatePayload(payload)
        let data = try encoder.encode(payload)
        try validateBackupFileSize(Int64(data.count))
        return data
    }

    /// Reads and imports a backup file chosen in the file importer or opened
    /// from another app. Both entry points need the same security-scope,
    /// regular-file and size checks before any bytes are read.
    @MainActor
    static func importBackup(at url: URL, appSettings: AppSettings) throws -> BackupImportSummary {
        guard url.isFileURL else { throw BackupManagerError.invalidBackupFile }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile != false else {
            throw BackupManagerError.invalidBackupFile
        }
        if let fileSize = values.fileSize {
            try validateBackupFileSize(Int64(fileSize))
        }

        let data = try Data(contentsOf: url)
        return try importBackupData(data, appSettings: appSettings)
    }

    @MainActor
    static func importBackupData(_ data: Data, appSettings: AppSettings) throws -> BackupImportSummary {
        try validateBackupFileSize(Int64(data.count))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: DesignSphereBackupPayload
        do {
            payload = try decoder.decode(DesignSphereBackupPayload.self, from: data)
        } catch {
            throw BackupManagerError.invalidBackupFile
        }

        guard payload.formatVersion == formatVersion else {
            throw BackupManagerError.unsupportedBackupVersion(payload.formatVersion)
        }

        // Validate every category before changing files, defaults, or settings so
        // malformed backups cannot result in a partial import.
        try validatePayload(payload)

        let documentsURL = try documentsDirectory()
        var summary = BackupImportSummary()

        let projectsDirectory = documentsURL.appendingPathComponent("DesignSphereProjects", isDirectory: true)
        summary.projectsAdded = try writeFiles(payload.projects, to: projectsDirectory)

        let importsDirectory = documentsURL.appendingPathComponent("Imports", isDirectory: true)
        summary.importsAdded = try writeFiles(payload.importedModels, to: importsDirectory)

        if let anchorsData = payload.worldAnchorsData {
            summary.anchorsAdded = try mergeAnchors(with: anchorsData, documentsURL: documentsURL)
        }

        if let importedFavorites = payload.favorites {
            summary.favoritesAdded = mergeFavorites(importedFavorites)
        }

        if let importedPreferences = payload.preferences {
            appSettings.highContrastTextEnabled = importedPreferences.highContrastTextEnabled
            appSettings.rememberFavoritesEnabled = importedPreferences.rememberFavoritesEnabled
            if let collisionModeRawValue = importedPreferences.collisionMode,
               let collisionMode = FurnitureCollisionMode(rawValue: collisionModeRawValue) {
                appSettings.collisionMode = collisionMode
            }
            summary.appliedPreferences = true
        }

        return summary
    }

    static func validateBackupFileSize(_ byteCount: Int64) throws {
        guard byteCount >= 0, byteCount <= maximumBackupFileBytes else {
            throw BackupManagerError.backupTooLarge(maximumBytes: maximumBackupFileBytes)
        }
    }

    private static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw BackupManagerError.missingDocumentsDirectory
        }
        return url
    }

    private static func loadFiles(at directoryURL: URL, allowedExtension: String) throws -> [DesignSphereBackupPayload.BackupFile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try entries
            .filter { $0.pathExtension.caseInsensitiveCompare(allowedExtension) == .orderedSame }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let limit = allowedExtension == "usdz" ? maximumImportedModelFileBytes : maximumProjectFileBytes
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize <= limit else {
                    throw BackupManagerError.embeddedFileTooLarge(maximumBytes: limit)
                }
                return .init(name: url.lastPathComponent, data: try Data(contentsOf: url))
            }
    }

    private static func writeFiles(_ files: [DesignSphereBackupPayload.BackupFile], to directoryURL: URL) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let standardizedDirectory = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        var writtenCount = 0
        for file in files {
            let destination = uniqueDestinationURL(for: file.name, in: directoryURL)
            let standardizedParent = destination
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard standardizedParent == standardizedDirectory else {
                throw BackupManagerError.invalidBackupFile
            }
            try file.data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            writtenCount += 1
        }
        return writtenCount
    }

    private static func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = "-imported-\(index)"
            let generatedName = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(generatedName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func mergeAnchors(with importedData: Data, documentsURL: URL) throws -> Int {
        let fileManager = FileManager.default
        let anchorsURL = documentsURL.appendingPathComponent("DesignSphereAnchors.json")
        let decoder = JSONDecoder()
        let importedDictionary = try decoder.decode([UUID: BackupAnchorRecord].self, from: importedData)

        var currentDictionary: [UUID: BackupAnchorRecord] = [:]
        if fileManager.fileExists(atPath: anchorsURL.path),
           let existingData = try? Data(contentsOf: anchorsURL),
           let existingAnchors = try? decoder.decode([UUID: BackupAnchorRecord].self, from: existingData) {
            currentDictionary = existingAnchors
        }

        var added = 0
        for (key, value) in importedDictionary where currentDictionary[key] == nil {
            currentDictionary[key] = value
            added += 1
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let serialized = try encoder.encode(currentDictionary)
        try serialized.write(to: anchorsURL, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: anchorsURL.path
        )
        return added
    }

    private static func validatePayload(_ payload: DesignSphereBackupPayload) throws {
        let categoryNames = payload.categories
        guard categoryNames.count <= BackupCategory.allCases.count,
              Set(categoryNames).count == categoryNames.count,
              categoryNames.allSatisfy({ BackupCategory(rawValue: $0) != nil }) else {
            throw BackupManagerError.invalidBackupFile
        }

        let embeddedFileCount = payload.projects.count + payload.importedModels.count
        guard embeddedFileCount <= maximumEmbeddedFileCount else {
            throw BackupManagerError.tooManyEmbeddedFiles(maximumCount: maximumEmbeddedFileCount)
        }

        let embeddedBytes = payload.projects.reduce(0) { $0 + $1.data.count }
            + payload.importedModels.reduce(0) { $0 + $1.data.count }
        guard embeddedBytes <= maximumTotalEmbeddedBytes else {
            throw BackupManagerError.embeddedFileTooLarge(maximumBytes: maximumTotalEmbeddedBytes)
        }

        try validateFiles(payload.projects, expectedExtension: "json", maximumBytes: maximumProjectFileBytes)
        try validateFiles(payload.importedModels, expectedExtension: "usdz", maximumBytes: maximumImportedModelFileBytes)

        let projectDecoder = JSONDecoder()
        projectDecoder.dateDecodingStrategy = .iso8601
        for file in payload.projects {
            guard let project = try? projectDecoder.decode(ProjectData.self, from: file.data),
                  project.schemaVersion > 0,
                  project.schemaVersion <= ProjectData.currentSchemaVersion,
                  isValidText(project.roomName),
                  project.models.count <= maximumProjectModelCount,
                  project.dateCreated.timeIntervalSinceReferenceDate.isFinite,
                  project.dateModified.timeIntervalSinceReferenceDate.isFinite,
                  project.models.allSatisfy(isValidSavedModel) else {
                throw BackupManagerError.invalidBackupFile
            }
        }

        for file in payload.importedModels where !isLoadableUSDZ(file.data) {
            throw BackupManagerError.invalidBackupFile
        }

        if let anchorData = payload.worldAnchorsData {
            guard anchorData.count <= maximumAnchorFileBytes,
                  let anchors = try? JSONDecoder().decode([UUID: BackupAnchorRecord].self, from: anchorData),
                  anchors.count <= maximumAnchorCount,
                  anchors.allSatisfy({ key, anchor in
                      key == anchor.id && anchor.matrix.count == 16 && anchor.matrix.allSatisfy(\.isFinite)
                  }) else {
                throw BackupManagerError.invalidBackupFile
            }
        }

        if let favorites = payload.favorites {
            guard favorites.count <= maximumFavoriteCount,
                  favorites.allSatisfy(isValidText) else {
                throw BackupManagerError.invalidBackupFile
            }
        }

        if let collisionMode = payload.preferences?.collisionMode,
           FurnitureCollisionMode(rawValue: collisionMode) == nil {
            throw BackupManagerError.invalidBackupFile
        }
    }

    private static func validateFiles(
        _ files: [DesignSphereBackupPayload.BackupFile],
        expectedExtension: String,
        maximumBytes: Int
    ) throws {
        var normalizedNames = Set<String>()
        for file in files {
            guard isSafeFilename(file.name),
                  URL(fileURLWithPath: file.name).pathExtension.caseInsensitiveCompare(expectedExtension) == .orderedSame,
                  normalizedNames.insert(file.name.lowercased()).inserted else {
                throw BackupManagerError.invalidBackupFile
            }
            guard file.data.count <= maximumBytes else {
                throw BackupManagerError.embeddedFileTooLarge(maximumBytes: maximumBytes)
            }
        }
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty,
              filename.utf8.count <= maximumNameLength,
              filename != ".",
              filename != "..",
              !filename.hasPrefix("."),
              !filename.contains("/"),
              !filename.contains("\\"),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              URL(fileURLWithPath: filename).lastPathComponent == filename else {
            return false
        }
        return true
    }

    private static func isValidText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && value.utf8.count <= maximumNameLength
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isValidSavedModel(_ model: ProjectData.SavedModel) -> Bool {
        isValidText(model.modelTypeName)
            && [model.position.x, model.position.y, model.position.z].allSatisfy(\.isFinite)
            && [model.rotation.x, model.rotation.y, model.rotation.z, model.rotation.w].allSatisfy(\.isFinite)
            && [model.scale.x, model.scale.y, model.scale.z].allSatisfy(\.isFinite)
            && (model.originalBounds.map {
                [$0.x, $0.y, $0.z].allSatisfy(\.isFinite)
            } ?? true)
            && (model.material.map {
                [$0.baseColorR, $0.baseColorG, $0.baseColorB, $0.baseColorA].allSatisfy(\.isFinite)
                    && ($0.roughness.map(\.isFinite) ?? true)
                    && ($0.metallic.map(\.isFinite) ?? true)
                    && ($0.specular.map(\.isFinite) ?? true)
            } ?? true)
    }

    private static func isLoadableUSDZ(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04],
            [0x50, 0x4B, 0x05, 0x06],
            [0x50, 0x4B, 0x07, 0x08]
        ]
        guard signatures.contains(where: { data.prefix($0.count).elementsEqual($0) }) else {
            return false
        }

        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesignSphereBackupValidation-\(UUID().uuidString)")
            .appendingPathExtension("usdz")
        do {
            try data.write(to: stagingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            defer { try? FileManager.default.removeItem(at: stagingURL) }
            _ = try ModelEntity.loadModel(contentsOf: stagingURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            return false
        }
    }

    private static func mergeFavorites(_ importedFavorites: [String]) -> Int {
        let defaults = UserDefaults.standard
        let current = Set((defaults.array(forKey: AppSettings.favoritesDefaultsKey) as? [String]) ?? [])
        let combined = current.union(importedFavorites)
        defaults.set(Array(combined).sorted(), forKey: AppSettings.favoritesDefaultsKey)
        NotificationCenter.default.post(name: AppSettings.favoritesDidResetNotification, object: nil)
        return combined.count - current.count
    }
}

extension UTType {
    static let designSphereBackup = UTType(exportedAs: "com.designsphere.backup")
}
