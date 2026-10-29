import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteDesign
@testable import ResoluteKit

/// What a display's page says and offers, from the design's sample displays.
@MainActor
@Suite struct DisplayPageTests {
    let builtIn = SampleDisplays.builtInRetina
    let dell = SampleDisplays.dellU2723QE
    let asus = SampleDisplays.asusPA278QV

    // MARK: - Header

    /// Figma 31:5, 34:332, 62:1020 and 37:1480.
    @Test func badgesEachKindOfDisplay() {
        typealias B = HeaderBadge
        #expect(DisplayPagePresentation.badges(
            for: builtIn.display, facts: builtIn.facts, displayCount: 2, hasOverride: false, hasUnsavedChanges: false
        ) == [B(text: "Main", tone: .neutral), B(text: "Built-in", tone: .neutral), B(text: "HiDPI", tone: .accent)])
        #expect(DisplayPagePresentation.badges(
            for: builtIn.display, facts: builtIn.facts, displayCount: 1, hasOverride: false, hasUnsavedChanges: false
        ) == [B(text: "Built-in", tone: .neutral), B(text: "HiDPI", tone: .accent)])
        #expect(DisplayPagePresentation.badges(
            for: dell.display, facts: dell.facts, displayCount: 2, hasOverride: true, hasUnsavedChanges: true
        ) == [B(text: "Override installed", tone: .accent), B(text: "Unsaved", tone: .warning)])
        #expect(DisplayPagePresentation.badges(
            for: asus.display, facts: asus.facts, displayCount: 2, hasOverride: false, hasUnsavedChanges: false
        ) == [B(text: "Standard display", tone: .neutral)])
        #expect(DisplayPagePresentation.notConnectedBadges(hasOverride: true, hasUnsavedChanges: false)
            == [B(text: "Not connected", tone: .neutral), B(text: "Override installed", tone: .accent)])
    }

    /// A Sharp Scaling override says so instead (Figma 67:1585, 67:2175): saved on a standard
    /// display, then only Sharp Scaling once its sharp sizes make the display HiDPI.
    @Test func badgesSharpScalingForWhatItIs() {
        typealias B = HeaderBadge
        #expect(DisplayPagePresentation.badges(
            for: asus.display, facts: asus.facts, displayCount: 2, hasOverride: true, hasUnsavedChanges: false,
            sharpScaling: "Sharp Scaling saved"
        ) == [B(text: "Standard display", tone: .neutral), B(text: "Sharp Scaling saved", tone: .accent)])
        #expect(DisplayPagePresentation.badges(
            for: dell.display, facts: dell.facts, displayCount: 2, hasOverride: true, hasUnsavedChanges: false,
            sharpScaling: "Sharp Scaling"
        ) == [B(text: "Sharp Scaling", tone: .accent)])
    }

    /// The header draws the draft's picture while there is one: a picture Resolute draws,
    /// or for none ("display") and another app's ("custom"), the suggestion.
    @Test func drawsTheDraftsPicture() {
        #expect(DisplayPagePresentation.picture(draftSkin: "studioDisplay", fallback: .display) == .studioDisplay)
        #expect(DisplayPagePresentation.picture(draftSkin: "display", fallback: .macBookPro) == .macBookPro)
        #expect(DisplayPagePresentation.picture(draftSkin: "custom", fallback: .iMac) == .iMac)
        #expect(DisplayPagePresentation.picture(draftSkin: nil, fallback: .tv) == .tv)
    }

    /// "Last connected 21 Oct · 5120 × 2880 pixels" from History; the IDs when it knows nothing.
    @Test func saysWhenADisplayWasLastConnected() throws {
        let lg = SampleDisplays.lgUltraFine5K
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let record = HistoryEntry.DisplayRecord(id: 4, name: "LG UltraFine 5K", vendorID: lg.key.vendorID, productID: lg.key.productID)
        func entry(_ date: Date, native: Bool) -> HistoryEntry {
            HistoryEntry(
                date: date, source: .panel,
                change: .mode(HistoryEntry.ModeChange(display: record, from: nil, to: HistoryEntry.ModeRecord(
                    modeID: 1, width: 2560, height: 1440, pixelWidth: native ? 5120 : 2560, pixelHeight: native ? 2880 : 1440,
                    refreshRate: 60, ioFlags: native ? DisplayMode.Flag.native : 0
                ))),
                outcome: .applied
            )
        }
        let history = [entry(lg.lastConnected, native: false), entry(lg.lastConnected.addingTimeInterval(-86_400), native: true)]
        let facts = DisplayPagePresentation.notConnectedFacts(
            for: lg.key, history: history, calendar: calendar, locale: Locale(identifier: "en_GB")
        )
        #expect(facts.hasPrefix("Last connected 21 Oct"))
        #expect(facts.hasSuffix(" · 5120 × 2880 pixels"))
        #expect(DisplayPagePresentation.notConnectedFacts(for: lg.key, history: []) == "Vendor 1e6d · Product 5b11")
        #expect(DisplayPagePresentation.notConnectedName(for: lg.key, listed: "Display 1e6d:5b11", history: history) == "LG UltraFine 5K")
        #expect(DisplayPagePresentation.notConnectedName(for: lg.key, listed: "Studio", history: history) == "Studio")
        #expect(DisplayPagePresentation.notConnectedName(for: lg.key, listed: nil, history: []) == "Display 1e6d:5b11")
    }

    // MARK: - Resolution tab

    /// Five sizes from Larger Text to More Space, the default captioned, pixels with ⌥.
    @Test func offersTheStops() throws {
        let stops = try #require(builtIn.stops)
        let options = ResolutionChoices.stopOptions(stops, showsPixels: false)
        #expect(options.map(\.size) == ["1168 × 755", "1312 × 848", "1496 × 967", "1728 × 1117", "2056 × 1329"])
        #expect(options.map(\.caption) == [nil, nil, nil, "Default", nil])
        #expect(options.map(\.stop) == [1, 2, 3, 4, 5])
        #expect(ResolutionChoices.stopOptions(stops, showsPixels: true)[3].size == "3456 × 2234")
        #expect(ResolutionChoices.mode(forStop: 5, in: stops)?.width == 2056)
        #expect(stops.current?.thumbnail == 4)
    }

    /// ProMotion is the built-in display's fastest rate; a monitor lists its rates in hertz.
    @Test func listsRefreshRates() {
        let rates = ResolutionChoices.rates(for: builtIn.display, facts: builtIn.facts)
        #expect(rates.map(\.title) == ["ProMotion", "60 Hz", "50 Hz", "48 Hz"])
        #expect(ResolutionChoices.currentRateKey(of: builtIn.display) == rates[0].key)
        #expect(ResolutionChoices.refreshHelp(facts: builtIn.facts) == "ProMotion adapts up to 120 Hz. Pick a fixed rate for video.")
        #expect(ResolutionChoices.rates(for: asus.display, facts: asus.facts).map(\.title) == ["75 Hz", "60 Hz", "50 Hz"])
        #expect(ResolutionChoices.refreshHelp(facts: asus.facts) == nil)
    }

    /// A standard display's resolutions, the native one marked (Figma 62:1020).
    @Test func listsAStandardDisplaysResolutions() {
        let resolutions = ResolutionChoices.resolutions(for: asus.display)
        #expect(resolutions.first?.title == "2560 × 1440 · Native")
        #expect(resolutions.count == 14)
        #expect(ResolutionChoices.standardResolutionHelp(facts: asus.facts)
            == "This display has 1× sizes only. Sizes below 2560 × 1440 are stretched to fit and look soft.")
    }

    /// All Modes' rows and tabs; Hidden only where the display has hidden modes.
    @Test func listsAllModes() throws {
        #expect(ResolutionChoices.filters(for: builtIn.display) == [.hiDPI, .lowResolution])
        #expect(ResolutionChoices.filters(for: dell.display) == [.hiDPI, .lowResolution, .hidden])
        let rows = ResolutionChoices.modeRows(for: builtIn.display, matching: .hiDPI)
        let current = try #require(rows.first { $0.values[0] == "1728 × 1117" })
        #expect(current.values == ["1728 × 1117", "HiDPI · Default", "3456 × 2234", "120 · 60 · 50 · 48 Hz"])
        #expect(current.accessibilityLabel == "1728 by 1117, HiDPI · Default, rendered at 3456 by 2234, 120 · 60 · 50 · 48 Hz")
        #expect(rows.first?.values[0] == "2056 × 1329")
        let hidden = ResolutionChoices.modeRows(for: dell.display, matching: .hidden)
        #expect(hidden.map { $0.values[0] } == ["2880 × 1620", "2560 × 1080", "2048 × 1152"])
        #expect(ResolutionChoices.hiddenFootnote(trialLength: .fifteenSeconds)
            == "Hidden modes are tried first: each switches back after 15 seconds unless you keep it on its display.")
    }

    /// Clicking a size switches the display, recorded as asked from the window.
    @Test func switchesAsAskedFromTheWindow() throws {
        let service = FakeDisplayService(displays: [builtIn.display, dell.display])
        let scratch = ScratchDefaults()
        let root = FileManager.default.temporaryDirectory.appending(path: "ResoluteDisplayPageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModelTests.makeModel(service: service, preferences: Preferences(defaults: scratch.defaults), overridesRoot: root)
        let display = try #require(model.display(for: .id(builtIn.display.id)))
        let stops = try #require(model.stops(for: display))
        let mode = try #require(ResolutionChoices.mode(forStop: 5, in: stops))
        model.apply(mode, to: display, from: .window)
        #expect(service.changes.last?.modeID == mode.modeID)
        #expect(model.historyEntries.first?.source == .window)
    }

    // MARK: - Add Resolution

    /// Figma 35:784: 3008 × 1692 HiDPI on the DELL at 2560 × 1440.
    @Test func previewsANewSize() {
        let preview = AddResolutionPreview(
            width: 3008, height: 1692, hiDPI: true, panel: dell.facts.nativeSize,
            current: (width: 2560, height: 1440), existing: [.standard(width: 5120, height: 2160)]
        )
        #expect(preview.renderingHelp == "Rendered at 6016 × 3384, then scaled to the 3840 × 2160 panel.")
        #expect(preview.title == "Looks like 3008 × 1692")
        #expect(preview.lines == [
            "More space than now (2560 × 1440); text about 15% smaller.",
            "Adds 6016 × 3384 (1×) too, the size it renders at.",
        ])
        #expect(preview.stop == 5)
        #expect(preview.warning?.hasPrefix("Some Macs can’t render scaled modes wider than 6144 pixels") == true)
    }

    /// Smaller sizes, sizes whose 1× entry is listed, 1× sizes and displays away.
    @Test func previewsOtherSizes() {
        let larger = AddResolutionPreview(
            width: 1920, height: 1080, hiDPI: true, panel: nil, current: (width: 2560, height: 1440),
            existing: [.standard(width: 3840, height: 2160)]
        )
        #expect(larger.renderingHelp == "Rendered at 3840 × 2160, then scaled to the panel.")
        #expect(larger.lines == ["Less space than now (2560 × 1440); text about 33% larger."])
        #expect(larger.stop == 1)
        #expect(larger.warning == nil)
        let oneX = AddResolutionPreview(width: 2560, height: 1440, hiDPI: false, panel: nil, current: nil, existing: [])
        #expect(oneX.renderingHelp == "2560 × 1440 pixels, drawn at 1×.")
        #expect(oneX.lines.isEmpty)
        #expect(oneX.stop == 3)
        let same = AddResolutionPreview(width: 2560, height: 1440, hiDPI: false, panel: nil, current: (2560, 1440), existing: [])
        #expect(same.lines == ["The same size as now."])
    }

    /// The panel's own ratio first, marked Native.
    @Test func offersAspectRatiosStartingWithThePanels() {
        let panel = dell.facts.nativeSize
        let choices = AspectChoice.choices(panel: panel)
        #expect(choices.map { $0.title(panel: panel) } == ["16:9 · Native", "16:10", "21:9", "32:9", "Any"])
        let ultrawide = DisplayFacts.PixelSize(width: 3440, height: 1440)
        #expect(AspectChoice.choices(panel: ultrawide).map { $0.title(panel: ultrawide) }.first == "43:18 · Native")
        #expect(AspectChoice.choices(panel: nil).map { $0.title(panel: nil) } == ["16:9", "16:10", "21:9", "32:9", "Any"])
        #expect(choices[0].matches(width: 3008, height: 1692))
        #expect(!choices[0].matches(width: 3008, height: 1700))
    }

    // MARK: - Restore Backup

    /// Figma 35:1103: "Today, 9:12", "Yesterday, 18:40", "21 Oct, 10:02".
    @Test func saysWhenEachBackupWasSaved() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_GB")
        let key = OverrideKey(vendorID: 0x10AC, productID: 0x42A3)
        let now = Date(timeIntervalSince1970: 1_793_268_000) // 29 Oct 2026, 10:00 UTC
        func choice(_ date: Date) -> CustomResolutionsModel.BackupChoice {
            CustomResolutionsModel.BackupChoice(backup: OverrideBackup(key: key, file: URL(filePath: "/tmp/b.plist"), date: date, sequence: 0))
        }
        #expect(choice(now.addingTimeInterval(-2_880)).savedText(now: now, calendar: calendar, locale: locale) == "Today, 09:12")
        #expect(choice(now.addingTimeInterval(-55_200)).savedText(now: now, calendar: calendar, locale: locale) == "Yesterday, 18:40")
        #expect(choice(now.addingTimeInterval(-8 * 86_400 + 120)).savedText(now: now, calendar: calendar, locale: locale) == "21 Oct, 10:02")
        let lastYear = choice(now.addingTimeInterval(-400 * 86_400)).savedText(now: now, calendar: calendar, locale: locale)
        #expect(lastYear.hasPrefix("24 Sep"))
        #expect(lastYear.hasSuffix(" 2025, 10:00"))
    }
}
