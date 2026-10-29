import CoreGraphics
import Foundation
import Testing
@testable import ResoluteKit

@Suite struct SpaceStopsTests {
    let capture: CapturedDisplay

    init() throws {
        capture = try CapturedDisplay.load()
    }

    /// A display listing HiDPI sizes of `widths` in the panel's shape and the panel's own 1× size, at 60 Hz.
    static func display(
        hiDPI widths: [Int], defaultWidth: Int?, panel: (Int, Int) = (3840, 2160), currentWidth: Int? = nil
    ) -> Display {
        var modes = widths.enumerated().map { index, width in
            TestData.mode(
                Int32(index + 1), width, width * panel.1 / panel.0, scale: 2,
                flags: width == defaultWidth ? 0x7 : 0x3
            )
        }
        modes.append(TestData.mode(100, panel.0, panel.1, flags: 0x0200_0003))
        let current = modes.first { $0.width == (currentWidth ?? defaultWidth) }?.modeID ?? 100
        return Display(id: 9, name: "Test Display", currentModeID: current, modes: modes)
    }

    @Test func offersTheFiveSizesSystemSettingsShowsOnThe16InchMacBookPro() throws {
        let stops = try #require(SpaceStops(display: capture.display()))
        #expect(stops.stops.map(\.label) == ["1168 × 755", "1312 × 848", "1496 × 967", "1728 × 1117", "2056 × 1329"])
        #expect(stops.stops.map(\.isDefault) == [false, false, false, true, false])
        #expect(stops.stops.map(\.isCurrent) == [false, false, false, true, false])
        #expect(stops.currentIndex == 3)
        #expect(stops.current?.key == ResolutionGroup.Key(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234))
        #expect(stops.currentLabel == "1728 × 1117 · Default")
        #expect(stops.stops.map(\.thumbnail) == [1, 2, 3, 4, 5])
    }

    @Test func switchesEachStopAtTheCurrentRefreshRate() throws {
        let at120 = try #require(SpaceStops(display: capture.display()))
        #expect(at120.stops.map(\.mode.modeID) == [12, 30, 42, 54, 72])
        let at60 = try #require(SpaceStops(display: capture.display(currentModeID: 55)))
        #expect(at60.stops.map(\.mode.modeID) == [13, 31, 43, 55, 73])
        let at4795 = try #require(SpaceStops(display: capture.display(currentModeID: 59)))
        #expect(at4795.stops.map(\.mode.modeID) == [17, 35, 47, 59, 77])
    }

    @Test func namesTheSizeInUseWhenItIsNotAStop() throws {
        let native = try #require(SpaceStops(display: capture.display(currentModeID: 126)))
        #expect(native.currentIndex == nil)
        #expect(native.current == nil)
        #expect(native.stops.allSatisfy { !$0.isCurrent })
        #expect(native.currentLabel == "3456 × 2234 · Native")
        #expect(native.stops.count == 5)

        let wide = try #require(SpaceStops(display: capture.display(currentModeID: 48)))
        #expect(wide.currentIndex == nil)
        #expect(wide.currentLabel == "1728 × 1080")
        // The 16:10 size in use keeps its 120 Hz for every stop.
        #expect(wide.stops.map(\.mode.modeID) == [12, 30, 42, 54, 72])

        let unknown = try #require(SpaceStops(display: capture.display(currentModeID: 9_999)))
        #expect(unknown.currentIndex == nil)
        #expect(unknown.currentLabel == nil)
    }

    @Test func hasNoStopsForADisplayWithoutRetinaSizes() {
        #expect(SpaceStops(display: TestData.fullHD()) == nil)
        #expect(SpaceStops(display: SampleDisplays.asusPA278QV.display) == nil)
        // One HiDPI size is not a scale.
        #expect(SpaceStops(display: Self.display(hiDPI: [1920], defaultWidth: 1920)) == nil)
        #expect(SpaceStops(display: Display(id: 1, name: "Empty", currentModeID: nil, modes: [])) == nil)
    }

    @Test func picksEvenStepsFromTheSmallestToTheLargestKeepingTheDefault() throws {
        let stops = try #require(SpaceStops(display: SampleDisplays.dellU2723QE.display))
        #expect(stops.stops.map(\.label) == ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440", "3360 × 1890"])
        #expect(stops.stops.map(\.isDefault) == [false, false, true, false, false])
        #expect(stops.currentIndex == 3)
        #expect(stops.currentLabel == "2560 × 1440")
        #expect(stops.stops.allSatisfy { $0.mode.refreshRate == 60 && $0.mode.origin == .system && $0.mode.isHiDPI })
    }

