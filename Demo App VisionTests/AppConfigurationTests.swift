import XCTest
import XRShareCollaboration
@testable import DesignSphere

final class AppEnumTests: XCTestCase {
    func testCategoriesHaveUniqueIdentifiersAndIcons() throws {
        XCTAssertEqual(Set(Category.allCases.map(\.id)).count, Category.allCases.count)
        for category in Category.allCases {
            XCTAssertFalse(category.icon.isEmpty)
            let data = try JSONEncoder().encode(category)
            XCTAssertEqual(try JSONDecoder().decode(Category.self, from: data), category)
        }
    }

    func testMaterialOptionsHaveUniqueIdentifiersAndCreateMaterials() throws {
        XCTAssertEqual(Set(MaterialOption.allCases.map(\.id)).count, MaterialOption.allCases.count)
        for option in MaterialOption.allCases {
            _ = option.color
            _ = option.createMaterial()
            let data = try JSONEncoder().encode(option)
            XCTAssertEqual(try JSONDecoder().decode(MaterialOption.self, from: data), option)
        }
    }

    func testTutorialCatalogMetadataIsCompleteAndUnique() {
        XCTAssertFalse(TutorialCatalog.modules.isEmpty)
        XCTAssertEqual(Set(TutorialCatalog.modules.map(\.id)).count, TutorialCatalog.modules.count)
        for module in TutorialCatalog.modules {
            XCTAssertFalse(module.title.isEmpty)
            XCTAssertFalse(module.summary.isEmpty)
            XCTAssertNotNil(module.durationLabel.range(of: #"^\d+:\d{2}$"#, options: .regularExpression))
            switch module.source {
            case .bundled(let name, let fileExtension):
                XCTAssertFalse(name.isEmpty)
                XCTAssertFalse(fileExtension.isEmpty)
            case .remote(let urlString):
                XCTAssertNotNil(URL(string: urlString))
            }
        }
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    private let settingsKeys = [
        "settings.highContrastTextEnabled",
        "settings.rememberFavoritesEnabled",
        "settings.collisionMode",
        "settings.onboardingCompleted",
        AppSettings.favoritesDefaultsKey,
    ]

    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    func testDefaultsAreSafeAndRememberFavoritesIsOptOut() {
        let settings = AppSettings()
        XCTAssertFalse(settings.highContrastTextEnabled)
        XCTAssertTrue(settings.rememberFavoritesEnabled)
        XCTAssertEqual(settings.collisionMode, .off)
    }

    func testChangesPersistAcrossInstances() {
        let settings = AppSettings()
        settings.highContrastTextEnabled = true
        settings.rememberFavoritesEnabled = false
        settings.collisionMode = .prevent

        let restored = AppSettings()
        XCTAssertTrue(restored.highContrastTextEnabled)
        XCTAssertFalse(restored.rememberFavoritesEnabled)
        XCTAssertEqual(restored.collisionMode, .prevent)
    }

    func testUnknownCollisionModeFallsBackToOff() {
        UserDefaults.standard.set("future-mode", forKey: "settings.collisionMode")
        XCTAssertEqual(AppSettings().collisionMode, .off)
    }

    func testResetLabsPreferencesPersistsDefaults() {
        let settings = AppSettings()
        settings.collisionMode = .prevent
        settings.resetLabsPreferences()
        XCTAssertEqual(settings.collisionMode, .off)
        XCTAssertEqual(AppSettings().collisionMode, .off)
    }

    func testClearFavoritesRemovesStorageAndPostsNotification() {
        UserDefaults.standard.set(["chair"], forKey: AppSettings.favoritesDefaultsKey)
        let notification = expectation(forNotification: AppSettings.favoritesDidResetNotification, object: nil)
        AppSettings().clearStoredFavorites()
        wait(for: [notification], timeout: 1)
        XCTAssertNil(UserDefaults.standard.object(forKey: AppSettings.favoritesDefaultsKey))
    }

    func testTutorialReplayMethodsUpdatePersistenceAndNotify() {
        UserDefaults.standard.set(true, forKey: "settings.onboardingCompleted")
        let notification = expectation(forNotification: AppSettings.tutorialReplayRequestedNotification, object: nil)
        let settings = AppSettings()
        settings.markOnboardingIncompleteForReplay()
        settings.requestTutorialReplay()
        wait(for: [notification], timeout: 1)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "settings.onboardingCompleted"))
    }

    private func clearDefaults() {
        for key in settingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

final class BackupValueTests: XCTestCase {
    func testCategoryMetadataAndIdentifiersAreComplete() {
        XCTAssertEqual(Set(BackupCategory.allCases.map(\.id)).count, BackupCategory.allCases.count)
        for category in BackupCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.detail.isEmpty)
        }
    }

    func testSummaryIncludesCountsAndOptionalPreferenceMessage() {
        var summary = BackupImportSummary(
            projectsAdded: 1,
            importsAdded: 2,
            anchorsAdded: 3,
            favoritesAdded: 4,
            appliedPreferences: false
        )
        XCTAssertEqual(summary.summaryText, "Imported: 1 projects, 2 models, 3 anchors, 4 favorites.")
        summary.appliedPreferences = true
        XCTAssertTrue(summary.summaryText.hasSuffix(" Applied app preferences."))
    }

    func testBackupErrorsHaveActionableDescriptions() {
        XCTAssertNotNil(BackupManagerError.missingDocumentsDirectory.errorDescription)
        XCTAssertNotNil(BackupManagerError.invalidBackupFile.errorDescription)
        XCTAssertTrue(BackupManagerError.unsupportedBackupVersion(9).errorDescription?.contains("9") == true)
        XCTAssertTrue(BackupManagerError.backupTooLarge(maximumBytes: 10 * 1_048_576).errorDescription?.contains("10 MB") == true)
        XCTAssertNotNil(BackupManagerError.tooManyEmbeddedFiles(maximumCount: 500).errorDescription)
        XCTAssertNotNil(BackupManagerError.embeddedFileTooLarge(maximumBytes: 10 * 1_048_576).errorDescription)
    }

    func testBackupPayloadRoundTripsBinaryDataAndPreferences() throws {
        let payload = DesignSphereBackupPayload(
            formatVersion: 1,
            createdAt: Date(timeIntervalSince1970: 123),
            categories: [BackupCategory.projects.rawValue],
            projects: [.init(name: "room.json", data: Data([0, 1, 2]))],
            importedModels: [.init(name: "chair.usdz", data: Data([3, 4]))],
            worldAnchorsData: Data([5]),
            favorites: ["chair"],
            preferences: .init(
                highContrastTextEnabled: true,
                rememberFavoritesEnabled: false,
                collisionMode: FurnitureCollisionMode.prevent.rawValue
            )
        )
        let decoded = try JSONDecoder().decode(
            DesignSphereBackupPayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.projects.first?.name, "room.json")
        XCTAssertEqual(decoded.projects.first?.data, Data([0, 1, 2]))
        XCTAssertEqual(decoded.importedModels.first?.name, "chair.usdz")
        XCTAssertEqual(decoded.worldAnchorsData, Data([5]))
        XCTAssertEqual(decoded.favorites, ["chair"])
        XCTAssertEqual(decoded.preferences?.collisionMode, "prevent")
    }

    @MainActor
    func testInvalidBackupDataIsRejectedWithoutWritingFiles() {
        XCTAssertThrowsError(try BackupManager.importBackupData(Data("not-json".utf8), appSettings: AppSettings())) { error in
            guard case BackupManagerError.invalidBackupFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testUnsupportedBackupVersionIsRejectedBeforeImport() throws {
        let payload = DesignSphereBackupPayload(
            formatVersion: 99,
            createdAt: Date(),
            categories: [],
            projects: [],
            importedModels: [],
            worldAnchorsData: nil,
            favorites: nil,
            preferences: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings())) { error in
            guard case BackupManagerError.unsupportedBackupVersion(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testPathTraversalAndInvalidProjectExtensionsAreRejected() throws {
        let projectData = try validProjectData()
        let unsafeNames = [
            "../outside.json",
            "subdirectory/room.json",
            "..\\outside.json",
            "/tmp/outside.json",
            ".hidden.json",
            "room.txt",
        ]

        for name in unsafeNames {
            let data = try backupData(
                categories: [.projects],
                projects: [.init(name: name, data: projectData)]
            )
            XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings()), name) { error in
                guard case BackupManagerError.invalidBackupFile = error else {
                    return XCTFail("Unexpected error for \(name): \(error)")
                }
            }
        }
    }

    @MainActor
    func testMalformedProjectModelAndAnchorPayloadsAreRejected() throws {
        let payloads = try [
            backupData(
                categories: [.projects],
                projects: [.init(name: "room.json", data: Data("not-project-json".utf8))]
            ),
            backupData(
                categories: [.importedModels],
                importedModels: [.init(
                    name: "chair.usdz",
                    data: Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0])
                )]
            ),
            backupData(
                categories: [.worldAnchors],
                worldAnchorsData: Data(#"{"not-a-uuid":{"id":"bad","matrix":[]}}"#.utf8)
            ),
        ]

        for data in payloads {
            XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings())) { error in
                guard case BackupManagerError.invalidBackupFile = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    @MainActor
    func testWholePayloadIsValidatedBeforePreferencesAreChanged() throws {
        let settings = AppSettings()
        settings.highContrastTextEnabled = false
        let data = try backupData(
            categories: [.projects, .appPreferences],
            projects: [
                .init(name: "valid.json", data: try validProjectData()),
                .init(name: "invalid.json", data: Data("invalid".utf8)),
            ],
            preferences: .init(
                highContrastTextEnabled: true,
                rememberFavoritesEnabled: false,
                collisionMode: FurnitureCollisionMode.prevent.rawValue
            )
        )

        XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: settings))
        XCTAssertFalse(settings.highContrastTextEnabled)
    }

    @MainActor
    func testBackupAndEmbeddedFileLimitsAreEnforced() throws {
        XCTAssertNoThrow(try BackupManager.validateBackupFileSize(BackupManager.maximumBackupFileBytes))
        XCTAssertThrowsError(try BackupManager.validateBackupFileSize(BackupManager.maximumBackupFileBytes + 1)) { error in
            guard case BackupManagerError.backupTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let oversizedProject = DesignSphereBackupPayload.BackupFile(
            name: "large.json",
            data: Data(repeating: 0, count: BackupManager.maximumProjectFileBytes + 1)
        )
        let data = try backupData(categories: [.projects], projects: [oversizedProject])
        XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings())) { error in
            guard case BackupManagerError.embeddedFileTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testEmbeddedFileCountLimitIsEnforced() throws {
        let files = (0...500).map {
            DesignSphereBackupPayload.BackupFile(name: "room-\($0).json", data: Data())
        }
        let data = try backupData(categories: [.projects], projects: files)
        XCTAssertThrowsError(try BackupManager.importBackupData(data, appSettings: AppSettings())) { error in
            guard case BackupManagerError.tooManyEmbeddedFiles = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func validProjectData() throws -> Data {
        let project = ProjectData(
            roomName: "Secure Import Test",
            worldAnchorID: nil,
            dateCreated: Date(timeIntervalSince1970: 100),
            dateModified: Date(timeIntervalSince1970: 200),
            models: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(project)
    }

    private func backupData(
        categories: Set<BackupCategory>,
        projects: [DesignSphereBackupPayload.BackupFile] = [],
        importedModels: [DesignSphereBackupPayload.BackupFile] = [],
        worldAnchorsData: Data? = nil,
        favorites: [String]? = nil,
        preferences: DesignSphereBackupPayload.PreferencesSnapshot? = nil
    ) throws -> Data {
        let payload = DesignSphereBackupPayload(
            formatVersion: 1,
            createdAt: Date(timeIntervalSince1970: 123),
            categories: categories.map(\.rawValue).sorted(),
            projects: projects,
            importedModels: importedModels,
            worldAnchorsData: worldAnchorsData,
            favorites: favorites,
            preferences: preferences
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
