import Testing
@testable import ResoluteKit

@Suite struct ModeQueryTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    @Test(arguments: ["1920x1080", "1920×1080", "1920 x 1080", "1920X1080"])
    func parsesPlainResolutions(text: String) throws {
        let query = try ModeQuery(resolution: text)
        #expect(query.width == 1920)
        #expect(query.height == 1080)
        #expect(query.scale == nil)
        #expect(query.refreshRate == nil)
    }

    @Test func parsesScaleAndRefreshRate() throws {
        let query = try ModeQuery(resolution: "1728x1117@2x@59.94Hz")
        #expect(query.scale == 2)
        #expect(query.refreshRate == 59.94)
        #expect(try ModeQuery(resolution: "1920x1200@60").refreshRate == 60)
        #expect(query.summary == "1728 × 1117 @2x 59.94 Hz")
    }

    @Test(arguments: ["", "1920", "1920x", "x1080", "0x0", "1920x1080@", "1920x1080@fast", "-1920x1080"])
    func rejectsMalformedResolutions(text: String) {
        #expect(throws: ResoluteError.invalidResolution(text)) {
            try ModeQuery(resolution: text)
        }
    }

    /// Numbers no display has would overflow later arithmetic (sizes are multiplied, rates
    /// and scales become integers), so the parser turns them away.
    @Test(arguments: ["1920x1080@1e300", "1920x1080@inf", "1920x1080@20000hz", "1920x1080@1e308x", "1920x1080@infx", "1920x1080@16x"])
    func rejectsNumbersNoDisplayHas(text: String) {
        #expect(throws: ResoluteError.invalidResolution(text)) {
            try ModeQuery(resolution: text)
        }
    }

    /// `Double(_:)` also reads hexadecimal, exponents, signs, "inf" and "nan", so "@0x3c" was
    /// 60 Hz. Rates and scales are plain decimal numbers.
    @Test(arguments: [
        "1920x1080@0x3c", "1920x1080@6e1", "1920x1080@+60", "1920x1080@60.", "1920x1080@.5x", "1920x1080@0x2x",
        "1920x1080@2e0x", "1920x1080@nan", "1920x1080@59,94", "1920x1080@٦٠",
    ])
    func acceptsOnlyDecimalRatesAndScales(text: String) {
        #expect(throws: ResoluteError.invalidResolution(text)) {
            try ModeQuery(resolution: text)
        }
    }

    @Test func readsDecimalNumbers() {
        #expect(ModeQuery.decimal("60") == 60)
        #expect(ModeQuery.decimal("59.94") == 59.94)
        #expect(ModeQuery.decimal("0.5") == 0.5)
        for text in ["", "0x3c", "6e1", "+60", "-60", "60.", ".5", "inf", "nan", "1,5", "٦٠", " 60"] {
            #expect(ModeQuery.decimal(text) == nil, "\(text)")
        }
    }

    @Test(arguments: ["9223372036854775807x2", "70000x1080", "1920x70000", "99999999999999999999999x2"])
    func saysHowBigASizeMayBe(text: String) {
        #expect(throws: ResoluteError.sizeTooLarge(text)) {
            try ModeQuery(resolution: text)
        }
        #expect(ResoluteError.sizeTooLarge(text).errorDescription == "“\(text)” is larger than any display: sizes go up to 65535.")
    }

    @Test(arguments: ["1496x967@60@50", "1496x967@2x@1x", "1496x967@2x@60hz@2x", "1920x1080@0.5"])
    func rejectsRepeatedOrImpossibleParts(text: String) {
        #expect(throws: ResoluteError.invalidResolution(text)) {
            try ModeQuery(resolution: text)
        }
    }

    @Test func listsTheRatesOnOfferWhenOneIsMissing() {
        let offered = ["120 Hz", "60 Hz", "59.94 Hz", "50 Hz", "48 Hz", "47.95 Hz"]
        let kept = ResoluteError.refreshRateNotOffered(resolution: "1728 × 1117 HiDPI", rate: "55 Hz", offered: offered)
        #expect(throws: kept) { try ModeQuery(refreshRate: 55).resolve(on: display) }
        #expect(throws: ResoluteError.refreshRateNotOffered(resolution: "1496 × 967 HiDPI", rate: "55 Hz", offered: offered)) {
            try ModeQuery(resolution: "1496x967@55").resolve(on: display)
        }
        #expect(kept.errorDescription
            == "1728 × 1117 HiDPI has no 55 Hz mode. It offers 120 Hz, 60 Hz, 59.94 Hz, 50 Hz, 48 Hz and 47.95 Hz.")
    }

    @Test func namesTheKeptSizeAndSuggestsSizesAtTheScaleAskedFor() throws {
        do {
            _ = try ModeQuery(scale: 1).resolve(on: display)
            Issue.record("the panel has no 1728 × 1117 mode at 1×")
        } catch ResoluteError.modeNotFound(let query, let suggestions) {
            #expect(query == "1728 × 1117 @1x")
            #expect(!suggestions.isEmpty)
            #expect(suggestions.allSatisfy { !$0.contains("HiDPI") })
        }
    }

    @Test func describesAnyQueryWithoutTrapping() {
        #expect(ModeQuery(scale: .infinity, refreshRate: .nan).summary == "@infx")
        #expect(ModeQuery(scale: 1.5, refreshRate: 0).summary == "@1.5x")
    }

    @Test func keepsTheCurrentRefreshRate() throws {
        #expect(try ModeQuery(resolution: "1496x967").resolve(on: display).modeID == 42)
    }

    @Test func honoursAnExplicitRefreshRateAndScale() throws {
        #expect(try ModeQuery(resolution: "1496x967@60").resolve(on: display).modeID == 43)
        #expect(try ModeQuery(resolution: "3456x2234@1x@59.94").resolve(on: display).modeID == 128)
    }

    @Test func changesOnlyTheRefreshRate() throws {
        #expect(try ModeQuery(refreshRate: 60).resolve(on: display).modeID == 55)
    }

    @Test func refusesToKeepAnUnknownResolution() throws {
        let unknown = capture.display(currentModeID: 9_999)
        let expected = ResoluteError.currentModeUnknown(display: "Built-in Retina Display")
        #expect(throws: expected) { try ModeQuery(refreshRate: 60).resolve(on: unknown) }
        #expect(throws: expected) { try ModeQuery(scale: 2).resolve(on: unknown) }
        // A resolution given explicitly still works; it takes the fastest refresh rate.
        #expect(try ModeQuery(resolution: "1496x967").resolve(on: unknown).modeID == 42)
    }

    @Test func findsTheDefaultModeAndExactIDs() throws {
        let at60 = capture.display(currentModeID: 55)
        #expect(try ModeQuery(useDefault: true).resolve(on: at60).modeID == 54)
        #expect(try ModeQuery(modeID: 100).resolve(on: display).modeID == 100)
        #expect(throws: ResoluteError.modeNotFound("mode 5000", suggestions: [])) {
            try ModeQuery(modeID: 5_000).resolve(on: display)
        }
    }

    @Test func prefersTheCurrentScaleForAmbiguousSizes() throws {
        let atHiDPI = TestData.uhd(currentModeID: 12)
        #expect(try ModeQuery(resolution: "1920x1080").resolve(on: atHiDPI).modeID == 10)
        let atLowResolution = TestData.uhd(currentModeID: 22)
        #expect(try ModeQuery(resolution: "1920x1080").resolve(on: atLowResolution).modeID == 21)
        #expect(try ModeQuery(resolution: "1920x1080@2x").resolve(on: atLowResolution).modeID == 10)
    }

    @Test func suggestsNearbyResolutions() {
        let expected = ResoluteError.modeNotFound(
            "1500 × 970",
            suggestions: ["1496 × 967 (HiDPI)", "1496 × 935 (HiDPI)", "1312 × 848 (HiDPI)"]
        )
        #expect(throws: expected) {
            try ModeQuery(resolution: "1500x970").resolve(on: display)
        }
    }

    /// Sizes are in points. 2992 × 1934 is what 1496 × 967 HiDPI renders, so someone typing
    /// it most likely means that mode.
    @Test func suggestsTheHiDPIModeThatRendersAtTheSizeGiven() {
        for text in ["2992x1934@2x", "2992x1934@2x@60"] {
            do {
                _ = try ModeQuery(resolution: text).resolve(on: display)
                Issue.record("\(text) is no mode's size in points")
            } catch ResoluteError.modeNotFound(_, let suggestions) {
                #expect(suggestions.first == "1496 × 967 (HiDPI, rendered at 2992 × 1934 pixels)", "\(text)")
            } catch {
                Issue.record("\(text): \(error)")
            }
        }
    }

    @Test func asksBeforeUsingHiddenModes() throws {
        let fullHD = TestData.fullHD()
        #expect(throws: ResoluteError.hiddenModeNeedsConfirmation("2560 × 1440")) {
            try ModeQuery(resolution: "2560x1440").resolve(on: fullHD)
        }
        var query = try ModeQuery(resolution: "2560x1440")
        query.allowHidden = true
        #expect(try query.resolve(on: fullHD).modeID == 91)
        #expect(throws: ResoluteError.hiddenModeNeedsConfirmation("mode 90")) {
            try ModeQuery(modeID: 90).resolve(on: fullHD)
        }
    }
}

