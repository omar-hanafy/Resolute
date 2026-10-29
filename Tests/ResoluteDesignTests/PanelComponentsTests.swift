import AppKit
import SwiftUI
import Testing
@testable import ResoluteDesign

@MainActor
@Suite struct StatusItemImageTests {
    @Test func countdownShowsMinutesAndTwoDigitSeconds() {
        #expect(StatusItemImage.countdown(secondsLeft: 12) == "0:12")
        #expect(StatusItemImage.countdown(secondsLeft: 5) == "0:05")
        #expect(StatusItemImage.countdown(secondsLeft: 60) == "1:00")
        #expect(StatusItemImage.countdown(secondsLeft: 75) == "1:15")
        #expect(StatusItemImage.countdown(secondsLeft: -3) == "0:00")
    }

    @Test func monochromeStatesAreTemplatesAndColoredOnesAreNot() {
        #expect(StatusItemImage(.symbol).isTemplate)
        #expect(StatusItemImage(.symbol, isOpen: true).isTemplate)
        #expect(StatusItemImage(.resolution("1728 × 1117")).isTemplate)
        #expect(!StatusItemImage(.trial(secondsLeft: 12)).isTemplate)
        #expect(!StatusItemImage(.waiting).isTemplate)
        for state in [StatusItemImage(.symbol), StatusItemImage(.trial(secondsLeft: 12)), StatusItemImage(.waiting)] {
            #expect(state.nsImage().isTemplate == state.isTemplate)
        }
    }

    @Test func sizesFollowFigma() {
        // Figma 17:135: Normal 32 × 24, Waiting 49 × 24; text adds a 5-point gap and its width.
        #expect(StatusItemImage(.symbol).size == CGSize(width: 32, height: 24))
        #expect(StatusItemImage(.symbol, isOpen: true).size == CGSize(width: 32, height: 24))
        #expect(StatusItemImage(.waiting).size == CGSize(width: 49, height: 24))
        let trial = StatusItemImage(.trial(secondsLeft: 12)).size
        let resolution = StatusItemImage(.resolution("1728 × 1117")).size
        #expect(trial.height == 24 && resolution.height == 24)
        #expect(trial.width > 32 + 5 && trial.width < 80)
        #expect(resolution.width > trial.width && resolution.width < 120)
        #expect(StatusItemImage(.symbol, height: 22).size.height == 22)
    }

    @Test func countdownKeepsItsWidthAsItTicks() {
        let widths = Set((0...15).map { StatusItemImage(.trial(secondsLeft: $0)).size.width })
        #expect(widths.count == 1)
    }

    @Test func imageIsDrawnAtItsSize() throws {
        let item = StatusItemImage(.resolution("1728 × 1117"))
        let image = item.nsImage()
        #expect(image.size == item.size)
        #expect(image.accessibilityDescription == "Resolute, 1728 by 1117")
        let pixels = try #require(Pixels(image, appearance: .darkAqua))
        // The symbol is drawn opaque in its 18-point box after the 7-point padding, and the
        // padding stays clear.
        #expect(pixels.maxAlpha(x: 7..<25, y: 3..<21) > 0.9)
        #expect(pixels.maxAlpha(x: 0..<6, y: 0..<24) == 0)
        // The display symbol is an outline: its screen stays clear.
        #expect(pixels.alpha(atX: 16, y: 13) == 0)
    }

    @Test func trialIsAnOrangeCapsule() throws {
        let pixels = try #require(Pixels(StatusItemImage(.trial(secondsLeft: 12)).nsImage(), appearance: .darkAqua))
        let middleOfPadding = pixels.color(atX: 3, y: 12)
        #expect(middleOfPadding.alpha == 1)
        #expect(middleOfPadding.red > 0.9 && middleOfPadding.green > 0.45 && middleOfPadding.green < 0.7 && middleOfPadding.blue < 0.3)
        // The capsule is round: its corner is clear.
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        // The symbol's screen shows the orange through its outline.
        let screen = pixels.color(atX: 16, y: 13)
        #expect(screen.red > 0.9 && screen.blue < 0.3)
    }

    @Test func openDrawsFigmasCapsuleBehindTheSymbol() throws {
        let closed = try #require(Pixels(StatusItemImage(.symbol).nsImage(), appearance: .darkAqua))
        let open = try #require(Pixels(StatusItemImage(.symbol, isOpen: true).nsImage(), appearance: .darkAqua))
        #expect(closed.alpha(atX: 3, y: 12) == 0)
        #expect(abs(open.alpha(atX: 3, y: 12) - 0.26) < 0.03)
    }

    @Test func waitingAddsAnOrangeHourglass() throws {
        let pixels = try #require(Pixels(StatusItemImage(.waiting).nsImage(), appearance: .darkAqua))
        // Somewhere in the hourglass's 12-point box, right of the symbol, is orange.
        let box = (30..<42).flatMap { x in (6..<18).map { y in pixels.color(atX: x, y: y) } }
        #expect(box.contains { $0.alpha > 0.5 && $0.red > 0.9 && $0.blue < 0.3 })
    }

