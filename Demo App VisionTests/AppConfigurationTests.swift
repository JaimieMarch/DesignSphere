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
}