    @Test func leavesHiddenSizesToAllResolutions() throws {
        var dell = SampleDisplays.dellU2723QE.display
        let hidden = try #require(dell.modes.first { $0.origin == .hidden && $0.width == 2048 })
        dell.currentModeID = hidden.modeID
        let stops = try #require(SpaceStops(display: dell))
        #expect(!stops.stops.map(\.label).contains("2048 × 1152"))
        #expect(!stops.stops.map(\.label).contains("2880 × 1620"))
        #expect(stops.currentIndex == nil)
        #expect(stops.currentLabel == "2048 × 1152")
    }

    @Test func keepsTheDefaultWhereEvenStepsWouldSkipIt() throws {
        let widths = [1280, 1360, 1440, 1600, 1920, 2048, 2560]
        let stops = try #require(SpaceStops(display: Self.display(hiDPI: widths, defaultWidth: 1360)))
        #expect(stops.stops.count == 5)
        #expect(stops.stops.first?.label == "1280 × 720")
        #expect(stops.stops.last?.label == "2560 × 1440")
        #expect(stops.stops.filter(\.isDefault).map(\.label) == ["1360 × 765"])
        let withoutDefault = try #require(SpaceStops(display: Self.display(hiDPI: widths, defaultWidth: nil, currentWidth: 1360)))
        #expect(!withoutDefault.stops.map(\.label).contains("1360 × 765"))
    }

    @Test func staysBetweenHalfAndTwiceTheDefaultWidth() throws {
        // An iMac-like list: 4480 × 2520 panel, default 2240 × 1260, sizes down to 640 × 360.
        let widths = [640, 800, 960, 1120, 1280, 1600, 1920, 2240, 2560]
        let stops = try #require(SpaceStops(display: Self.display(hiDPI: widths, defaultWidth: 2240, panel: (4480, 2520))))
        #expect(stops.stops.map(\.label) == ["1120 × 630", "1280 × 720", "1600 × 900", "2240 × 1260", "2560 × 1440"])
        #expect(stops.currentIndex == 3)
    }

    @Test func matchesThePanelsShapeWithinOnePercent() throws {
        // The 14-inch MacBook Pro (3024 × 1964): the sizes Apple's override file lists for it,
        // and two 16:10 sizes that would leave bars.
        let sizes = [(1024, 665), (1147, 745), (1352, 878), (1512, 982), (1800, 1169), (1352, 845), (1512, 945)]
        var modes = sizes.enumerated().map { index, size in
            TestData.mode(Int32(index + 1), size.0, size.1, scale: 2, hz: 120, flags: size == (1512, 982) ? 0x7 : 0x3)
        }
        modes.append(TestData.mode(50, 3024, 1964, hz: 120, flags: 0x0200_0003))
        let display = Display(id: 1, name: "Built-in", isBuiltin: true, currentModeID: 4, modes: modes)
        let stops = try #require(SpaceStops(display: display))
        #expect(stops.stops.map(\.label) == ["1024 × 665", "1147 × 745", "1352 × 878", "1512 × 982", "1800 × 1169"])
    }

    @Test func spreadsFewerStopsOverTheFivePictures() throws {
        #expect((0..<2).map { SpaceStops.thumbnail(at: $0, of: 2) } == [1, 5])
        #expect((0..<3).map { SpaceStops.thumbnail(at: $0, of: 3) } == [1, 3, 5])
        #expect((0..<4).map { SpaceStops.thumbnail(at: $0, of: 4) } == [1, 2, 4, 5])
        let uhd = try #require(SpaceStops(display: TestData.uhd()))
        #expect(uhd.stops.map(\.label) == ["1920 × 1080", "2560 × 1440"])
        #expect(uhd.stops.map(\.thumbnail) == [1, 5])
        #expect(uhd.currentLabel == "1920 × 1080 · Default")
    }

    @Test func readsSizesWithByForVoiceOver() throws {
        let stops = try #require(SpaceStops(display: capture.display()))
        #expect(stops.stops[3].accessibilityLabel == "1728 by 1117, Default")
        #expect(stops.stops[0].accessibilityLabel == "1168 by 755")
        #expect(DisplayFacts.spoken("1728 × 1117 · 120 Hz") == "1728 by 1117, 120 Hz")
    }
}

