import CoreGraphics
import Foundation
import Testing
@testable import ResoluteKit

@Suite struct MirroringPlanTests {
    @Test func mirrorsEveryOtherDisplayToTheMainDisplay() {
        let steps = MirroringPlan.steps(online: [1, 5, 9], main: 5, enable: true)
        #expect(steps == [.init(display: 1, source: 5), .init(display: 9, source: 5)])
    }

    @Test func stopsMirroringWithTheNullDisplay() {
        let steps = MirroringPlan.steps(online: [1, 5], main: 1, enable: false)
        #expect(steps == [.init(display: 5, source: kCGNullDirectDisplay)])
    }
}

@Suite struct DisplayNamesTests {
    @Test func disambiguatesIdenticalNames() {
        #expect(DisplayNames.disambiguate(["DELL U2720Q", "Built-in Retina Display", "DELL U2720Q"])
            == ["DELL U2720Q (1)", "Built-in Retina Display", "DELL U2720Q (2)"])
    }

    @Test func leavesDistinctNamesAlone() {
        #expect(DisplayNames.disambiguate(["A", "B"]) == ["A", "B"])
    }

    /// A display really named "Studio (1)" next to two "Studio" displays got a twin.
    @Test func skipsSuffixesAnotherDisplayIsNamedWith() {
        #expect(DisplayNames.disambiguate(["Studio (1)", "Studio", "Studio"]) == ["Studio (1)", "Studio (2)", "Studio (3)"])
        #expect(DisplayNames.disambiguate(["A", "A", "A (2)"]) == ["A (1)", "A (3)", "A (2)"])
    }

    @Test(arguments: [
        ["Studio (1)", "Studio", "Studio"], ["A (1)", "A (1)", "A"], ["A", "A", "A (1)", "A (1)"],
        ["X (2)", "X", "X", "X (1)"], ["", "", " (1)"],
    ])
    func alwaysGivesEveryDisplayItsOwnName(_ names: [String]) {
        let result = DisplayNames.disambiguate(names)
        #expect(Set(result).count == names.count)
        // A name only one display has stays as it is.
        for (name, given) in zip(names, result) where names.filter({ $0 == name }).count == 1 {
            #expect(given == name)
        }
    }

    /// AppKit's screen list belongs to the main thread, and the command line takes its
    /// snapshots on other threads.
    @Test(.timeLimit(.minutes(1))) func readsScreensOnTheMainThreadWhenAskedFromAnother() async {
        let answers = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let caller = Thread.isMainThread
                let reader = DisplayNames.onMainThread { Thread.isMainThread }
                continuation.resume(returning: (caller, reader))
            }
        }
        #expect(answers == (false, true))
    }

    @MainActor @Test func readsScreensStraightAwayOnTheMainThread() {
        #expect(DisplayNames.onMainThread { Thread.isMainThread })
    }

    /// Swift Testing keeps the main queue serving, so the opt-in live tests, which take
    /// snapshots off the main thread, cannot hang on the screen names.
    @Test(.timeLimit(.minutes(1))) func readsScreenNamesFromATestThread() async {
        let names = await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: DisplayNames.screenNames()) }
        }
        #expect(Set(names.keys).isSubset(of: SystemDisplayService.onlineDisplayIDs()))
    }
}

/// Uses a display ID no display has, and no SkyLight, so nothing here can reach a real
/// display.
@Suite struct OfflineDisplayTests {
    let offline: CGDirectDisplayID = 0x5E5E_5E5E

    /// On macOS 27 CoreGraphics answers -1 for an ID it has never seen, which is not 0, and
    /// 0 for a display that went away.
    @Test func countsOnlyAPositiveAnswerAsOnline() throws {
        try #require(!SystemDisplayService.onlineDisplayIDs().contains(offline))
        #expect(!SystemDisplayService.isOnline(offline))
        for id in SystemDisplayService.onlineDisplayIDs() {
            #expect(SystemDisplayService.isOnline(id))
        }
    }

    @Test func refusesToSwitchADisplayThatIsNotOnline() throws {
        try #require(!SystemDisplayService.onlineDisplayIDs().contains(offline))
        #expect(throws: ResoluteError.displayNotFound("id:\(offline)")) {
            try SystemDisplayService(skyLight: nil).apply(modeID: 1, to: offline, scope: .app)
        }
    }
}

@Suite struct ConfigurationScopeTests {
    @Test func mapsToCoreGraphicsOptions() {
        #expect(ConfigurationScope.permanent.option == .permanently)
        #expect(ConfigurationScope.session.option == .forSession)
        #expect(ConfigurationScope.app.option == .forAppOnly)
    }
}
