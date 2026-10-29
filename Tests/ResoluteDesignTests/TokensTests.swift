import AppKit
import SwiftUI
import Testing
@testable import ResoluteDesign

@MainActor
@Suite struct TokensTests {
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

    /// A Resolute color with Figma's Light and Dark values as RGBA bytes.
    struct Expected: Sendable, CustomTestStringConvertible {
        var name: String
        var color: @Sendable () -> NSColor
        var light: [Int]
        var dark: [Int]

        var testDescription: String { name }
    }

    nonisolated static let figma: [Expected] = [
        Expected(name: "surface/card", color: { NSPalette.surfaceCard }, light: [255, 255, 255, 0x99], dark: [255, 255, 255, 0x12]),
        Expected(name: "surface/selected-control", color: { NSPalette.surfaceSelectedControl }, light: [255, 255, 255, 0xFF], dark: [255, 255, 255, 0x3D]),
        Expected(name: "surface/track", color: { NSPalette.surfaceTrack }, light: [0, 0, 0, 0x0F], dark: [255, 255, 255, 0x14]),
        Expected(name: "surface/row-hover", color: { NSPalette.surfaceRowHover }, light: [0, 0, 0, 0x0D], dark: [255, 255, 255, 0x0F]),
        Expected(name: "surface/sidebar-selection", color: { NSPalette.surfaceSidebarSelection }, light: [0, 0, 0, 0x14], dark: [255, 255, 255, 0x1A]),
        Expected(name: "surface/group", color: { NSPalette.surfaceGroup }, light: [0, 0, 0, 0x08], dark: [255, 255, 255, 0x0A]),
        Expected(name: "surface/warning-tint", color: { NSPalette.surfaceWarningTint }, light: [0xFF, 0x8C, 0x29, 0x1F], dark: [0xFF, 0x91, 0x30, 0x29]),
        Expected(name: "stroke/hairline", color: { NSPalette.strokeHairline }, light: [0, 0, 0, 0x1A], dark: [255, 255, 255, 0x1A]),
        Expected(name: "stroke/window-edge", color: { NSPalette.strokeWindowEdge }, light: [0, 0, 0, 0x26], dark: [255, 255, 255, 0x24]),
        Expected(name: "Fills - Opaque/Primary", color: { NSPalette.fillPrimary }, light: [0, 0, 0, 0x1A], dark: [255, 255, 255, 0x1A]),
        Expected(name: "Fills - Opaque/Secondary", color: { NSPalette.fillSecondary }, light: [0, 0, 0, 0x14], dark: [255, 255, 255, 0x14]),
        // Figma blends #E6E6E6 plus-darker and #141414 plus-lighter; these are the alphas
        // that match over the trial dialog's glass.
        Expected(name: "Fills - Vibrant/Secondary", color: { NSPalette.fillVibrantSecondary }, light: [0, 0, 0, 0x1A], dark: [255, 255, 255, 0x16]),
        // Labels/Primary at 10%, as the kit's progress bar draws its track.
        Expected(name: "progress track", color: { NSPalette.progressTrack }, light: [0, 0, 0, 0x16], dark: [255, 255, 255, 0x16]),
        Expected(name: "Progress Bars/Track - Stroke", color: { NSPalette.progressTrackStroke }, light: [0, 0, 0, 0x12], dark: [255, 255, 255, 0x0A]),
        Expected(name: "selected segment shadow", color: { NSPalette.shadowSelectedControl }, light: [0, 0, 0, 0x2E], dark: [0, 0, 0, 0x2E]),
    ]

    @Test(arguments: figma)
    func surfacesMatchFigma(_ expected: Expected) {
        #expect(components(expected.color(), in: .aqua) == expected.light)
        #expect(components(expected.color(), in: .darkAqua) == expected.dark)
    }