@Suite struct DisplayFactsTests {
    @Test func describesTheBuiltInDisplayAsTheDesignDoes() {
        let facts = SampleDisplays.builtInRetina.facts
        #expect(facts.kind == .retina)
        #expect(facts.diagonal == "16.2-inch")
        #expect(facts.nativeSize == DisplayFacts.PixelSize(width: 3456, height: 2234))
        #expect(facts.nativePixels == "3456 × 2234 pixels")
        #expect(facts.maximumRefreshRate == 120)
        #expect(facts.hasProMotion)
        #expect(facts.refresh == "ProMotion up to 120 Hz")
        #expect(facts.summary == "1728 × 1117 · 120 Hz")
        #expect(facts.badge == "Default")
        #expect(facts.resolutionCount == 22)
        #expect(facts.specifications == "16.2-inch · 3456 × 2234 pixels · ProMotion up to 120 Hz")
    }

    @Test func describesTheCapturedDisplayWithAllItsRates() throws {
        let facts = DisplayFacts(
            display: try CapturedDisplay.load().display(),
            details: DisplayDetails(physicalSize: .init(width: 344.2447, height: 222.5239))
        )
        #expect(facts.diagonal == "16.2-inch")
        #expect(facts.refresh == "ProMotion up to 120 Hz")
        #expect(facts.resolutionCount == 22)
    }

    @Test func describesExternalDisplaysAsTheDesignDoes() {
        let dell = SampleDisplays.dellU2723QE.facts
        #expect(dell.kind == .retina)
        #expect(dell.specifications == "27-inch · 3840 × 2160 pixels · 60 Hz")
        #expect(dell.summary == "2560 × 1440 · 60 Hz")
        #expect(dell.badge == nil)
        #expect(dell.resolutionCount == 19)
        #expect(!dell.hasProMotion)

        let asus = SampleDisplays.asusPA278QV.facts
        #expect(asus.kind == .standard)
        #expect(asus.specifications == "27-inch · 2560 × 1440 pixels · up to 75 Hz")
        #expect(asus.summary == "2560 × 1440 · 75 Hz")
        #expect(asus.badge == "Standard")
        #expect(asus.resolutionCount == 14)
    }

    @Test func roundsDiagonalsTheWayAppleSellsDisplays() {
        func diagonal(
            _ width: Double, _ height: Double, panel: (Int, Int), builtIn: Bool, vendor: UInt32 = 0x10AC
        ) -> String? {
            let display = Display(
                id: 1, name: "Test", vendorID: builtIn ? 0x610 : vendor, isBuiltin: builtIn, currentModeID: nil, modes: []
            )
            return DisplayFacts.diagonal(
                of: .init(width: width, height: height),
                panel: .init(width: panel.0, height: panel.1),
                display: display
            )
        }
        // What the 16-inch MacBook Pro reports is 16.14 inches; Apple sells it as 16.2.
        #expect(diagonal(344.24, 222.52, panel: (3456, 2234), builtIn: true) == "16.2-inch")
        // The 14-inch at the same density, the 13.6-inch MacBook Air at its exact size, the
        // 2019 16-inch MacBook Pro and the 24-inch iMac's 23.5-inch picture.
        #expect(diagonal(301.21, 195.63, panel: (3024, 1964), builtIn: true) == "14.2-inch")
        #expect(diagonal(290.29, 188.69, panel: (2560, 1664), builtIn: true) == "13.6-inch")
        #expect(diagonal(345.26, 215.79, panel: (3072, 1920), builtIn: true) == "16-inch")
        #expect(diagonal(522.0, 293.6, panel: (4480, 2520), builtIn: true) == "24-inch")
        // A built-in size Apple has not sold keeps its tenths.
        #expect(diagonal(383.0, 239.4, panel: (3456, 2160), builtIn: true) == "17.8-inch")
        // Monitors in whole inches, as they are sold: 31.5-inch panels are "32-inch".
        #expect(diagonal(597, 336, panel: (3840, 2160), builtIn: false) == "27-inch")
        #expect(diagonal(697, 392, panel: (3840, 2160), builtIn: false) == "32-inch")
        #expect(diagonal(527, 296, panel: (1920, 1080), builtIn: false) == "24-inch")
        #expect(diagonal(800, 335, panel: (3440, 1440), builtIn: false) == "34-inch")
        // Apple's own monitors take Apple's sizes: the Pro Display XDR's picture is 31.66 inches.
        #expect(diagonal(701, 394, panel: (6016, 3384), builtIn: false, vendor: 0x610) == "32-inch")
        #expect(diagonal(597, 336, panel: (5120, 2880), builtIn: false, vendor: 0x610) == "27-inch")
    }

