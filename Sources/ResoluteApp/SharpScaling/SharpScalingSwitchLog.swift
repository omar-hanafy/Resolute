import Foundation
import ResoluteKit

/// The setups whose deferred switch has happened, one per display, so the switch to a sharp
/// size happens once per setup: not again after the person moves away from it, and not
/// again when Resolute next launches. A setup is known by when it was saved.
///
/// The app keeps it in its user defaults; tests and the gallery keep it in memory.
@MainActor
final class SharpScalingSwitchLog {
    static let defaultsKey = "SharpScalingSwitchedSetups"

    private let defaults: UserDefaults?
    /// Seconds since 1970 of the setup switched for, by override file.
    private var entries: [String: Double]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        entries = defaults?.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
    }

    /// Whether the switch for `key`'s setup saved at `saved` has happened.
    func hasSwitched(_ key: OverrideKey, saved: Date) -> Bool {
        // Property lists keep dates to the second.
        entries[key.relativePath].map { abs($0 - saved.timeIntervalSince1970) < 1 } ?? false
    }

    func markSwitched(_ key: OverrideKey, saved: Date) {
        entries[key.relativePath] = saved.timeIntervalSince1970
        defaults?.set(entries, forKey: Self.defaultsKey)
    }
}
