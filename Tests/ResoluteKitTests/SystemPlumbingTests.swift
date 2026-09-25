import CoreGraphics
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
}

@Suite struct ConfigurationScopeTests {
    @Test func mapsToCoreGraphicsOptions() {
        #expect(ConfigurationScope.permanent.option == .permanently)
        #expect(ConfigurationScope.session.option == .forSession)
        #expect(ConfigurationScope.app.option == .forAppOnly)
    }
}