    @Test func leavesOutASizeThatDoesNotFitThePixels() {
        let display = Display(id: 1, name: "TV", currentModeID: nil, modes: [])
        let panel = DisplayFacts.PixelSize(width: 3840, height: 2160)
        // Some TVs report 16 × 9 cm to give their shape, not their size.
        #expect(DisplayFacts.diagonal(of: .init(width: 160, height: 90), panel: panel, display: display) == nil)
        #expect(DisplayFacts.diagonal(of: .init(width: 0, height: 0), panel: panel, display: display) == nil)
        #expect(DisplayFacts.diagonal(of: nil, panel: panel, display: display) == nil)
        #expect(DisplayFacts(display: TestData.uhd(), details: DisplayDetails()).specifications == "3840 × 2160 pixels · 60 Hz")
    }

    @Test func saysUpToOnlyForDisplaysFasterThan60Hz() {
        func refresh(_ rates: [Double], builtIn: Bool = false, hidden: [Double] = []) -> DisplayFacts {
            let listed = rates.enumerated().map { TestData.mode(Int32($0.offset + 1), 1920, 1080, hz: $0.element) }
            let extra = hidden.enumerated().map {
                TestData.mode(Int32($0.offset + 50), 1920, 1080, hz: $0.element, flags: 0x1, origin: .hidden)
            }
            let display = Display(id: 1, name: "Test", isBuiltin: builtIn, currentModeID: 1, modes: listed + extra)
            return DisplayFacts(display: display, details: DisplayDetails())
        }
        #expect(refresh([60, 50, 30]).refresh == "60 Hz")
        #expect(refresh([144, 120, 60]).refresh == "up to 144 Hz")
        #expect(refresh([75]).refresh == "75 Hz")
        #expect(refresh([59.94]).refresh == "59.94 Hz")
        // A fast external panel is not ProMotion, and a built-in 60 Hz one has nothing to adapt.
        #expect(refresh([120, 60]).refresh == "up to 120 Hz")
        #expect(!refresh([120, 60]).hasProMotion)
        #expect(refresh([60], builtIn: true).refresh == "60 Hz")
        #expect(!refresh([60], builtIn: true).hasProMotion)
        // Hidden rates are not the display's to promise.
        #expect(refresh([60, 50], hidden: [75]).refresh == "60 Hz")
        #expect(refresh([0]).refresh == nil)
        #expect(refresh([0]).summary == "1920 × 1080")
    }

    @Test func badgesTheSizeInUse() throws {
        let capture = try CapturedDisplay.load()
        let details = DisplayDetails()
        #expect(DisplayFacts(display: capture.display(), details: details).badge == "Default")
        #expect(DisplayFacts(display: capture.display(currentModeID: 126), details: details).badge == "Native")
        #expect(DisplayFacts(display: capture.display(currentModeID: 48), details: details).badge == nil)
        #expect(DisplayFacts(display: capture.display(currentModeID: 9_999), details: details).summary == nil)
        #expect(DisplayFacts(display: TestData.fullHD(), details: details).badge == "Standard")
    }

    @Test func countsWhatAllResolutionsLists() throws {
        let display = try CapturedDisplay.load().display()
        #expect(DisplayFacts.resolutionCount(for: display) == 22)
        #expect(DisplayFacts.resolutionCount(for: display, includeLowResolution: false) == 12)
        #expect(DisplayFacts.resolutionCount(for: TestData.fullHD()) == 3)
        #expect(DisplayFacts.resolutionCount(for: TestData.fullHD(), includeHidden: true) == 4)
        #expect(DisplayFacts.resolutionCount(for: SampleDisplays.dellU2723QE.display, includeHidden: true) == 22)
    }

    @Test func findsThePanelSizeWithoutANativeFlag() {
        let modes = [TestData.mode(1, 1920, 1080), TestData.mode(2, 2560, 1440), TestData.mode(3, 1280, 720, scale: 2)]
        let display = Display(id: 1, name: "Test", currentModeID: 1, modes: modes)
        #expect(DisplayFacts.nativeSize(of: display) == DisplayFacts.PixelSize(width: 2560, height: 1440))
        #expect(DisplayFacts.nativeSize(of: Display(id: 1, name: "Empty", currentModeID: nil, modes: [])) == nil)
    }
}

