import Foundation

@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let favoritesDefaultsKey = "favoriteModels"
    nonisolated static let favoritesDidResetNotification = Notification.Name("AppSettings.favoritesDidReset")
    nonisolated static let tutorialReplayRequestedNotification = Notification.Name("AppSettings.tutorialReplayRequested")

    private enum Keys {
        static let highContrastText = "settings.highContrastTextEnabled"
        static let rememberFavorites = "settings.rememberFavoritesEnabled"
        static let labsMeasurementTools = "settings.labs.measurementToolsEnabled"
        static let onboardingCompleted = "settings.onboardingCompleted"
    }

    @Published var highContrastTextEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highContrastTextEnabled, forKey: Keys.highContrastText)
        }
    }

    @Published var rememberFavoritesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rememberFavoritesEnabled, forKey: Keys.rememberFavorites)
        }
    }

    @Published var labsMeasurementToolsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(labsMeasurementToolsEnabled, forKey: Keys.labsMeasurementTools)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        highContrastTextEnabled = defaults.bool(forKey: Keys.highContrastText)
        if defaults.object(forKey: Keys.rememberFavorites) == nil {
            rememberFavoritesEnabled = true
        } else {
            rememberFavoritesEnabled = defaults.bool(forKey: Keys.rememberFavorites)
        }
        labsMeasurementToolsEnabled = defaults.bool(forKey: Keys.labsMeasurementTools)
    }

    func clearStoredFavorites() {
        UserDefaults.standard.removeObject(forKey: Self.favoritesDefaultsKey)
        NotificationCenter.default.post(name: Self.favoritesDidResetNotification, object: nil)
    }

    func resetLabsPreferences() {
        labsMeasurementToolsEnabled = false
    }

    func requestTutorialReplay() {
        UserDefaults.standard.set(false, forKey: Keys.onboardingCompleted)
        NotificationCenter.default.post(name: Self.tutorialReplayRequestedNotification, object: nil)
    }
}
