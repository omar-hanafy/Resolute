import AppKit
import SwiftUI
import Testing
@testable import ResoluteDesign

/// The shared controls: their colors, sizes and the small pieces of logic they carry,
/// laid out headlessly (nothing here orders a window in).
@MainActor
@Suite struct ControlsTests {
    /// The resolved sRGB components of `color` in `appearance`, as 0...255 values.
    private func components(_ color: NSColor, in appearance: NSAppearance.Name) -> [Int] {
        var resolved: NSColor?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        guard let resolved else { return [] }
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    private func sameColor(_ a: NSColor, _ b: NSColor) -> Bool {
        [NSAppearance.Name.aqua, .darkAqua].allSatisfy { components(a, in: $0) == components(b, in: $0) }
    }

    /// The size SwiftUI lays `view` out at when nothing constrains it.
    private func fittingSize(_ view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    // MARK: - Badge

    @Test func badgeTonesUseFigmaColors() {
        #expect(sameColor(Badge.Tone.neutral.foreground, .secondaryLabelColor))
        #expect(components(Badge.Tone.neutral.background, in: .aqua) == [0, 0, 0, 0x1A])
        #expect(components(Badge.Tone.neutral.background, in: .darkAqua) == [255, 255, 255, 0x1A])

        #expect(sameColor(Badge.Tone.accent.foreground, .controlAccentColor))
        #expect(sameColor(Badge.Tone.accent.background, NSPalette.surfaceAccentTint))

        // Darker than Figma's orange in Light, for contrast (TokensTests.warningTextIsReadable).
        #expect(sameColor(Badge.Tone.warning.foreground, NSPalette.warningText))
        #expect(components(Badge.Tone.warning.background, in: .aqua) == [0xFF, 0x8C, 0x29, 0x1F])
        #expect(components(Badge.Tone.warning.background, in: .darkAqua) == [0xFF, 0x91, 0x30, 0x29])
    }

    @Test(arguments: Badge.Tone.allCases)
    func badgeIsFigmasHeight(_ tone: Badge.Tone) {
        #expect(fittingSize(Badge("Override installed", tone: tone)).height == Metrics.Badge.height)
    }

    // MARK: - Segmented tabs

    /// Holds a selection for a binding, as a model would.
    private final class Selection<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @Test func clickingASegmentSelectsIt() {
        let selection = Selection(60)
        let tabs = SegmentedTabs(
            [.init(120, "120 Hz"), .init(60, "60 Hz"), .init(50, "50 Hz")],
            selection: Binding(get: { selection.value }, set: { selection.value = $0 }),
            size: .large
        )
        #expect(tabs.items.map { tabs.isSelected($0) } == [false, true, false])

        tabs.select(120)
        #expect(selection.value == 120)
        #expect(tabs.items.map { tabs.isSelected($0) } == [true, false, false])

        tabs.select(120)
        #expect(selection.value == 120)
    }

    @Test func segmentsKeepTheirWidthWhenSelected() {
        for title in ["Resolution", "Custom Resolutions", "Terminal & Agents", "Low Resolution (1×)"] {
            let selected = fittingSize(SegmentLabel(title: title, isSelected: true, fillsWidth: false))
            let unselected = fittingSize(SegmentLabel(title: title, isSelected: false, fillsWidth: false))
            #expect(selected == unselected, "\(title)")
            #expect(selected.height == Metrics.Segment.height)
        }
    }

    @Test func tabsAreASegmentInATrack() {
        let tabs = SegmentedTabs([.init(0, "General"), .init(1, "About")], selection: .constant(0))
        #expect(fittingSize(tabs).height == Metrics.Segment.height + 2 * Metrics.Segment.trackPadding)
    }

    /// Where the selected segment's capsule (white in Light) spans along the control's
    /// middle row, in points.
    private func selectedSpan(of tabs: some View, width: CGFloat) throws -> ClosedRange<Int> {
        let renderer = ImageRenderer(content: tabs.frame(width: width).environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let middle = bitmap.pixelsHigh / 2
        let white = (0..<bitmap.pixelsWide).filter { x in
            guard let color = bitmap.colorAt(x: x, y: middle)?.usingColorSpace(.sRGB) else { return false }
            return color.alphaComponent > 0.99 && min(color.redComponent, color.greenComponent, color.blueComponent) > 0.99
        }
        let first = try #require(white.first), last = try #require(white.last)
        return first...last
    }

    @Test func largeTabsShareTheWidthEqually() throws {
        let items: [SegmentedTabs<Int>.Item] = [.init(0, "HiDPI"), .init(1, "Low Resolution (1×)")]
        let width: CGFloat = 292
        let share = (width - 2 * Metrics.Segment.trackPadding) / 2
        let first = try selectedSpan(of: SegmentedTabs(items, selection: .constant(0), size: .large), width: width)
        let second = try selectedSpan(of: SegmentedTabs(items, selection: .constant(1), size: .large), width: width)
        #expect(abs(CGFloat(first.count) - share) <= 2, "first segment spans \(first)")
        #expect(abs(CGFloat(second.count) - share) <= 2, "second segment spans \(second)")
        #expect(abs(CGFloat(second.lowerBound) - (Metrics.Segment.trackPadding + share)) <= 2)
    }

    // MARK: - Banner

    @Test func bannerToneIcons() {
        #expect(Banner("Title", message: "Message", tone: .warning).symbol == .exclamationmarkTriangleFill)
        #expect(Banner("Title", message: "Message", tone: .info).symbol == .infoCircleFill)
        #expect(Banner("Title", message: "Message", tone: .info, symbol: .sparkles).symbol == .sparkles)
        #expect(Banner.Tone.warning.background == Palette.surfaceWarningTint)
        #expect(Banner.Tone.info.background == Palette.surfaceAccentTint)
    }

    /// Figma 17:101: 316 × 66, from a title, a one-line message and an action.
    @Test func bannerIsFigmasHeight() {
        let banner = Banner("Waiting for DELL U2723QE", message: "It went dark while trying 2880 × 1620.", tone: .warning,
                            action: .init("Stop Waiting") {})
        #expect(fittingSize(banner.frame(width: 316)).height == 66)
        let withoutAction = Banner("Waiting for DELL U2723QE", message: "It went dark while trying 2880 × 1620.", tone: .info)
        #expect(fittingSize(withoutAction.frame(width: 316)).height == 66 - 13 - Metrics.Banner.textSpacing)
    }

    /// Figma 60:547's Sharp Scaling offer: 292 × 76 with a two-line message.
    @Test func compactBannerIsFigmasHeight() {
        let offer = Banner(
            "Sharper text on this display",
            message: "Add Retina-style sizes, from Larger Text to More Space, like a 5K display.",
            tone: .info, symbol: .sparkles, size: .compact,
            action: .init("Set Up Sharp Scaling…") {}, onDismiss: {}
        )
        #expect(fittingSize(offer.frame(width: 292)).height == 76)
    }

    @Test func bannerActionsRun() {
        var stopped = false
        let action = Banner.Action("Stop Waiting") { stopped = true }
        action.perform()
        #expect(stopped)
    }

    // MARK: - Buttons

    @Test func capsuleButtonsAreFigmasSize() {
        let large = Button("Revert") {}.buttonStyle(.capsule(.primary))
        #expect(fittingSize(large.frame(width: 130)).height == Metrics.CapsuleButton.largeHeight)
        let small = Button("Apply") {}.buttonStyle(.capsule(.primary, size: .small))
        #expect(fittingSize(small).height == Metrics.CapsuleButton.smallHeight)
    }

    @Test func capsuleButtonColors() {
        let primary = CapsuleButtonStyle(.primary)
        #expect(primary.fill == Palette.accent)
        #expect(primary.foreground == Palette.labelWhite)
        let secondary = CapsuleButtonStyle(.secondary)
        #expect(secondary.fill == Palette.fillVibrantSecondary)
        #expect(secondary.foreground == Palette.labelPrimary)
        #expect(CapsuleButtonStyle(.primary, size: .large).textStyle == .bodyMedium)
        #expect(CapsuleButtonStyle(.primary, size: .small).textStyle == .calloutEmphasized)
    }

    @Test func linkIsAsTallAsItsText() {
        #expect(fittingSize(Button("Undo") {}.buttonStyle(.accentLink)).height == TextStyle.calloutEmphasized.lineHeight)
        #expect(fittingSize(Button("Stop Waiting") {}.buttonStyle(.accentLink(.footnoteEmphasized))).height == TextStyle.footnoteEmphasized.lineHeight)
    }

    // MARK: - Shortcuts

    @Test func shortcutsAreWrittenTheMacWay() {
        #expect(ShortcutLabel.text(key: "1", modifiers: [.option, .control]) == "⌃⌥1")
        #expect(ShortcutLabel.text(key: "r", modifiers: [.command, .shift, .option, .control]) == "⌃⌥⇧⌘R")
        #expect(ShortcutLabel.text(key: ",", modifiers: .command) == "⌘,")
        #expect(ShortcutLabel(key: "q", modifiers: .command).keys == "⌘Q")
    }

    @Test func shortcutsAreSpokenInWords() {
        #expect(ShortcutLabel.spokenText("⌃⌥1") == "Control-Option-1")
        #expect(ShortcutLabel.spokenText("⌘,") == "Command-Comma")
        #expect(ShortcutLabel.spokenText("⌘Q") == "Command-Q")
        #expect(ShortcutLabel.spokenText("⇧⌘↩") == "Shift-Command-Return")
        #expect(ShortcutLabel.spokenText("F5") == "F5")
    }

    @Test func shortcutChipIsFigmasHeight() {
        #expect(fittingSize(ShortcutLabel("⌃⌥1")).height == 17)
        #expect(fittingSize(ShortcutLabel("⌘,", style: .menuItem)).height == TextStyle.body.lineHeight)
    }

    // MARK: - Countdown

    @Test func countdownFractionIsTheShareLeft() {
        #expect(CountdownBar.fraction(remaining: 12, total: 15) == 0.8)
        #expect(CountdownBar(remaining: 15, total: 15).fraction == 1)
        #expect(CountdownBar(remaining: 0, total: 15).fraction == 0)
    }

    @Test func countdownFractionIsClamped() {
        #expect(CountdownBar.fraction(remaining: 20, total: 15) == 1)
        #expect(CountdownBar.fraction(remaining: -3, total: 15) == 0)
        #expect(CountdownBar.fraction(remaining: 5, total: 0) == 0)
        #expect(CountdownBar.fraction(remaining: 5, total: -1) == 0)
        #expect(CountdownBar.fraction(remaining: .nan, total: 15) == 0)
        #expect(CountdownBar.fraction(remaining: 5, total: .infinity) == 0)
        #expect(CountdownBar(fraction: 1.5).fraction == 1)
        #expect(CountdownBar(fraction: -0.2).fraction == 0)
        #expect(CountdownBar(fraction: .nan).fraction == 0)
    }

    @Test func countdownReadsTheSecondsLeft() {
        #expect(CountdownBar(remaining: 12, total: 15).accessibilityValue == "12 seconds")
        #expect(CountdownBar(remaining: 0.2, total: 15).accessibilityValue == "1 second")
        #expect(CountdownBar(remaining: -1, total: 15).accessibilityValue == "0 seconds")
        #expect(CountdownBar(fraction: 0.75).accessibilityValue == "75 percent")
    }

    @Test func countdownIsFigmasHeight() {
        #expect(fittingSize(CountdownBar(fraction: 0.75).frame(width: 268)).height == Metrics.Countdown.height)
    }

    // MARK: - HUD, section label, divider

    @Test func hudIsFigmasSize() {
        let card = HUDCard("Switched back", subtitle: "DELL U2723QE · 2560 × 1440", symbol: .arrowUturnBackward)
        #expect(fittingSize(card) == Metrics.HUD.size)
        #expect(HUDCard.Tone.neutral.symbolColor == Palette.labelPrimary)
        #expect(HUDCard.Tone.positive.symbolColor == Palette.green)
    }

    @Test func sectionLabelStyles() {
        #expect(SectionLabel("Presets").style == .panel)
        #expect(fittingSize(SectionLabel("Presets")).height == TextStyle.subheadlineEmphasized.lineHeight)
        #expect(SectionLabel("Startup", style: .form).style == .form)
    }

    @Test func dividerIsOnePointThick() {
        #expect(fittingSize(HairlineDivider().frame(width: 100)).height == Metrics.Group.dividerThickness)
        #expect(fittingSize(HairlineDivider(.vertical).frame(height: 20)).width == Metrics.Group.dividerThickness)
    }

    // MARK: - Spoken text

    @Test func sizesAreSpokenWithBy() {
        #expect(SpokenText.sizes("DELL U2723QE · 2560 × 1440") == "DELL U2723QE, 2560 by 1440")
        #expect(SpokenText.sizes("1920×1080") == "1920 by 1080")
        #expect(SpokenText.sizes("Low Resolution (1×)") == "Low Resolution (1x)")
        #expect(SpokenText.sizes("Presets") == "Presets")
    }
}