@Suite struct DisplayDetailsTests {
    @Test func ignoresTheSizeCoreGraphicsGuesses() {
        // With no size from the display, CoreGraphics guesses one from its bounds at 72 dpi.
        #expect(DisplayDetails.physicalSize(
            reported: CGSize(width: 1354.67, height: 762), bounds: CGSize(width: 3840, height: 2160)
        ) == nil)
        #expect(DisplayDetails.physicalSize(reported: .zero, bounds: CGSize(width: 1920, height: 1080)) == nil)
        #expect(DisplayDetails.physicalSize(
            reported: CGSize(width: 597, height: 336), bounds: CGSize(width: 2560, height: 1440)
        ) == DisplayDetails.PhysicalSize(width: 597, height: 336))
    }

    @Test func knowsAnIMacsScreen() {
        #expect(DisplayDetails(macModel: "iMac21,1").isIMacScreen)
        #expect(DisplayDetails(macModel: "iMac19,1").isIMacScreen)
        #expect(DisplayDetails(macModel: "Mac15,4").isIMacScreen)
        #expect(DisplayDetails(macModel: "Mac16,3", macName: "iMac (24-inch, 2024)").isIMacScreen)
        #expect(DisplayDetails(macModel: "Mac99,1", macName: "iMac (24-inch, 2027)").isIMacScreen)
        #expect(!DisplayDetails(macModel: "Mac14,10", macName: "MacBook Pro (16-inch, 2023)").isIMacScreen)
        #expect(!DisplayDetails().isIMacScreen)
    }

    @Test func readsTheMacOnlyForABuiltInDisplay() {
        // No display has this ID, so there is no size to read and none is made up. (0 would
        // not do: CoreGraphics takes it to mean the main display.)
        let away = CGDirectDisplayID.max
        let external = DisplayDetails.read(for: Display(id: away, name: "Away", currentModeID: nil, modes: []))
        #expect(external == DisplayDetails())
        let builtIn = DisplayDetails.read(for: Display(id: away, name: "Away", isBuiltin: true, currentModeID: nil, modes: []))
        #expect(builtIn.physicalSize == nil)
        #expect(builtIn.macModel?.isEmpty == false)
    }
}

@Suite struct DisplaySkinSuggestionTests {
    func display(
        _ name: String, vendor: UInt32 = 0x10AC, product: UInt32 = 0x1234, panel: (Int, Int) = (3840, 2160),
        builtIn: Bool = false
    ) -> Display {
        Display(
            id: 5, name: name, vendorID: vendor, productID: product, isBuiltin: builtIn, currentModeID: 1,
            modes: [TestData.mode(1, panel.0, panel.1, flags: 0x0200_0003)]
        )
    }

