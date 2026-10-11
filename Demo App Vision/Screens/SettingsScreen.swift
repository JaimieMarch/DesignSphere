// Settings screen for app-wide user preferences

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import XRShareCollaboration

private enum LocalDataTarget: String, CaseIterable, Identifiable {
    case savedProjects
    case importedModels
    case worldAnchors
    case favorites
    case labsPreferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .savedProjects:
            return "Saved Projects"
        case .importedModels:
            return "Imported Models"
        case .worldAnchors:
            return "World Anchors"
        case .favorites:
            return "Favorites"
        case .labsPreferences:
            return "Labs Preferences"
        }
    }

    var detail: String {
        switch self {
        case .savedProjects:
            return "Deletes all saved room/project JSON files."
        case .importedModels:
            return "Deletes all locally imported USDZ assets."
        case .worldAnchors:
            return "Deletes all stored anchor transforms for room alignment."
        case .favorites:
            return "Clears the saved favorites list."
        case .labsPreferences:
            return "Resets experimental feature toggles back to default."
        }
    }

    var destructiveButtonTitle: String {
        "Wipe \(title)"
    }
}

private enum LocalDataResetError: LocalizedError {
    case missingDocumentsDirectory

    var errorDescription: String? {
        switch self {
        case .missingDocumentsDirectory:
            return "Unable to locate the app's documents directory."
        }
    }
}

private enum LocalDataResetManager {
    @MainActor
    static func wipe(_ target: LocalDataTarget, appSettings: AppSettings) throws -> String {
        switch target {
        case .savedProjects:
            let deleted = try removeContents(ofDocumentsSubdirectory: "DesignSphereProjects", matchingExtension: "json")
            NotificationCenter.default.post(name: ProjectData.filesDidChangeNotification, object: nil)
            return "Deleted \(deleted) saved project file(s)."
        case .importedModels:
            let deleted = try removeContents(ofDocumentsSubdirectory: "Imports", matchingExtension: "usdz")
            NotificationCenter.default.post(name: ProjectData.filesDidChangeNotification, object: nil)
            return "Deleted \(deleted) imported model file(s)."
        case .worldAnchors:
            WorldAnchorProvider.shared.removeAllAnchors(deleteFile: true)
            return "Deleted stored world anchors."
        case .favorites:
            appSettings.clearStoredFavorites()
            return "Cleared saved favorites."
        case .labsPreferences:
            appSettings.resetLabsPreferences()
            return "Reset Labs preferences."
        }
    }

    private static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LocalDataResetError.missingDocumentsDirectory
        }
        return url
    }

    private static func removeContents(ofDocumentsSubdirectory subdirectory: String, matchingExtension ext: String?) throws -> Int {
        let fileManager = FileManager.default
        let directoryURL = try documentsDirectory().appendingPathComponent(subdirectory, isDirectory: true)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return 0 }

        let allEntries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let entriesToDelete: [URL]
        if let ext {
            entriesToDelete = allEntries.filter { $0.pathExtension.caseInsensitiveCompare(ext) == .orderedSame }
        } else {
            entriesToDelete = allEntries
        }

        for url in entriesToDelete {
            try fileManager.removeItem(at: url)
        }
        return entriesToDelete.count
    }
}

