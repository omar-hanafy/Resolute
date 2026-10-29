import Foundation
import Testing
@testable import ResoluteKit

@Suite struct SampleDisplaysTests {
    @Test func areDistinctDisplaysEachInAListedMode() throws {
        let samples = SampleDisplays.all
        #expect(samples.map(\.display.name) == ["Built-in Retina Display", "DELL U2723QE", "ASUS PA278QV"])
        #expect(Set(samples.map(\.id)).count == samples.count)
        #expect(samples.filter(\.display.isMain).map(\.display.name) == ["Built-in Retina Display"])
        for sample in samples {
            let display = sample.display
            let current = try #require(display.currentMode, "\(display.name)")
            #expect(current.origin == .system, "\(display.name)")
            #expect(Set(display.modes.map(\.modeID)).count == display.modes.count, "\(display.name)")
            #expect(Set(display.modes.compactMap(\.privateIndex)).count == display.modes.count, "\(display.name)")
            #expect(display.privateModes == .trusted, "\(display.name)")
            #expect(display.modes.allSatisfy { $0.pixelWidth >= $0.width && $0.pixelHeight >= $0.height })
            #expect(sample.details.physicalSize != nil, "\(display.name)")
        }
    }

    @Test func builtInIsTheCaptureAtTheFourRatesTheDesignShows() throws {
        var expected = try CapturedDisplay.load().display()
        expected.modes = expected.modes.filter { [12_000, 6_000, 5_000, 4_800].contains($0.refreshKey) }
        #expect(SampleDisplays.builtInRetina.display == expected)
        #expect(SampleDisplays.builtInRetina.display.modes.count == 88)
        let rates = ModeCatalog.refreshOptions(for: SampleDisplays.builtInRetina.display, includeHidden: false)
        #expect(rates.map { RefreshRate.format($0.refreshRate) } == ["120 Hz", "60 Hz", "50 Hz", "48 Hz"])
        #expect(SampleDisplays.builtInRetina.details == DisplayDetails(
            physicalSize: .init(width: 344.24, height: 222.52), macModel: "Mac14,10", macName: "MacBook Pro (16-inch, 2023)"
        ))
    }

    @Test func dellListsTheSizesTheDesignShows() throws {
        let dell = SampleDisplays.dellU2723QE.display
        #expect(OverrideKey(display: dell).relativePath == "DisplayVendorID-10ac/DisplayProductID-42a3")
        let current = try #require(dell.currentMode)
        #expect(current.sizeText == "2560 × 1440" && current.isHiDPI && current.refreshRate == 60)

        let listed = ModeCatalog.sections(for: dell, includeLowResolution: true, includeHidden: false)
        #expect(listed.map(\.kind) == [.hiDPI, .lowResolution])
        #expect(listed[0].groups.map(\.sizeText) == [
            "3360 × 1890", "3008 × 1692", "2560 × 1440", "2304 × 1296", "1920 × 1080", "1600 × 900", "1280 × 720",
        ])
        #expect(listed[0].groups.filter(\.isDefault).map(\.sizeText) == ["1920 × 1080"])
        #expect(listed[1].groups.count == 12)
        #expect(listed[1].groups.first?.sizeText == "3840 × 2160")
        #expect(listed[1].groups.first?.badge == "Native")

        let hidden = ModeCatalog.sections(for: dell, includeLowResolution: true, includeHidden: true).last
        #expect(hidden?.kind == .hidden)
        #expect(hidden?.groups.map(\.sizeText) == ["2880 × 1620", "2560 × 1080", "2048 × 1152"])
        #expect(dell.hiddenModeCount == 3)
        let rates = ModeCatalog.refreshOptions(for: dell, includeHidden: false)
        #expect(rates.map { RefreshRate.format($0.refreshRate) } == ["60 Hz", "50 Hz", "30 Hz"])
    }

    @Test func asusHasOnly1xSizes() throws {
        let asus = SampleDisplays.asusPA278QV.display
        #expect(asus.modes.filter(\.isHiDPI).isEmpty)
        #expect(asus.modes.filter(\.isDefault).isEmpty)
        let current = try #require(asus.currentMode)
        #expect(current.sizeText == "2560 × 1440" && current.refreshRate == 75 && current.isNative)
        let sections = ModeCatalog.sections(for: asus, includeLowResolution: true, includeHidden: true)
        #expect(sections.map(\.kind) == [.standard])
        #expect(sections[0].groups.count == 14)
        #expect(sections[0].groups.first?.badge == "Native")
        let rates = ModeCatalog.refreshOptions(for: asus, includeHidden: false)
        #expect(rates.map { RefreshRate.format($0.refreshRate) } == ["75 Hz", "60 Hz", "50 Hz"])
    }

    @Test func lgUltraFineIsAnOverrideForADisplayThatIsAway() throws {
        let lg = SampleDisplays.lgUltraFine5K
        #expect(lg.name == "LG UltraFine 5K")
        #expect(lg.key.relativePath == "DisplayVendorID-1e6d/DisplayProductID-5b11")
        #expect(lg.override.key == lg.key)
        #expect(lg.nativeSize.text == "5120 × 2880")
        #expect(lg.skin == .display)
        #expect(lg.override.resolutions.map(\.summary) == [
            "2560 × 1440 HiDPI (5120 × 2880 px, flags 00000009 00a00000)",
            "3200 × 1800 HiDPI (6400 × 3600 px, flags 00000009 00a00000)",
            "5120 × 2880 1×",
        ])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = utc.dateComponents([.year, .month, .day], from: lg.lastConnected)
        #expect(day.year == 2026 && day.month == 10 && day.day == 21)
        // The override reads back as written.
        let data = try lg.override.propertyListData()
        #expect(try DisplayOverride(key: lg.key, propertyList: data).resolutions == lg.override.resolutions)
    }

    @Test func suggestTheDesignsPictures() {
        #expect(SampleDisplays.all.map(\.skin) == [.macBookPro, .display, .display])
    }

    @Test func showTheFactsAndStopsTheDesignShows() throws {
        let builtIn = try #require(SampleDisplays.builtInRetina.stops)
        #expect(builtIn.currentLabel == "1728 × 1117 · Default")
        #expect(builtIn.currentIndex == 3)
        let dell = try #require(SampleDisplays.dellU2723QE.stops)
        #expect(dell.currentLabel == "2560 × 1440")
        #expect(dell.currentIndex == 3)
        #expect(SampleDisplays.asusPA278QV.stops == nil)
        #expect(SampleDisplays.all.map(\.facts.summary) == [
            "1728 × 1117 · 120 Hz", "2560 × 1440 · 60 Hz", "2560 × 1440 · 75 Hz",
        ])
        #expect(SampleDisplays.all.map(\.facts.badge) == ["Default", nil, "Standard"])
        #expect(SampleDisplays.all.map(\.facts.resolutionCount) == [22, 19, 14])
    }
}