    @Test func accessibilityDescriptionsSayWhatTheItemShows() {
        #expect(StatusItemImage(.symbol).accessibilityDescription == "Resolute")
        #expect(StatusItemImage(.trial(secondsLeft: 12)).accessibilityDescription == "Resolute, hidden mode on trial, 12 seconds left")
        #expect(StatusItemImage(.waiting).accessibilityDescription == "Resolute, a revert is waiting for its display")
    }
}

@MainActor
@Suite struct PanelComponentsTests {
    @Test func spokenTextReadsSizesWithBy() {
        #expect(PanelSpeech.text("1728 × 1117 · 120 Hz") == "1728 by 1117, 120 Hz")
        #expect(PanelSpeech.text("DELL U2723QE → 2560 × 1440") == "DELL U2723QE to 2560 by 1440")
        #expect(PanelSpeech.text("Low Resolution (1×)") == "Low Resolution (1x)")
        #expect(PanelSpeech.text("Hidden · 21:9") == "Hidden, 21:9")
    }

    @Test func choicesKnowWhichOneIsSelected() {
        let choices = ["60 Hz", "50 Hz", "30 Hz"].map { PanelChoice($0, isSelected: $0 == "50 Hz") {} }
        #expect(choices.selectedIndex == 1)
        #expect([PanelChoice("60 Hz") {}].selectedIndex == nil)
        #expect(PanelChoice("2560 × 1440") {}.spokenLabel == "2560 by 1440")
        #expect(PanelChoice("Coding", accessibilityLabel: "Coding preset") {}.spokenLabel == "Coding preset")
    }

    @Test func choosingFromAPopUpRunsThatChoice() {
        var chosen: [String] = []
        let choices = ["60 Hz", "50 Hz", "30 Hz"].map { title in
            PanelChoice(title, isSelected: title == "60 Hz") { chosen.append(title) }
        }
        let popUp = PanelPopUp(title: "Refresh Rate", choices: choices)
        #expect(popUp.selection.wrappedValue == 0)
        popUp.selection.wrappedValue = 2
        popUp.selection.wrappedValue = nil
        popUp.selection.wrappedValue = 7
        #expect(chosen == ["30 Hz"])
    }

    @Test func presetsThatDontFitWrapToAnotherLine() {
        let three = fittingSize(PresetsRow(["Coding", "Presenting", "Gaming"].map { PanelChoice($0) {} }) {})
        let many = fittingSize(PresetsRow((1...9).map { PanelChoice("Preset \($0)") {} }) {})
        #expect(many.width == three.width)
        // The label, then at least two lines of 23-point chips 6 points apart.
        #expect(many.height >= 28 + 23 + 6 + 23)
    }

    @Test func stopsSpreadOverTheFiveDrawings() {
        #expect(StopStrip.thumbnailStops(count: 5) == [1, 2, 3, 4, 5])
        #expect(StopStrip.thumbnailStops(count: 3) == [1, 3, 5])
        #expect(StopStrip.thumbnailStops(count: 4) == [1, 2, 4, 5])
        #expect(StopStrip.thumbnailStops(count: 2) == [1, 5])
        #expect(StopStrip.thumbnailStops(count: 1) == [3])
        #expect(StopStrip.thumbnailStops(count: 0).isEmpty)
    }

    @Test func modeOutlineShowsTheAspectRatio() {
        #expect(ModeRow.outlineSize(aspectRatio: nil) == CGSize(width: 18, height: 11))
        let wide = ModeRow.outlineSize(aspectRatio: 16.0 / 9)
        #expect(wide.width == 18 && abs(wide.height - 10.125) < 0.001)
        let ultrawide = ModeRow.outlineSize(aspectRatio: 64.0 / 27)
        #expect(ultrawide.width == 18 && ultrawide.height < 8)
        let square = ModeRow.outlineSize(aspectRatio: 4.0 / 3)
        #expect(square.height == 11 && abs(square.width - 44.0 / 3) < 0.001)
    }

    @Test func modeRowReadsItsSizeTagAndTrial() {
        #expect(ModeRow("2560 × 1080", tag: "Hidden · 21:9", isHidden: true) {}.accessibilityLabel == "2560 by 1080, Hidden, 21:9, Try…")
        #expect(ModeRow("1920 × 1080", tag: "Default", isSelected: true) {}.accessibilityLabel == "1920 by 1080, Default")
    }

    @Test func displayCardHeaderReadsNameModeAndBadge() {
        let card = DisplayCard(
            name: "Built-in Retina Display", summary: "1728 × 1117 · 120 Hz", picture: .macBookPro, badge: Badge("Default"),
            sizes: .resolutions([]), refreshRates: [], resolutionCount: 22, openDisplay: {}, showAllResolutions: {}
        )
        #expect(card.headerLabel == "Built-in Retina Display, 1728 by 1117, 120 Hz, Default")
    }

    // MARK: Figma geometry

    @Test func rowsAreTwentySixPointsHigh() {
        #expect(fittingSize(PanelRow("Settings…", symbol: .gearshape, trailing: .shortcut("⌘,")) {}).height == 26)
        #expect(fittingSize(PanelRow("Mirror Displays", symbol: .rectangleOnRectangle, isOn: .constant(false))).height == 26)
        #expect(fittingSize(ModeRow("2560 × 1440", isSelected: true) {}).height == 26)
    }

