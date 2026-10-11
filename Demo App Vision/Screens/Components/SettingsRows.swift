// Rows for the Settings screen that read live system state: the app version,
// the surface-detection permission, and how much space catalog downloads use.

import SwiftUI
import ARKit
import XRShareCollaboration

// MARK: - Version

enum AppVersion {
    /// "Version 1.0 (1)". Support asks users to quote this, so it has to be
    /// visible somewhere in the app.
    static func displayString(from info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unknown"
        }
    }

    static var current: String { displayString(from: Bundle.main.infoDictionary) }
}

// MARK: - Surface detection permission

/// What the user has decided about world sensing, the one permission the app
/// asks for. A denial otherwise fails silently: furniture still appears, but
/// never settles on real floors, walls or tables.
enum SurfaceDetectionPermission: Equatable {
    case allowed
    case denied
    case notDetermined
    case unavailable

    init(_ status: ARKitSession.AuthorizationStatus?) {
        switch status {
        case .allowed: self = .allowed
        case .denied: self = .denied
        case .notDetermined: self = .notDetermined
        case .none: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .allowed: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not asked yet"
        case .unavailable: return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .allowed:
            return "Furniture rests on the floors, walls and tables DesignSphere detects around you."
        case .denied:
            return "Furniture can still be placed, but it can't rest on real surfaces or stay anchored in your room. Open Settings to allow it for DesignSphere, then reopen the app."
        case .notDetermined:
            return "DesignSphere asks the first time it opens your space."
        case .unavailable:
            return "Surface detection isn't available on this device."
        }
    }

    var systemImage: String {
        switch self {
        case .allowed: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle"
        case .unavailable: return "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .allowed: return .green
        case .denied: return .orange
        case .notDetermined, .unavailable: return .secondary
        }
    }
}

struct SurfaceDetectionPermissionRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: SurfaceDetectionPermission?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Surface Detection")
                    .font(.headline)
                Spacer()
                if let permission {
                    Label(permission.title, systemImage: permission.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(permission.tint)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let permission {
                Text(permission.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if permission == .denied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(settingsURL) }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Opens DesignSphere's settings so you can allow surface detection")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .task { await refresh() }
        // The user may have just come back from the Settings app.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
    }

    private func refresh() async {
        let results = await ARKitSession().queryAuthorization(for: [.worldSensing])
        permission = SurfaceDetectionPermission(results[.worldSensing])
    }
}

// MARK: - Downloaded catalog files

struct CatalogDownloadsRow: View {
    @State private var usage: Int64?
    @State private var isClearing = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloaded Models")
                        .font(.headline)
                    Text("Models and thumbnails saved for faster loading. They download again when you use them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let usage {
                    Text(Self.format(usage))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button(isClearing ? "Clearing…" : "Clear Downloads", role: .destructive) {
                showConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(isClearing || usage == 0)
            .accessibilityHint("Deletes downloaded models and thumbnails. Your projects are not affected.")

            if let resultMessage {
                Text(resultMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .task { usage = await CatalogDownloads.diskUsage() }
        .confirmationDialog(
            "Clear downloaded models?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Downloads", role: .destructive) { clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your projects, imports and favorites stay. Models download again the next time you place them.")
        }
        .onChange(of: resultMessage) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
    }

    private func clear() {
        isClearing = true
        Task {
            let before = usage ?? 0
            await CatalogDownloads.removeAll()
            let after = await CatalogDownloads.diskUsage()
            usage = after
            resultMessage = "Freed \(Self.format(max(before - after, 0)))."
            isClearing = false
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
