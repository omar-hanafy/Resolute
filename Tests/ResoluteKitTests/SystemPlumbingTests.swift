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
}

@Suite struct ConfigurationScopeTests {
    @Test func mapsToCoreGraphicsOptions() {
        #expect(ConfigurationScope.permanent.option == .permanently)
        #expect(ConfigurationScope.session.option == .forSession)
        #expect(ConfigurationScope.app.option == .forAppOnly)
    }
}