@Suite struct DisplaySelectorTests {
    let displays = [
        TestData.uhd(id: 3),
        TestData.fullHD(id: 2),
        Display(id: 1, name: "Built-in Retina Display", isBuiltin: true, isMain: true, currentModeID: nil, modes: []),
    ]

    @Test func parsesSelectors() {
        #expect(DisplaySelector("main") == .main)
        #expect(DisplaySelector("MAIN") == .main)
        #expect(DisplaySelector("1") == .index(1))
        #expect(DisplaySelector("id:42") == .id(42))
        #expect(DisplaySelector("dell") == .name("dell"))
    }

    @Test func resolvesEachKind() throws {
        #expect(try DisplaySelector.main.resolve(in: displays).id == 1)
        #expect(try DisplaySelector.index(0).resolve(in: displays).id == 3)
        #expect(try DisplaySelector.id(2).resolve(in: displays).id == 2)
        #expect(try DisplaySelector.name("full hd").resolve(in: displays).id == 2)
    }

    @Test func reportsMissingAndAmbiguousDisplays() {
        #expect(throws: ResoluteError.displayNotFound("7")) {
            try DisplaySelector.index(7).resolve(in: displays)
        }
        #expect(throws: ResoluteError.ambiguousDisplay("monitor", matches: ["4K Monitor", "Full HD Monitor"])) {
            try DisplaySelector.name("monitor").resolve(in: displays)
        }
        #expect(throws: ResoluteError.noDisplays) {
            try DisplaySelector.main.resolve(in: [])
        }
    }

    @Test func prefersAnExactNameOverPartialMatches() throws {
        let similar = [
            Display(id: 5, name: "LG", currentModeID: nil, modes: []),
            Display(id: 6, name: "LG UltraFine", currentModeID: nil, modes: []),
        ]
        #expect(try DisplaySelector.name("lg").resolve(in: similar).id == 5)
    }
}
