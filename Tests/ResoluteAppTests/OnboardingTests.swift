import AppKit
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

@MainActor
@Suite struct OnboardingTests {
    let scratch = ScratchDefaults()

    @Test func welcomeShowsOnlyOnTheFirstDeliberateLaunch() {
        #expect(WelcomeRule.shouldShow(launchKind: .deliberate, hasShownWelcome: false))
        #expect(!WelcomeRule.shouldShow(launchKind: .deliberate, hasShownWelcome: true))
        // A launch at login stays quiet, and leaves Welcome for the first launch a person makes.
        #expect(!WelcomeRule.shouldShow(launchKind: .atLogin, hasShownWelcome: false))
        #expect(!WelcomeRule.shouldShow(launchKind: .atLogin, hasShownWelcome: true))
    }

    @Test func welcomeFollowsTheModelsLaunchAndPreferences() throws {
        let preferences = Preferences(defaults: scratch.defaults)
        let root = FileManager.default.temporaryDirectory.appending(path: "ResoluteOnboardingTests-\(UUID().uuidString)")
        let deliberate = AppModelTests.makeModel(service: FakeDisplayService(), preferences: preferences, overridesRoot: root)
        #expect(WelcomeRule.shouldShow(deliberate))
        preferences.hasShownWelcome = true
        #expect(!WelcomeRule.shouldShow(deliberate))

        let quiet = AppModelTests.makeModel(
            service: FakeDisplayService(), preferences: Preferences(defaults: ScratchDefaults().defaults),
            overridesRoot: root, launchKind: .atLogin
        )
        #expect(!WelcomeRule.shouldShow(quiet))
    }

    @Test func theFirstCloseNoticeIsDueOnce() {
        let preferences = Preferences(defaults: scratch.defaults)
        #expect(FirstCloseNotice.isDue(preferences))
        preferences.hasShownFirstCloseNotice = true
        #expect(!FirstCloseNotice.isDue(preferences))
    }

    @Test func withoutAMenuBarIconTheNoticeWaitsForTheNextClose() {
        let preferences = Preferences(defaults: scratch.defaults)
        let model = AppModelTests.makeModel(
            service: FakeDisplayService(), preferences: preferences,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteOnboardingTests-\(UUID().uuidString)")
        )
        #expect(!FirstCloseNotice.showIfDue(from: nil, model: model))
        // An icon that is not in a window (the menu bar hid it) can't anchor the notice either.
        #expect(!FirstCloseNotice.showIfDue(from: NSStatusBarButton(), model: model))
        #expect(FirstCloseNotice.isDue(preferences))
    }
}
