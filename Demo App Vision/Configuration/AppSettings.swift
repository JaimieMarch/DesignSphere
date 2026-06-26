import Foundation
import XRShareCollaboration

@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let favoritesDefaultsKey = "favoriteModels"
    nonisolated static let favoritesDidResetNotification = Notification.Name("AppSettings.favoritesDidReset")
    nonisolated static let tutorialReplayRequestedNotification = Notification.Name("AppSettings.tutorialReplayRequested")

    private enum Keys {
        static let highContrastText = "settings.highContrastTextEnabled"
        static let rememberFavorites = "settings.rememberFavoritesEnabled"
        static let collisionMode = "settings.collisionMode"
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

    @Published var collisionMode: FurnitureCollisionMode {
        didSet {
            UserDefaults.standard.set(collisionMode.rawValue, forKey: Keys.collisionMode)
        }
    }

    /// True once the user has seen (or dismissed) the first-run walkthrough.
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingCompleted)
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
        let storedCollisionMode = defaults.string(forKey: Keys.collisionMode)
        collisionMode = storedCollisionMode.flatMap(FurnitureCollisionMode.init(rawValue:)) ?? .warn
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    func clearStoredFavorites() {
        UserDefaults.standard.removeObject(forKey: Self.favoritesDefaultsKey)
        NotificationCenter.default.post(name: Self.favoritesDidResetNotification, object: nil)
    }

    func resetLabsPreferences() {
        collisionMode = .warn
    }

    func requestTutorialReplay() {
        NotificationCenter.default.post(name: Self.tutorialReplayRequestedNotification, object: nil)
    }

    func markOnboardingIncompleteForReplay() {
        hasCompletedOnboarding = false
    }
}
