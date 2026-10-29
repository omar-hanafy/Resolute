import SwiftUI

extension DesignCatalog {
    /// Scenes owned by the foundations owner (tokens, materials).
    @MainActor static var foundations: [CatalogScene] {
        [
            CatalogScene(id: "ds.foundations.palette", title: "Colors (Light 48:594, Dark 48:659)", figmaNode: "48:594", backdrop: .none) {
                ColorSheet(title: nil, swatches: ColorSheet.figma)
            },
            CatalogScene(id: "ds.foundations.palette.added", title: "Colors the components add", backdrop: .none) {
                ColorSheet(title: "added for components", swatches: ColorSheet.added)
            },
            CatalogScene(id: "ds.foundations.type-scale", title: "Type scale", figmaNode: "48:546", padding: 20) {
                TypeScaleSheet()
            },
            CatalogScene(id: "ds.foundations.icons", title: "SF Symbols", figmaNode: "48:725") {
                IconSheet()
            },
            CatalogScene(id: "ds.foundations.metrics", title: "Metrics", figmaNode: "48:1022", padding: 20) {
                MetricsSheet()
            },
            CatalogScene(
                id: "ds.foundations.wallpaper", title: "Desktop wallpaper stand-in (Light 5:2500, Dark 5:2499)",
                figmaNode: "5:2500", size: CGSize(width: 756, height: 491), backdrop: .none
            ) {
                WallpaperBackdrop()
            },
            glassScene(.panel, id: "ds.foundations.glass.panel", node: "20:157", size: CGSize(width: Metrics.Panel.width, height: 220), cornerRadius: Metrics.Panel.cornerRadius),
            glassScene(.alert, id: "ds.foundations.glass.alert", node: "28:58", size: CGSize(width: Metrics.Trial.width, height: 275), cornerRadius: Metrics.Trial.cornerRadius),
            glassScene(.hud, id: "ds.foundations.glass.hud", node: "29:71", size: Metrics.HUD.size, cornerRadius: Metrics.HUD.cornerRadius),
            glassScene(.panel, id: "ds.foundations.glass.panel.before-26", node: nil, size: CGSize(width: Metrics.Panel.width, height: 220), cornerRadius: Metrics.Panel.cornerRadius, material: .visualEffect),
            glassScene(.hud, id: "ds.foundations.glass.hud.before-26", node: nil, size: Metrics.HUD.size, cornerRadius: Metrics.HUD.cornerRadius, material: .visualEffect),
        ]
    }

    /// One kind of glass over the wallpaper, blending within the window so the capture
    /// shows what the glass does to what is behind it.
    @MainActor private static func glassScene(
        _ kind: GlassBackground.Kind,
        id: String,
        node: String?,
        size: CGSize,
        cornerRadius: CGFloat,
        material: GlassBackground.Material = .automatic
    ) -> CatalogScene {
        let before26 = material == .visualEffect
        let drawnWith = GlassBackground.Style(kind: kind, cornerRadius: cornerRadius, blending: .withinWindow, material: material)
            .usesLiquidGlass ? " · Liquid Glass" : " · visual effect"
        return CatalogScene(
            id: id,
            title: "Glass: \(kind.catalogName)" + (before26 ? ", as macOS 14 and 15 draw it" : ""),
            figmaNode: node,
            size: CGSize(width: size.width + 80, height: size.height + 80),
            backdrop: .wallpaper
        ) {
            VStack(alignment: .leading, spacing: Metrics.Spacing.xSmall) {
                Text(verbatim: kind.catalogName + drawnWith).textBox(.headline)
                    .foregroundStyle(Palette.labelPrimary)
                Text("Labels/Secondary on the material").textBox(.callout)
                    .foregroundStyle(Palette.labelSecondary)
            }
            .padding(Metrics.Spacing.xLarge)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .glassBackground(kind, cornerRadius: cornerRadius)
            .environment(\.glassMaterial, material)
            .glassBlending(.withinWindow)
        }
    }
}

/// A Figma color sheet: a swatch and a name for each color, on the window background.
private struct ColorSheet: View {
    struct Swatch {
        var name: String
        var color: Color
        /// Strokes are drawn as a 2-point outline, as Figma shows them.
        var isStroke = false
    }