    @Test func matchesTheDesignSystemsPictures() {
        #expect(DisplaySkin.allCases.map(\.rawValue) == [
            "macBookPro", "iMac", "studioDisplay", "proDisplayXDR", "display", "ultrawide", "tv",
        ])
    }

    @Test func givesABuiltInDisplayItsMacsPicture() {
        let builtIn = display("Built-in Retina Display", vendor: 0x610, product: 0xA050, panel: (3456, 2234), builtIn: true)
        #expect(DisplaySkin.suggestion(for: builtIn, details: SampleDisplays.builtInRetina.details) == .macBookPro)
        #expect(DisplaySkin.suggestion(for: builtIn, details: DisplayDetails()) == .macBookPro)
        let iMac = DisplayDetails(macModel: "Mac16,2", macName: "iMac (24-inch, 2024)")
        #expect(DisplaySkin.suggestion(for: builtIn, details: iMac) == .iMac)
    }

    @Test func knowsApplesDisplaysByProductID() {
        func skin(_ name: String, vendor: UInt32 = 0x610, product: UInt32, panel: (Int, Int) = (5120, 2880)) -> DisplaySkin {
            DisplaySkin.suggestion(for: display(name, vendor: vendor, product: product, panel: panel), details: DisplayDetails())
        }
        #expect(skin("Studio Display", product: 0xAE3A) == .studioDisplay)
        #expect(skin("Studio Display XDR", product: 0xAE42) == .studioDisplay)
        #expect(skin("Pro Display XDR", product: 0xAE22, panel: (6016, 3384)) == .proDisplayXDR)
        #expect(skin("Thunderbolt Display", product: 0x9227, panel: (2560, 1440)) == .display)
        // Another vendor's product with a Pro Display XDR's product ID is not one.
        #expect(skin("Monitor", vendor: 0x10AC, product: 0xAE22) == .display)
    }

    @Test func callsWidePanelsUltrawide() {
        let details = DisplayDetails()
        #expect(DisplaySkin.suggestion(for: display("LG ULTRAWIDE", panel: (3440, 1440)), details: details) == .ultrawide)
        #expect(DisplaySkin.suggestion(for: display("Odyssey G9", panel: (5120, 1440)), details: details) == .ultrawide)
        #expect(DisplaySkin.suggestion(for: display("29WN600", panel: (2560, 1080)), details: details) == .ultrawide)
        #expect(DisplaySkin.suggestion(for: display("U2723QE", panel: (3840, 2160)), details: details) == .display)
        #expect(DisplaySkin.suggestion(for: display("Old Monitor", panel: (1600, 1200)), details: details) == .display)
    }

    @Test func callsTelevisionsTV() {
        let details = DisplayDetails()
        for name in ["LG TV SSCR2", "SONY TV  *00", "Panasonic-TV", "Living Room TV", "BRAVIA KD-55X85J", "VIZIO V505"] {
            #expect(DisplaySkin.suggestion(for: display(name), details: details) == .tv, "\(name)")
        }
        for name in ["TVS Monitor", "DELL U2723QE", "LG HDR 4K", "ASUS PA278QV"] {
            #expect(DisplaySkin.suggestion(for: display(name), details: details) == .display, "\(name)")
        }
    }
}

/// Reads this Mac's displays and changes nothing. Run with RESOLUTE_LIVE_TESTS=1 and
/// `--filter LivePresentationTests --skip LiveDisplayTests`: the same variable turns on
/// LiveDisplayTests, which switch the display's refresh rate.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_TESTS"] == "1"))
struct LivePresentationTests {
    let displays = SystemDisplayService().displays()

    var builtIn: Display? {
        displays.first { $0.isBuiltin }
    }

    /// On MacBooks, Apple's override file for the built-in panel lists the Retina sizes
    /// System Settings offers (all but the default on a MacBook Air): each one is a stop.
    @Test func offersEverySizeApplesOverrideListsForTheBuiltInPanel() throws {
        let builtIn = try #require(self.builtIn, "This Mac has no built-in display.")
        let stops = try #require(SpaceStops(display: builtIn))
        let apple = try #require(try OverrideStore().systemOverride(for: OverrideKey(display: builtIn)))
        let listed = apple.resolutions.compactMap { entry -> String? in
            guard case .standard(let width, let height) = entry else { return nil }
            return "\(width / 2) × \(height / 2)"
        }
        try #require(listed.count <= SpaceStops.maximumCount, "Apple lists \(listed) for this panel.")
        #expect(Set(listed).isSubset(of: stops.stops.map(\.label)), "\(stops.stops.map(\.label))")
        #expect(stops.stops.filter(\.isDefault).count == 1)
    }

    @Test func describesTheBuiltInPanel() throws {
        let builtIn = try #require(self.builtIn, "This Mac has no built-in display.")
        let details = DisplayDetails.read(for: builtIn)
        let facts = DisplayFacts(display: builtIn, details: details)
        #expect(details.macModel?.isEmpty == false)
        #expect(facts.diagonal != nil)
        if facts.nativeSize == DisplayFacts.PixelSize(width: 3456, height: 2234) {
            #expect(facts.specifications == "16.2-inch · 3456 × 2234 pixels · ProMotion up to 120 Hz")
            #expect(DisplaySkin.suggestion(for: builtIn, details: details) == .macBookPro)
        }
    }

    @Test func describesEveryDisplay() {
        for display in displays {
            let facts = DisplayFacts(display: display, details: DisplayDetails.read(for: display))
            #expect(facts.nativeSize != nil, "\(display.name)")
            #expect(facts.summary != nil, "\(display.name)")
            #expect(facts.resolutionCount > 0, "\(display.name)")
            #expect((facts.kind == .retina) == (SpaceStops(display: display) != nil), "\(display.name)")
        }
    }
}
