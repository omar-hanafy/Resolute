import Testing
@testable import ResoluteApp

@MainActor
@Suite struct DiagnosticsTests {
    /// These used to start the menu-bar app instead of saying what went wrong.
    @Test(arguments: [
        ["--details"], ["--verison"], ["--dump-menus"], ["--version", "--bogus"], ["--details", "--version"],
    ])
    func refusesWhatItDoesNotKnow(_ arguments: [String]) {
        #expect(Diagnostics.run(["Resolute"] + arguments) == 64)
    }

    /// LaunchServices and Xcode pass single-dash arguments, and their values, to a normal launch.
    @Test(arguments: [[], ["-NSDocumentRevisionsDebugMode", "YES"], ["-ApplePersistenceIgnoreState", "YES"]])
    func startsNormallyWithSingleDashArguments(_ arguments: [String]) {
        #expect(Diagnostics.run(["Resolute"] + arguments) == nil)
    }

    @Test(arguments: [
        ["--version"], ["--dump-menu", "--details"], ["--details", "--dump-menu-model"],
        ["--render-editor", "editor.png"], ["-NSDocumentRevisionsDebugMode", "YES", "--dump-menu"],
    ])
    func acceptsWhatItKnows(_ arguments: [String]) {
        #expect(!Diagnostics.isMisused(["Resolute"] + arguments))
    }
}