    @Test func panelPiecesMatchFigmasHeights() {
        expectHeight(of: PanelHeader {}, 30)
        expectHeight(of: ActivityRow(title: "DELL U2723QE → 2560 × 1440", detail: "From Terminal · 2 min ago") {}, 43)
        expectHeight(of: PresetsRow(["Coding", "Presenting", "Gaming"].map { PanelChoice($0) {} }) {}, 54)
        expectHeight(of: PanelSegments(["120 Hz", "60 Hz"].map { PanelChoice($0) {} }), 25)
        expectHeight(of: PresetChip("Coding", symbol: .star) {}, 23)
        expectHeight(of: AllResolutionsHeader(name: "DELL U2723QE", picture: .display) {}, 26)
        // Figma's message wraps to two lines in Inter; this one wraps to two in SF Pro too.
        expectHeight(
            of: WaitingBanner(
                title: "Waiting for DELL U2723QE",
                message: "It went dark while trying 2880 × 1620. Resolute switches it back when it reconnects."
            ) {},
            79
        )
    }

    @Test func retinaCardIsTwoHundredPointsHigh() {
        expectHeight(of: retinaCard(refreshRates: ["120 Hz", "60 Hz", "50 Hz", "48 Hz"]), 200)
        // Without refresh rates the card ends 8 points under All Resolutions: 10 + 36 + 10 +
        // 34.3 (the stops, which layout rounds to the pixel) + 10 + 13 (their caption) + 10 +
        // 26 + 8.
        expectHeight(of: retinaCard(refreshRates: []), 157.3, tolerance: 1)
    }

    private func retinaCard(refreshRates: [String]) -> some View {
        let stops = ["1168 × 755", "1312 × 848", "1496 × 967", "1728 × 1117", "2056 × 1329"].map { PanelChoice($0) {} }
        return DisplayCard(
            name: "Built-in Retina Display", summary: "1728 × 1117 · 120 Hz", picture: .macBookPro, badge: Badge("Default"),
            sizes: .stops(StopStrip(stops, caption: "1728 × 1117 · Default", tone: .violet)),
            refreshRates: refreshRates.map { PanelChoice($0) {} },
            resolutionCount: 22, openDisplay: {}, showAllResolutions: {}
        )
    }

    @Test func standardCardMatchesFigma() {
        let choices = ["2560 × 1440 · Native", "1920 × 1080"].map { PanelChoice($0, isSelected: $0.hasSuffix("Native")) {} }
        let card = DisplayCard(
            name: "ASUS PA278QV", summary: "2560 × 1440 · 75 Hz", picture: .display, badge: Badge("Standard"),
            sizes: .resolutions(choices), refreshRates: ["75 Hz", "60 Hz", "50 Hz"].map { PanelChoice($0) {} },
            resolutionCount: 14, openDisplay: {}, showAllResolutions: {}
        ) {
            PanelOffer(
                title: "Sharper text on this display",
                message: "Add Retina-style sizes, from Larger Text to More Space, like a 5K display.",
                actionTitle: "Set Up Sharp Scaling…", action: {}, dismiss: {}
            )
        }
        expectHeight(of: card, 245)
        expectHeight(of: PanelPopUpRow("Refresh Rate", symbol: .arrowTriangle2Circlepath, choices: choices), 30)
    }

    @Test func panelIsThreeHundredFortyPointsWide() {
        // 10 points above and below a 30-point header.
        #expect(NSHostingView(rootView: PanelSurface { PanelHeader {} }).fittingSize == CGSize(width: 340, height: 50))
    }

    /// The view's size at the width of the panel's content.
    private func fittingSize(_ view: some View) -> CGSize {
        NSHostingView(rootView: view.frame(width: Metrics.Panel.width - 2 * Metrics.Panel.padding)).fittingSize
    }

    private func expectHeight(
        of view: some View,
        _ height: CGFloat,
        tolerance: CGFloat = 0.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let size = fittingSize(view)
        #expect(abs(size.height - height) < tolerance, "Height \(size.height), Figma \(height)", sourceLocation: sourceLocation)
    }
}

/// An image's pixels, drawn at 1× in an appearance, read with the origin at the bottom left.
@MainActor
private struct Pixels {
    let rep: NSBitmapImageRep

    init?(_ image: NSImage, appearance: NSAppearance.Name) {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
        }
        self.rep = rep
    }

    func color(atX x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)?.usingColorSpace(.sRGB) ?? .clear
        let alpha = color.alphaComponent
        // Unpremultiplied components, so a translucent pixel still reads as its color.
        return alpha == 0 ? (0, 0, 0, 0) : (color.redComponent, color.greenComponent, color.blueComponent, alpha)
    }

    func alpha(atX x: Int, y: Int) -> CGFloat {
        color(atX: x, y: y).alpha
    }

    func maxAlpha(x: Range<Int>, y: Range<Int>) -> CGFloat {
        x.flatMap { x in y.map { alpha(atX: x, y: $0) } }.max() ?? 0
    }
}