private struct DesignSphereBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.designSphereBackup, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw BackupManagerError.invalidBackupFile
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct BackupExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories: Set<BackupCategory> = Set(BackupCategory.allCases)
    let onExport: (Set<BackupCategory>) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Backup Contents") {
                    ForEach(BackupCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { selectedCategories.contains(category) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCategories.insert(category)
                                } else {
                                    selectedCategories.remove(category)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.title)
                                    .font(.headline)
                                Text(category.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("After tapping Create Backup, you'll choose where to save it on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Backup") {
                        onExport(selectedCategories)
                        dismiss()
                    }
                    .disabled(selectedCategories.isEmpty)
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct LocalDataManagementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Data to Wipe") {
                    ForEach(LocalDataTarget.allCases) { target in
                        NavigationLink {
                            LocalDataResetDetailView(target: target)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.title)
                                    .font(.headline)
                                Text(target.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Local Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LocalDataResetDetailView: View {
    let target: LocalDataTarget
    @EnvironmentObject private var appSettings: AppSettings
    @State private var confirmationText = ""
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        Form {
            Section("Selected Data") {
                Text(target.title)
                    .font(.headline)
                Text(target.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Confirmation") {
                Text("Type DELETE to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("DELETE", text: $confirmationText)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .accessibilityLabel("Deletion confirmation")
                    .accessibilityHint("Type DELETE in capital letters to enable the wipe button")
            }

            Section {
                Button(role: .destructive) {
                    runWipe()
                } label: {
                    Text(isProcessing ? "Wiping..." : target.destructiveButtonTitle)
                }
                .disabled(confirmationText != "DELETE" || isProcessing)
            }

            if let resultMessage {
                Section("Result") {
                    Text(resultMessage)
                }
            }

            if let errorMessage {
                Section("Error") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(errorMessage)")
                }
            }
        }
        .navigationTitle(target.title)
        .onChange(of: resultMessage) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
        .onChange(of: errorMessage) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement("Error: \(newValue)").post()
        }
    }

    private func runWipe() {
        isProcessing = true
        errorMessage = nil
        do {
            resultMessage = try LocalDataResetManager.wipe(target, appSettings: appSettings)
            confirmationText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var appSettings: AppSettings
    /// Called after a restore writes imported models to disk, so the catalog
    /// can pick them up without a relaunch.
    var onModelsImported: () -> Void = {}
    @State private var showLocalDataManagement = false
    @State private var showBackupExportOptions = false
    @State private var showBackupImporter = false
    @State private var showBackupExporter = false
    @State private var backupDocument = DesignSphereBackupDocument(data: Data())
    @State private var backupFilename = "DesignSphere-Backup"
    @State private var backupResultMessage: String?
    @State private var backupErrorMessage: String?
    @State private var selectedInformation: AppInformationDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle.bold())

                    Text("Preferences, permissions, storage, and backups.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsCard(title: "Accessibility") {
                    Toggle(isOn: $appSettings.highContrastTextEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High Contrast Text")
                                .font(.headline)
                            Text("Increases text contrast and legibility across the app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("High contrast text")
                    .accessibilityHint("Increases text contrast and legibility across the app")
                }

                SettingsCard(title: "Permissions") {
                    SurfaceDetectionPermissionRow()
                }

                SettingsCard(title: "Privacy") {
                    Toggle(isOn: $appSettings.rememberFavoritesEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remember Favorites")
                                .font(.headline)
                            Text("Stores your favorites locally on this device.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("Remember favorites")
                    .accessibilityHint("Stores your favorites locally on this device")

                    Text("Analytics and telemetry are currently not enabled in this app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        selectedInformation = .privacyPolicy
                    } label: {
                        settingsNavigationLabel("Privacy Policy", systemImage: "hand.raised")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Privacy Policy")
                    .accessibilityHint("Opens the DesignSphere privacy policy")

                    Button {
                        showLocalDataManagement = true
                    } label: {
                        settingsNavigationLabel("Manage Local Data", systemImage: "internaldrive")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityLabel("Manage local data")
                    .accessibilityHint("Opens options to wipe saved projects, imports, anchors, or favorites")
                }

                SettingsCard(title: "Storage") {
                    CatalogDownloadsRow()
                }

                SettingsCard(title: "Labs") {
                    Toggle(isOn: Binding(
                        get: { appSettings.collisionMode != .off },
                        set: { appSettings.collisionMode = $0 ? .prevent : .off }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Collision")
                                .font(.headline)
                            Text("Keeps furniture from settling into overlap when placed or moved. Off by default.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("Collision")
                    .accessibilityHint("Prevents furniture from overlapping when placed or moved")
                }

                SettingsCard(title: "Backups") {
                    Button("Create Backup") {
                        backupErrorMessage = nil
                        showBackupExportOptions = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Create backup")
                    .accessibilityHint("Export a backup of your projects and settings")

                    Button("Import Backup") {
                        backupErrorMessage = nil
                        showBackupImporter = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Import backup")
                    .accessibilityHint("Restore projects and settings from a backup file")

                    if let backupResultMessage {
                        Text(backupResultMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let backupErrorMessage {
                        Label(backupErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(backupErrorMessage)")
                    }
                }

                SettingsCard(title: "Tutorial") {
                    Button("Open Tutorial") {
                        appSettings.requestTutorialReplay()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open tutorial")
                    .accessibilityHint("Opens the interactive walkthrough")

                    Text("Replay the Interactive Walkthrough anytime, then exit when you're done.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsCard(title: "About") {
                    HStack {
                        Text("DesignSphere")
                            .font(.headline)
                        Spacer()
                        Text(AppVersion.current)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)

                    Button {
                        selectedInformation = .support
                    } label: {
                        settingsNavigationLabel("Support & Contact", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Support and contact")
                    .accessibilityHint("Opens support information and contact links")

                    Button {
                        selectedInformation = .acknowledgements
                    } label: {
                        settingsNavigationLabel("Acknowledgements", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Acknowledgements")
                    .accessibilityHint("Credits for the furniture models and their licenses")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(cornerRadius: 24)
        .padding(24)
        .sheet(isPresented: $showLocalDataManagement) {
            LocalDataManagementView()
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showBackupExportOptions) {
            BackupExportOptionsView { categories in
                createBackup(with: categories)
            }
        }
        .sheet(item: $selectedInformation) { destination in
            AppInformationView(destination: destination)
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .designSphereBackup,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                backupResultMessage = "Backup exported successfully."
            case .failure(let error):
                backupErrorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.designSphereBackup, .json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(from: result)
        }
        .onChange(of: backupResultMessage) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
        .onChange(of: backupErrorMessage) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement("Error: \(newValue)").post()
        }
    }

    private func createBackup(with categories: Set<BackupCategory>) {
        do {
            let data = try BackupManager.createBackupData(categories: categories, appSettings: appSettings)
            backupDocument = DesignSphereBackupDocument(data: data)
            backupFilename = makeBackupFilename()
            showBackupExporter = true
            backupResultMessage = "Backup prepared. Choose a save location."
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func importBackup(from result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let summary = try BackupManager.importBackup(at: url, appSettings: appSettings)
            if summary.importsAdded > 0 {
                onModelsImported()
            }
            backupResultMessage = summary.summaryText
            backupErrorMessage = nil
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func makeBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "DesignSphere-Backup-\(formatter.string(from: Date()))"
    }

    private func settingsNavigationLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    SettingsScreen()
        .environmentObject(AppSettings())
}
