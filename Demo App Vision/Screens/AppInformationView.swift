import SwiftUI

enum AppInformationDestination: String, Identifiable, CaseIterable {
    case privacyPolicy
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy:
            return "Privacy Policy"
        case .support:
            return "Support & Contact"
        }
    }

    var systemImage: String {
        switch self {
        case .privacyPolicy:
            return "hand.raised"
        case .support:
            return "questionmark.circle"
        }
    }

    var onlineURL: URL? {
        switch self {
        case .privacyPolicy:
            return URL(string: "https://github.com/JaimieMarch/DesignSphere/blob/main/docs/privacy-policy.md")
        case .support:
            return URL(string: "https://github.com/JaimieMarch/DesignSphere/blob/main/docs/support.md")
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
                    }

                    if let onlineURL = destination.onlineURL {
                        Link("View Online", destination: onlineURL)
                            .buttonStyle(.bordered)
                    }

                    Text("Last updated July 26, 2026")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                text: "Include the app version, visionOS version, what you expected, what happened, and reproducible steps. Do not attach room scans, project files, backups, or other private content to a public report."
            )

            if let issueURL = URL(string: "https://github.com/JaimieMarch/DesignSphere/issues/new") {
                Link("Contact Support on GitHub", destination: issueURL)
                    .buttonStyle(.borderedProminent)
            }

            if let issuesURL = URL(string: "https://github.com/JaimieMarch/DesignSphere/issues") {
                Link("View Known Issues", destination: issuesURL)
            }
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
