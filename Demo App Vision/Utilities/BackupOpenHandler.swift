// Handles a DesignSphere backup opened from outside the app (Files, Mail,
// AirDrop). The Info.plist declares DesignSphere the owner of `.dsbackup`
// files, so the system launches the app for them; without this the launch
// would silently do nothing.

import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct BackupOpenHandler: ViewModifier {
    @ObservedObject var controller: CollaborativeSessionController
    @EnvironmentObject private var appSettings: AppSettings

    @State private var pendingBackupURL: URL?
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                // Importing adds projects and models and can change preferences,
                // so it is never done without the user agreeing first.
                pendingBackupURL = url
            }
            .alert(
                "Restore this backup?",
                isPresented: Binding(
                    get: { pendingBackupURL != nil },
                    set: { if !$0 { pendingBackupURL = nil } }
                ),
                presenting: pendingBackupURL
            ) { url in
                Button("Restore") { restore(from: url) }
                Button("Cancel", role: .cancel) { pendingBackupURL = nil }
            } message: { url in
                Text("\"\(url.lastPathComponent)\" will add its projects, imported models and favorites to DesignSphere. Nothing you already have is deleted. If it includes app preferences, they replace your current ones.")
            }
            .alert(
                "Backup restored",
                isPresented: Binding(
                    get: { resultMessage != nil },
                    set: { if !$0 { resultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
            .alert(
                "Couldn't restore backup",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func restore(from url: URL) {
        pendingBackupURL = nil
        do {
            let summary = try BackupManager.importBackup(at: url, appSettings: appSettings)
            if summary.importsAdded > 0 {
                controller.refreshAvailableModels()
            }
            resultMessage = summary.summaryText
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