    var title: String?
    var swatches: [Swatch]
    @Environment(\.colorScheme) private var colorScheme

    static let figma: [Swatch] = [
        Swatch(name: "Labels/Primary (kit)", color: Palette.labelPrimary),
        Swatch(name: "Labels/Secondary (kit)", color: Palette.labelSecondary),
        Swatch(name: "Labels/Tertiary (kit)", color: Palette.labelTertiary),
        Swatch(name: "Labels/Quaternary (kit)", color: Palette.labelQuaternary),
        Swatch(name: "Fills/Primary (kit)", color: Palette.fillPrimary),
        Swatch(name: "Fills/Secondary (kit)", color: Palette.fillSecondary),
        Swatch(name: "Accents/Blue (kit)", color: Palette.blue),
        Swatch(name: "Accents/Orange (kit)", color: Palette.orange),
        Swatch(name: "Accents/Green (kit)", color: Palette.green),
        Swatch(name: "Accents/Red (kit)", color: Palette.red),
        Swatch(name: "Window Background (kit)", color: Palette.windowBackground),
        Swatch(name: "surface/card (Resolute)", color: Palette.surfaceCard),
        Swatch(name: "surface/selected-control (Resolute)", color: Palette.surfaceSelectedControl),
        Swatch(name: "surface/track (Resolute)", color: Palette.surfaceTrack),
        Swatch(name: "surface/row-hover (Resolute)", color: Palette.surfaceRowHover),
        Swatch(name: "surface/sidebar-selection (Resolute)", color: Palette.surfaceSidebarSelection),
        Swatch(name: "surface/group (Resolute)", color: Palette.surfaceGroup),
        Swatch(name: "surface/warning-tint (Resolute)", color: Palette.surfaceWarningTint),
        Swatch(name: "warning text (Resolute)", color: Palette.warningText),
        Swatch(name: "surface/accent-tint (Resolute)", color: Palette.surfaceAccentTint),
        Swatch(name: "stroke/hairline (Resolute)", color: Palette.strokeHairline, isStroke: true),
        Swatch(name: "stroke/window-edge (Resolute)", color: Palette.strokeWindowEdge, isStroke: true),
    ]

    static let added: [Swatch] = [
        Swatch(name: "Accent (the person's accent color)", color: Palette.accent),
        Swatch(name: "Labels/White (kit)", color: Palette.labelWhite),
        Swatch(name: "Fills - Vibrant/Secondary (kit)", color: Palette.fillVibrantSecondary),
        Swatch(name: "Progress track (kit)", color: Palette.progressTrack),
        Swatch(name: "Progress Bars/Track - Stroke (kit)", color: Palette.progressTrackStroke, isStroke: true),
        Swatch(name: "Selected segment shadow", color: Palette.shadowSelectedControl),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            Text([colorScheme == .dark ? "Dark" : "Light", title].compactMap { $0 }.joined(separator: " · "))
                .textBox(.headline)
                .foregroundStyle(Palette.labelPrimary)
            ForEach(swatches, id: \.name) { swatch in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(swatch.isStroke ? Color.clear : swatch.color)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(swatch.isStroke ? swatch.color : Palette.labelQuaternary, lineWidth: swatch.isStroke ? 2 : 1)
                        }
                        .frame(width: 28, height: 28)
                    Text(swatch.name).textBox(.callout).foregroundStyle(Palette.labelSecondary)
                }
            }
        }
        .padding(Metrics.Spacing.xxLarge)
        .frame(width: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.windowBackground))
    }
}

/// Figma's type scale: each style's name, then a sample in the style, on one baseline.
private struct TypeScaleSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type scale").textBox(.title2).foregroundStyle(Palette.labelPrimary)
            ForEach(TextStyle.allCases, id: \.self) { style in
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(style.figmaName).textBox(.subheadline).foregroundStyle(Palette.labelSecondary)
                        .frame(width: 170, alignment: .leading)
                    Text(style == .mono ? "resolute set 1496x967 -d main" : "Built-in Retina Display · 1728 × 1117 · Larger Text ↔ More Space")
                        .textBox(style)
                        .foregroundStyle(Palette.labelPrimary)
                        .fixedSize()
                }
            }
        }
        .frame(width: 967, alignment: .leading)
    }
}

