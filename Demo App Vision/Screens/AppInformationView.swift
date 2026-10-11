import SwiftUI

enum AppInformationDestination: String, Identifiable, CaseIterable {
    case privacyPolicy
    case support
    case acknowledgements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy:
            return "Privacy Policy"
        case .support:
            return "Support & Contact"
        case .acknowledgements:
            return "Acknowledgements"
        }
    }

    var systemImage: String {
        switch self {
        case .privacyPolicy:
            return "hand.raised"
        case .support:
            return "questionmark.circle"
        case .acknowledgements:
            return "heart.text.square"
        }
    }

    /// Public copies of the in-app policy and support text.
    ///
    /// These resolve only once `docs/` is on the default branch — App Store
    /// Connect requires a working Privacy Policy URL, and App Review taps it.
    /// Verify both in a signed-out browser before submitting; see
    /// `docs/app-store-checklist.md`.
    var onlineURL: URL? {
        switch self {
        case .privacyPolicy:
            return URL(string: "https://github.com/JaimieMarch/DesignSphere/blob/main/docs/privacy-policy.md")
        case .support:
            return URL(string: "https://github.com/JaimieMarch/DesignSphere/blob/main/docs/support.md")
        case .acknowledgements:
            return URL(string: "https://github.com/JaimieMarch/DesignSphere/blob/main/docs/asset-license-audit.md")
        }
    }
}

struct AppInformationView: View {
    let destination: AppInformationDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(destination.title, systemImage: destination.systemImage)
                        .font(.largeTitle.bold())

                    switch destination {
                    case .privacyPolicy:
                        privacyPolicy
                    case .support:
                        supportInformation
                    case .acknowledgements:
                        acknowledgements
                    }

                    if let onlineURL = destination.onlineURL {
                        Link("View Online", destination: onlineURL)
                            .buttonStyle(.bordered)
                    }

                    if destination != .acknowledgements {
                        Text("Last updated July 26, 2026")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            .navigationTitle(destination.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var privacyPolicy: some View {
        VStack(alignment: .leading, spacing: 20) {
            informationSection(
                title: "Overview",
                text: "DesignSphere has no accounts, advertising, or behavioral analytics. The app does not sell personal information or use data to track you across apps or websites. Cloudflare processes limited network metadata when it delivers the remote catalog."
            )

            informationSection(
                title: "Data Stored on Your Device",
                text: "Saved projects, imported USDZ models, world-anchor transforms, favorites, preferences, downloaded catalog files, and backups are stored locally. You choose where exported backups are saved."
            )

            informationSection(
                title: "Spatial Information",
                text: "DesignSphere uses Apple spatial APIs to understand surfaces, maintain placement, and support system interactions. Spatial information is processed on the device and is not uploaded by DesignSphere. The app does not record camera, microphone, or hand-tracking footage."
            )

            informationSection(
                title: "Remote Catalog",
                text: "The app contacts a Cloudflare-hosted catalog to retrieve its manifest, thumbnails, and USDZ models. Cloudflare may retain an IP address, requested object, timestamp, response status, and related diagnostic metadata to deliver, secure, and operate that service. This is declared as Other Diagnostic Data used for app functionality, not linked to you, and not used for tracking. Projects, imports, backups, spatial information, and assistant prompts are never included in catalog requests."
            )

            informationSection(
                title: "Design Assistant",
                text: "Natural-language design requests use Apple's on-device Foundation Models when available. DesignSphere does not send those requests to its own servers."
            )

            informationSection(
                title: "Retention and Deletion",
                text: "Project and preference data remains until you delete it, wipe it from Settings, or remove the app. Downloaded catalog files are cache data and may be removed automatically by the operating system. A backup remains wherever you exported it until you delete it there."
            )

            informationSection(
                title: "Contact",
                text: "For privacy questions or requests, open Support & Contact in Settings and create an issue in the public DesignSphere support tracker. Do not include private project files, backup files, or sensitive personal information in a public issue."
            )

            if let cloudflarePrivacyURL = URL(string: "https://www.cloudflare.com/privacypolicy/") {
                Link("Cloudflare Privacy Policy", destination: cloudflarePrivacyURL)
            }
        }
    }

    private var supportInformation: some View {
        VStack(alignment: .leading, spacing: 20) {
            informationSection(
                title: "Getting Help",
                text: "DesignSphere is an Apple Vision Pro app. Before reporting a problem, install the latest available app build, restart the app, and confirm that visionOS and your network connection are working."
            )

            informationSection(
                title: "Catalog and Downloads",
                text: "The catalog needs a network connection on first use. Previously downloaded models and the last catalog can remain available from local cache, but the operating system may clear cached files."
            )

            informationSection(
                title: "Imports and Backups",
                text: "Model imports accept USDZ files up to 150 MB. Backup tools are under Settings. Keep a separate copy of important backups and import only files you trust."
            )

            informationSection(
                title: "Report a Problem",
                text: "Include the app version, visionOS version, what you expected, what happened, and reproducible steps. Do not attach project files, backups, or other private content to a public report."
            )

            informationSection(
                title: "Your Versions",
                text: "DesignSphere \(AppVersion.current.replacingOccurrences(of: "Version ", with: "")), visionOS \(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))"
            )
            .textSelection(.enabled)

            if let issueURL = URL(string: "https://github.com/JaimieMarch/DesignSphere/issues/new") {
                Link("Contact Support on GitHub", destination: issueURL)
                    .buttonStyle(.borderedProminent)
            }

            if let issuesURL = URL(string: "https://github.com/JaimieMarch/DesignSphere/issues") {
                Link("View Known Issues", destination: issuesURL)
            }
        }
    }

    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: 20) {
            informationSection(
                title: "Furniture Models",
                text: "The furniture catalog is built from models published by Poly Haven and The Base Mesh, including the textures embedded in them. Both libraries release their work under the CC0 1.0 Universal public domain dedication. Credit isn't required, but DesignSphere wouldn't exist without the artists who share their work this way."
            )

            VStack(alignment: .leading, spacing: 10) {
                if let polyHavenURL = URL(string: "https://polyhaven.com/models") {
                    Link("Poly Haven", destination: polyHavenURL)
                }
                if let baseMeshURL = URL(string: "https://www.thebasemesh.com/model-library") {
                    Link("The Base Mesh: Tim Steer and contributors", destination: baseMeshURL)
                }
                if let cc0URL = URL(string: "https://creativecommons.org/publicdomain/zero/1.0/") {
                    Link("CC0 1.0 Universal", destination: cc0URL)
                }
            }

            informationSection(
                title: "App Icon",
                text: "The DesignSphere icon was made for this project."
            )
        }
    }

    private func informationSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.bold())
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AppInformationView(destination: .privacyPolicy)
}
