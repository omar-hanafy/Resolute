import AppKit
import ResoluteKit

/// What the app model is built from. `live` is the real Mac; tests and the gallery give it
/// fakes, so nothing they do touches the displays, the login item or the user's settings.
@MainActor
struct AppEnvironment {
    var service: any DisplayControlling
    var preferences: Preferences
    var loginItem: any LoginItemToggling
    /// Where the overrides of displays that are not connected are found.
    var overrides: OverrideStore
    /// Presets, History and the socket `resolute` asks through, shared with the command line.
    var support: SupportLocations
    /// Posts `NSApplication.didChangeScreenParametersNotification`.
    var notificationCenter: NotificationCenter
    /// Asks on the display on trial whether to keep its mode; true only for Keep before the
    /// countdown ends.
    var askToKeep: @MainActor (TrialQuestion) -> Bool
    /// Says on the display how its trial ended, for two seconds.
    var showTrialOutcome: @MainActor (TrialOutcome, TrialQuestion) -> Void
    /// Shows an error under a title, unless the person cancelled.
    var showError: @MainActor (any Error, String) -> Void
    var launchKind: LaunchKind
    /// A display's physical size and, for a built-in one, the Mac it is part of. Live reads
    /// CoreGraphics and the I/O Registry; the gallery and tests give sample details.
    var displayDetails: @MainActor (Display) -> DisplayDetails = { DisplayDetails.read(for: $0) }

    static func live(launchKind: LaunchKind) -> AppEnvironment {
        AppEnvironment(
            service: SystemDisplayService(),
            preferences: Preferences(),
            loginItem: LoginItemController(),
            overrides: OverrideStore(),
            support: .standard,
            notificationCenter: .default,
            askToKeep: { TrialDialog.ask($0) },
            showTrialOutcome: { TrialNotice.show($0, $1) },
            showError: { Alerts.show($0, title: $1) },
            launchKind: launchKind
        )
    }
}

/// Launch at Login as the app model changes it: `LoginItemControlling` and turning it on or
/// off, which asks for approval in System Settings when macOS needs it.
@MainActor
protocol LoginItemToggling: LoginItemControlling {
    func toggle()
}

extension LoginItemController: LoginItemToggling {}

/// What the app model asks of the windows, the panel and the app: `ShellController` in the
/// app, a recording fake in tests.
@MainActor
protocol AppShell: AnyObject {
    /// Shows the Resolute window on `route`, with the Dock icon and ⌘Tab while it is open.
    func showWindow(_ route: AppRoute)
    /// Opens the panel under the menu bar icon, as clicking the icon does.
    func showPanel()
    func closePanel()
    /// Quits, after the checks that keep a switch, a revert or unsaved custom resolutions
    /// from being lost (Quit Resolute in the panel and menus, and ⌃⌥⌘Q).
    func quit()
}
