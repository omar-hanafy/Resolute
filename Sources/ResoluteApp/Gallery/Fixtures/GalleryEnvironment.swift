import Foundation
import ResoluteKit

extension AppEnvironment {
    /// The gallery's app: the sample displays, preferences of its own that it only reads, a
    /// login item that stays off, no override files, a support folder of its own (scenes
    /// write sample presets and history there), and no dialogs.
    static func gallery(
        service: FakeDisplayService = FakeDisplayService(),
        support: SupportLocations = SupportLocations(
            root: FileManager.default.temporaryDirectory.appending(path: "ResoluteGallery-support-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
    ) -> AppEnvironment {
        AppEnvironment(
            service: service,
            preferences: Preferences(defaults: UserDefaults(suiteName: "com.omarhanafy.Resolute.gallery") ?? .standard),
            loginItem: FixedLoginItem(state: .disabled),
            overrides: OverrideStore(
                locations: .staged(at: FileManager.default.temporaryDirectory.appending(path: "ResoluteGallery-no-overrides"))
            ),
            support: support,
            notificationCenter: NotificationCenter(),
            askToKeep: { _ in false },
            showTrialOutcome: { _, _ in },
            showError: { _, _ in },
            launchKind: .deliberate,
            displayDetails: { display in
                SampleDisplays.all.first { $0.display.id == display.id }?.details ?? DisplayDetails()
            }
        )
    }
}

/// A login item that reports one state and never changes it.
@MainActor
final class FixedLoginItem: LoginItemToggling {
    let state: LaunchAtLoginState

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func unregister() throws {}

    func toggle() {}
}
