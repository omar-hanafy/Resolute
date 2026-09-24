import Testing
@testable import ResoluteKit

@Suite struct ModeCatalogTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    @Test func groupsTheCapturedModesByResolution() {
        let groups = ModeCatalog.groups(display.modes)
        #expect(groups.count == 22)
        #expect(groups.allSatisfy { $0.modes.count == 6 })
        #expect(groups.first?.sizeText == "3456 × 2234")
        #expect(groups.last?.sizeText == "960 × 600")
    }

    @Test func splitsHiDPIAndLowResolutionSections() {
        let sections = ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: false)
        #expect(sections.map(\.kind) == [.hiDPI, .lowResolution])
        #expect(sections[0].groups.map(\.sizeText) == [
            "2056 × 1329", "2056 × 1285", "1728 × 1117", "1728 × 1080", "1496 × 967", "1496 × 935",
            "1312 × 848", "1312 × 820", "1280 × 800", "1168 × 755", "1168 × 730", "960 × 600",
        ])
        #expect(sections[1].groups.map(\.sizeText) == [
            "3456 × 2234", "3456 × 2160", "2992 × 1934", "2992 × 1870", "2624 × 1696",
            "2624 × 1640", "2560 × 1600", "2336 × 1510", "2336 × 1460", "1920 × 1200",
        ])
        #expect(ResolutionSection.Kind.lowResolution.title == "Low Resolution (1×)")
    }

    @Test func hidesLowResolutionModesUnlessOneIsCurrent() {
        #expect(ModeCatalog.sections(for: display, includeLowResolution: false, includeHidden: false).map(\.kind) == [.hiDPI])
        let atNative = capture.display(currentModeID: 126)
        let sections = ModeCatalog.sections(for: atNative, includeLowResolution: false, includeHidden: false)
        #expect(sections.map(\.kind) == [.hiDPI, .lowResolution])
        #expect(sections[1].groups.map(\.sizeText) == ["3456 × 2234"])
    }

    @Test func marksDefaultAndNativeGroups() throws {
        let groups = ModeCatalog.groups(display.modes)
        let hiDPIDefault = try #require(groups.first { $0.sizeText == "1728 × 1117" && $0.isHiDPI })
        #expect(hiDPIDefault.isDefault)
        #expect(hiDPIDefault.isNative)
        let native = try #require(groups.first { $0.sizeText == "3456 × 2234" })
        #expect(native.isNative)
        #expect(!native.isDefault)
        #expect(groups.first { $0.sizeText == "1496 × 967" }?.isNative == false)
        #expect(native.refreshRates == [120, 60, 59.94, 50, 48, 47.95])
    }

    @Test func keepsTheCurrentRefreshRateWhenSwitchingResolution() throws {
        let group = try #require(ModeCatalog.groups(display.modes).first { $0.sizeText == "1496 × 967" })
        #expect(ModeCatalog.preferredMode(in: group, current: display.currentMode).modeID == 42)
        let at60 = capture.display(currentModeID: 55)
        #expect(ModeCatalog.preferredMode(in: group, current: at60.currentMode).modeID == 43)
    }

    @Test func picksTheCurrentModeForItsOwnGroup() throws {
        let group = try #require(ModeCatalog.groups(display.modes).first { $0.sizeText == "1728 × 1117" })
        #expect(ModeCatalog.preferredMode(in: group, current: display.currentMode).modeID == 54)
    }

    @Test func fallsBackToTheFastestSystemMode() throws {
        let fullHD = TestData.fullHD()
        let group = try #require(ModeCatalog.groups(fullHD.modes).first { $0.sizeText == "1920 × 1080" })
        let elsewhereAt75 = TestData.mode(99, 800, 600, hz: 75)
        // The hidden 75 Hz mode matches the refresh rate, but system modes come first.
        #expect(ModeCatalog.preferredMode(in: group, current: elsewhereAt75).modeID == 1)
        #expect(ModeCatalog.preferredMode(in: group, current: nil).modeID == 1)
    }

    @Test func listsRefreshRatesForTheCurrentResolution() {
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: false)
        #expect(options.map { RefreshRate.format($0.refreshRate) } == ["120 Hz", "60 Hz", "59.94 Hz", "50 Hz", "48 Hz", "47.95 Hz"])
        #expect(options.filter(\.isCurrent).map(\.mode.modeID) == [54])
    }

    @Test func includesHiddenRefreshRatesOnlyWhenAsked() {
        let fullHD = TestData.fullHD()
        #expect(ModeCatalog.refreshOptions(for: fullHD, includeHidden: false).map(\.refreshRate) == [60, 50])
        #expect(ModeCatalog.refreshOptions(for: fullHD, includeHidden: true).map(\.refreshRate) == [75, 60, 50])
    }

    @Test func usesOneStandardSectionForDisplaysWithoutHiDPI() {
        let sections = ModeCatalog.sections(for: TestData.fullHD(), includeLowResolution: false, includeHidden: false)
        #expect(sections.map(\.kind) == [.standard])
        #expect(sections[0].groups.map(\.sizeText) == ["1920 × 1080", "1280 × 720", "1024 × 768"])
    }

    @Test func putsHiddenOnlyResolutionsInTheirOwnSection() {
        let sections = ModeCatalog.sections(for: TestData.fullHD(), includeLowResolution: true, includeHidden: true)
        #expect(sections.map(\.kind) == [.standard, .hidden])
        #expect(sections[1].groups.map(\.sizeText) == ["2560 × 1440"])
        #expect(sections[0].groups[0].modes.map(\.modeID) == [1, 2, 90])
    }

    @Test func returnsNoRefreshOptionsWithoutACurrentMode() {
        #expect(ModeCatalog.refreshOptions(for: capture.display(currentModeID: 9_999), includeHidden: false).isEmpty)
    }
}