/// Every symbol in `Symbol`, in Figma's icon sheet: a 24-point icon over its name.
private struct IconSheet: View {
    private let columns = Array(repeating: GridItem(.fixed(128), spacing: 12), count: 12)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Symbol.allCases, id: \.self) { symbol in
                // A long name takes two lines and spills evenly into the padding, as in
                // Figma.
                VStack(spacing: Metrics.Spacing.small) {
                    SymbolIcon(symbol, size: 24).foregroundStyle(Palette.labelPrimary)
                    Text(symbol.name)
                        .textBox(.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 116)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 128, height: 52)
                .padding(.top, 10)
                .padding(.bottom, Metrics.Spacing.medium)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.windowBackground))
            }
        }
        .frame(width: 1690, alignment: .leading)
        .padding(20)
        .background(Palette.surfaceGroup)
    }
}

/// Figma's Metrics note, written from the `Metrics` values: it reads exactly like the
/// Figma frame while the tokens match it.
private struct MetricsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            Text("Metrics").textBox(.title2).foregroundStyle(Palette.labelPrimary)
            ForEach(FoundationsText.metricsLines, id: \.self) { line in
                Text("•  " + line).textBox(.callout).foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 380, alignment: .leading)
    }
}

/// Text the foundations scenes write from the tokens.
enum FoundationsText {
    /// The lines of Figma's Metrics note (48:1022), from the `Metrics` values.
    static var metricsLines: [String] {
        func number(_ value: CGFloat) -> String { String(Int(value)) }
        return [
            "Menu bar: \(number(Metrics.MenuBar.height)) high (macOS 27 kit), status item \(number(Metrics.MenuBar.statusItemHeight)) high",
            "Panel: \(number(Metrics.Panel.width)) wide, \(number(Metrics.Panel.padding)) padding, \(number(Metrics.Panel.cornerRadius)) corner radius, \(number(Metrics.Panel.sectionSpacing)) between sections",
            "Display card: \(number(Metrics.DisplayCard.cornerRadius)) radius, \(number(Metrics.DisplayCard.padding)) padding; thumbnails \(number(Metrics.DisplayCard.thumbnailSize.width)) × \(number(Metrics.DisplayCard.thumbnailSize.height)), \(number(Metrics.DisplayCard.thumbnailSpacing)) apart",
            "Panel rows: \(number(Metrics.PanelRow.height)) high, \(number(Metrics.PanelRow.cornerRadius)) radius, \(number(Metrics.PanelRow.symbolSize)) symbol, \(number(Metrics.PanelRow.textSize)) text",
            "Window: \(number(Metrics.Window.defaultSize.width)) × \(number(Metrics.Window.defaultSize.height)) default, \(number(Metrics.Window.sidebarWidth)) sidebar, \(number(Metrics.Window.contentPadding)) content padding",
            "Groups: \(number(Metrics.Group.cornerRadius)) radius, \(number(Metrics.Group.rowHeight)) row height, \(number(Metrics.Group.dividerThickness)) px dividers",
            "Trial dialog: \(number(Metrics.Trial.width)) wide, centered on the display being tried",
        ]
    }
}

extension GlassBackground.Kind {
    fileprivate var catalogName: String {
        switch self {
        case .panel: "Panel"
        case .alert: "Alert"
        case .hud: "HUD"
        }
    }
}

extension TextStyle {
    /// The style's name in Figma, after "macOS/".
    var figmaName: String {
        switch self {
        case .largeTitle: "Large Title"
        case .title1: "Title 1"
        case .title2: "Title 2"
        case .title3: "Title 3"
        case .headline: "Headline"
        case .body: "Body"
        case .bodyMedium: "Body Medium"
        case .bodyEmphasized: "Body Emphasized"
        case .callout: "Callout"
        case .calloutEmphasized: "Callout Emphasized"
        case .subheadline: "Subheadline"
        case .subheadlineEmphasized: "Subheadline Emphasized"
        case .footnote: "Footnote"
        case .footnoteEmphasized: "Footnote Emphasized"
        case .caption: "Caption"
        case .mono: "Mono"
        }
    }
}