    /// Orange text reads at 4.5:1 or more, in Light on the window and on the warning tint
    /// over it, and in Dark on the window.
    @Test func warningTextIsReadable() {
        func luminance(_ rgb: [Int]) -> Double {
            let linear = rgb.prefix(3).map { value -> Double in
                let channel = Double(value) / 255
                return channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        func over(_ top: [Int], _ bottom: [Int]) -> [Int] {
            let alpha = Double(top[3]) / 255
            return (0..<3).map { Int((Double(top[$0]) * alpha + Double(bottom[$0]) * (1 - alpha)).rounded()) } + [255]
        }
        func contrast(_ text: [Int], on background: [Int]) -> Double {
            let (lighter, darker) = (max(luminance(text), luminance(background)), min(luminance(text), luminance(background)))
            return (lighter + 0.05) / (darker + 0.05)
        }
        let lightWindow = components(.windowBackgroundColor, in: .aqua)
        let lightText = components(NSPalette.warningText, in: .aqua)
        #expect(contrast(lightText, on: lightWindow) >= 4.5)
        #expect(contrast(lightText, on: over(components(NSPalette.surfaceWarningTint, in: .aqua), lightWindow)) >= 4.5)
        #expect(contrast(components(NSPalette.warningText, in: .darkAqua), on: components(.windowBackgroundColor, in: .darkAqua)) >= 4.5)
    }

    @Test func accentTintFollowsTheAccentAtFigmasOpacity() {
        for (appearance, alpha) in [(NSAppearance.Name.aqua, 0x1F), (.darkAqua, 0x33)] {
            let tint = components(NSPalette.surfaceAccentTint, in: appearance)
            let accent = components(.controlAccentColor, in: appearance)
            #expect(Array(tint.prefix(3)) == Array(accent.prefix(3)))
            #expect(tint.last == alpha)
        }
    }

    @Test func everySymbolExists() {
        let missing = Symbol.allCases.filter { $0.nsImage() == nil }
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing.map(\.name))")
    }

    @Test func symbolsAreSizedLikeFigmasIcons() {
        #expect(Symbol.pointSize(inFrame: 18) == 13)
        #expect(abs(Symbol.pointSize(inFrame: 16) - 11.56) < 0.01)
        #expect(abs(Symbol.pointSize(inFrame: 48) - 34.67) < 0.01)
        #expect(NSHostingView(rootView: SymbolIcon(.sparkles, size: 16)).fittingSize == CGSize(width: 16, height: 16))
    }

    /// Figma's `macOS/*` styles: point size, weight and line height.
    static let typeScale: [TextStyle: (size: CGFloat, weight: Font.Weight, lineHeight: CGFloat)] = [
        .largeTitle: (26, .bold, 32), .title1: (22, .bold, 26), .title2: (17, .semibold, 22), .title3: (15, .semibold, 20),
        .headline: (13, .bold, 16), .body: (13, .regular, 16), .bodyMedium: (13, .medium, 16), .bodyEmphasized: (13, .semibold, 16),
        .callout: (12, .regular, 15), .calloutEmphasized: (12, .semibold, 15),
        .subheadline: (11, .regular, 14), .subheadlineEmphasized: (11, .semibold, 14),
        .footnote: (10, .regular, 13), .footnoteEmphasized: (10, .semibold, 13), .caption: (10, .medium, 13),
        .mono: (12, .regular, 18),
    ]

    @Test(arguments: TextStyle.allCases)
    func typeScaleMatchesFigma(_ style: TextStyle) throws {
        let figma = try #require(Self.typeScale[style])
        #expect(style.pointSize == figma.size)
        #expect(style.weight == figma.weight)
        #expect(style.lineHeight == figma.lineHeight)
        #expect(style.nsFont.isFixedPitch == (style == .mono))
    }

    /// A text box is a whole number of Figma lines, as in Figma; where the font's own line
    /// is taller than Figma's, a whole number of those.
    @Test(arguments: TextStyle.allCases)
    func textBoxesAreWholeLines(_ style: TextStyle) {
        let pitch = max(style.lineHeight, style.naturalLineHeight)
        let one = NSHostingView(rootView: Text("Built-in").textBox(style).fixedSize()).fittingSize.height
        let three = NSHostingView(rootView: Text("Built-in\nRetina\nDisplay").textBox(style).fixedSize()).fittingSize.height
        #expect(abs(one - pitch) < 0.01, "one line is \(one)")
        #expect(abs(three - 3 * pitch) < 0.01, "three lines are \(three)")
        #expect(style.lineSpacing >= 0)
    }

    /// The tokens written as Figma's Metrics note (48:1022) read exactly like it.
    @Test func metricsMatchFigmasNote() {
        #expect(FoundationsText.metricsLines == [
            "Menu bar: 34 high (macOS 27 kit), status item 24 high",
            "Panel: 340 wide, 12 padding, 22 corner radius, 8 between sections",
            "Display card: 14 radius, 12 padding; thumbnails 54 × 35, 6 apart",
            "Panel rows: 26 high, 8 radius, 16 symbol, 13 text",
            "Window: 1040 × 720 default, 240 sidebar, 28 content padding",
            "Groups: 12 radius, 44 row height, 1 px dividers",
            "Trial dialog: 300 wide, centered on the display being tried",
        ])
    }

    /// The controls' sizes, from their Figma nodes.
    @Test func controlMetricsMatchFigma() {
        #expect(Metrics.Badge.height == 15 && Metrics.Badge.horizontalPadding == 6)  // 17:15
        #expect(Metrics.Segment.height == 21 && Metrics.Segment.horizontalPadding == 10 && Metrics.Segment.trackPadding == 2)  // 17:20
        #expect(Metrics.Banner.cornerRadius == 12 && Metrics.Banner.iconSize == 16 && Metrics.Banner.iconSpacing == 9)  // 17:115
        #expect([Metrics.Banner.topPadding, Metrics.Banner.leadingPadding, Metrics.Banner.bottomPadding, Metrics.Banner.trailingPadding] == [9, 10, 10, 12])
        #expect(Metrics.Banner.Compact.cornerRadius == 10 && Metrics.Banner.Compact.trailingPadding == 8)  // 59:720
        #expect(Metrics.CapsuleButton.largeHeight == 32 && Metrics.CapsuleButton.largeSpacing == 8)  // 28:64
        #expect(Metrics.CapsuleButton.smallHeight == 23 && Metrics.CapsuleButton.smallHorizontalPadding == 12)  // 36:463
        #expect(Metrics.ShortcutChip.cornerRadius == 6 && Metrics.ShortcutChip.horizontalPadding == 7)  // 36:471
        #expect(Metrics.Countdown.height == 10)  // 28:35
        #expect(Metrics.HUD.size == CGSize(width: 220, height: 190) && Metrics.HUD.spacing == 8)  // 29:70
        #expect(Metrics.Trial.cornerRadius == 34)  // 28:58
    }

    // MARK: - Glass

    private func style(
        _ kind: GlassBackground.Kind = .panel,
        cornerRadius: CGFloat = 22,
        blending: GlassBackground.Blending = .behindWindow,
        material: GlassBackground.Material
    ) -> GlassBackground.Style {
        GlassBackground.Style(kind: kind, cornerRadius: cornerRadius, blending: blending, material: material)
    }

    @Test func glassIsLiquidGlassWhereTheMacHasIt() throws {
        let host = GlassHostView()
        host.show(style(material: .automatic))
        #expect(host.subviews.count == 1)
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = try #require(host.effectView as? NSGlassEffectView)
            #expect(glass.cornerRadius == 22)
            return
        }
        #endif
        #expect(host.effectView is NSVisualEffectView)
    }

    @Test(arguments: [GlassBackground.Blending.behindWindow, .withinWindow])
    func visualEffectBlendsAsAsked(_ blending: GlassBackground.Blending) throws {
        let host = GlassHostView()
        host.show(style(.hud, cornerRadius: 22, blending: blending, material: .visualEffect))
        let effect = try #require(host.effectView as? NSVisualEffectView)
        #expect(effect.blendingMode == (blending == .withinWindow ? .withinWindow : .behindWindow))
        #expect(effect.state == .active)
        #expect(effect.layer?.cornerRadius == 22)
        #expect(effect.layer?.cornerCurve == .continuous)
    }

    @Test func eachKindHasItsMaterialBeforeLiquidGlass() {
        #expect(style(.panel, material: .visualEffect).visualEffectMaterial == .popover)
        #expect(style(.alert, material: .visualEffect).visualEffectMaterial == .hudWindow)
        #expect(style(.hud, material: .visualEffect).visualEffectMaterial == .hudWindow)
    }

    @Test func glassKeepsOrSwapsItsEffectView() throws {
        let host = GlassHostView()
        host.show(style(material: .visualEffect))
        let first = try #require(host.effectView)
        host.show(style(cornerRadius: 14, material: .visualEffect))
        #expect(host.effectView === first)
        #expect(first.layer?.cornerRadius == 14)

        host.show(style(material: .automatic))
        #expect(host.subviews.count == 1)
        if GlassBackground.drawsLiquidGlass {
            #expect(host.effectView !== first)
            #expect(first.superview == nil)
        }
    }

    @Test func glassBlendsBehindTheWindowUnlessToldOtherwise() {
        #expect(EnvironmentValues().glassBlending == .behindWindow)
        #expect(EnvironmentValues().glassMaterial == .automatic)
    }

    // MARK: - Wallpaper

    /// The average luminance of the wallpaper stand-in drawn in `scheme`, and whether it
    /// covers its whole frame.
    private func wallpaper(_ scheme: ColorScheme) throws -> (luminance: CGFloat, opaque: Bool) {
        let renderer = ImageRenderer(content: WallpaperBackdrop().frame(width: 151, height: 120).environment(\.colorScheme, scheme))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var total: CGFloat = 0
        var count: CGFloat = 0
        var opaque = true
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                total += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                count += 1
                opaque = opaque && color.alphaComponent > 0.99
            }
        }
        return (total / max(count, 1), opaque)
    }

    @Test func wallpaperFillsItsFrameInEachAppearance() throws {
        let light = try wallpaper(.light)
        let dark = try wallpaper(.dark)
        #expect(light.opaque && dark.opaque)
        #expect(dark.luminance < 0.3, "dark wallpaper luminance \(dark.luminance)")
        #expect(light.luminance > dark.luminance + 0.25, "light \(light.luminance), dark \(dark.luminance)")
    }

    // MARK: - Catalog

    @Test func catalogIDsAreUnique() {
        let ids = DesignCatalog.scenes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func foundationsAndControlsScenesAreNamedForTheirOwner() {
        #expect(DesignCatalog.foundations.allSatisfy { $0.id.hasPrefix("ds.foundations.") })
        #expect(DesignCatalog.controls.allSatisfy { $0.id.hasPrefix("ds.controls.") })
        let unmapped = DesignCatalog.controls.filter { $0.figmaNode == nil }.map(\.id)
        #expect(unmapped.isEmpty, "Control scenes without a Figma node: \(unmapped)")
    }
}
