import Foundation

enum AppFeatureFlags {
    static let settingsScreenEnabled = true
    static let measurementToolsEnabled = true
    static let sharePlayEnabled = false
    static let aiAssistantEnabled = true

    /// When enabled, the catalog is served from the remote manifest (R2) and
    /// models download lazily on placement, replacing the bundled models.
    static let remoteCatalogEnabled = true
    static let remoteCatalogBaseURL = URL(string: "https://pub-efd589f26cb24d3db0c409b9416b4ecd.r2.dev")
}
