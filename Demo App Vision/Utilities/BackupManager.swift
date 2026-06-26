import Foundation
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

    var errorDescription: String? {
        switch self {
        case .missingDocumentsDirectory:
            return "Unable to locate the app's documents directory."
        case .invalidBackupFile:
            return "The selected backup file is invalid."
        case .unsupportedBackupVersion(let version):
            return "Backup format version \(version) is not supported."
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
        return try encoder.encode(payload)
    }

    @MainActor
    static func importBackupData(_ data: Data, appSettings: AppSettings) throws -> BackupImportSummary {
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
                .init(name: url.lastPathComponent, data: try Data(contentsOf: url))
            }
    }

    private static func writeFiles(_ files: [DesignSphereBackupPayload.BackupFile], to directoryURL: URL) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var writtenCount = 0
        for file in files {
            let destination = uniqueDestinationURL(for: file.name, in: directoryURL)
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

        let importedJSONObject = try JSONSerialization.jsonObject(with: importedData)
        guard let importedDictionary = importedJSONObject as? [String: Any] else {
            throw BackupManagerError.invalidBackupFile
        }

        var currentDictionary: [String: Any] = [:]
        if fileManager.fileExists(atPath: anchorsURL.path),
           let existingData = try? Data(contentsOf: anchorsURL),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            currentDictionary = existingJSON
        }

        var added = 0
        for (key, value) in importedDictionary where currentDictionary[key] == nil {
            currentDictionary[key] = value
            added += 1
        }

        let serialized = try JSONSerialization.data(withJSONObject: currentDictionary, options: [.prettyPrinted, .sortedKeys])
        try serialized.write(to: anchorsURL, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: anchorsURL.path
        )
        return added
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
