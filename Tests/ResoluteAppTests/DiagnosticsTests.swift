import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Stands in for `SMAppService`, so no test registers or unregisters the real app.
@MainActor
final class FakeLoginItem: LoginItemControlling {
    var state: LaunchAtLoginState
    private let failure: (any Error)?
    private(set) var unregisterCount = 0

    init(_ state: LaunchAtLoginState, failure: (any Error)? = nil) {
        self.state = state
        self.failure = failure
    }

    func unregister() throws {
        unregisterCount += 1
        if let failure { throw failure }
        state = .disabled
    }
}

@MainActor
@Suite struct DiagnosticsTests {
    /// These used to start the menu-bar app instead of saying what went wrong.
    @Test(arguments: [
        ["--details"], ["--verison"], ["--dump-menus"], ["--version", "--bogus"], ["--details", "--version"],
    ])
    func refusesWhatItDoesNotKnow(_ arguments: [String]) {
        #expect(Diagnostics.run(["Resolute"] + arguments, loginItem: FakeLoginItem(.enabled)) == 64)
    }

    /// LaunchServices and Xcode pass single-dash arguments, and their values, to a normal launch.
    @Test(arguments: [[], ["-NSDocumentRevisionsDebugMode", "YES"], ["-ApplePersistenceIgnoreState", "YES"]])
    func startsNormallyWithSingleDashArguments(_ arguments: [String]) {
        #expect(Diagnostics.run(["Resolute"] + arguments, loginItem: FakeLoginItem(.enabled)) == nil)
    }

    @Test(arguments: [
        ["--version"], ["--dump-menu", "--details"], ["--details", "--dump-menu-model"],
        ["--render-editor", "editor.png"], ["-NSDocumentRevisionsDebugMode", "YES", "--dump-menu"],
        ["--unregister-login-item"],
    ])
    func acceptsWhatItKnows(_ arguments: [String]) {
        #expect(!Diagnostics.isMisused(["Resolute"] + arguments))
    }

    // MARK: - Launch at Login

    /// What uninstall.sh runs, so a removed app leaves no login item behind.
    @Test(arguments: [LaunchAtLoginState.enabled, .requiresApproval])
    func turnsLaunchAtLoginOff(_ state: LaunchAtLoginState) {
        let loginItem = FakeLoginItem(state)
        #expect(Diagnostics.run(["Resolute", "--unregister-login-item"], loginItem: loginItem) == 0)
        #expect(loginItem.unregisterCount == 1)
    }

    /// Off already, or outside an app bundle, where macOS has no login item for it.
    @Test(arguments: [LaunchAtLoginState.disabled, .unavailable])
    func leavesLaunchAtLoginAloneWhenThereIsNothingToTurnOff(_ state: LaunchAtLoginState) {
        let loginItem = FakeLoginItem(state)
        #expect(Diagnostics.run(["Resolute", "--unregister-login-item"], loginItem: loginItem) == 0)
        #expect(loginItem.unregisterCount == 0)
    }

    @Test func failsWhenLaunchAtLoginCannotBeTurnedOff() {
        let loginItem = FakeLoginItem(.enabled, failure: CocoaError(.featureUnsupported))
        #expect(Diagnostics.run(["Resolute", "--unregister-login-item"], loginItem: loginItem) == 1)
        #expect(loginItem.unregisterCount == 1)
    }
}
