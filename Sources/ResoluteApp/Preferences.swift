import Foundation

/// Settings kept in the app's user defaults.
@MainActor
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showLowResolutionModes: Bool {
        get { defaults.object(forKey: Key.showLowResolutionModes) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showLowResolutionModes) }
    }

    private enum Key {
        static let showLowResolutionModes = "ShowLowResolutionModes"
    }
}
