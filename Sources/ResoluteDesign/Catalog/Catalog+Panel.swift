import AppKit
import SwiftUI

extension DesignCatalog {
    /// Scenes owned by the panel components owner: every state of the status item and the
    /// panel's components (Figma: Components › Menu Bar Panel, 50:706), and whole panels
    /// built from them with Figma's sample data (page 8:6, Sharp Scaling 60:543).
    @MainActor static var panelComponents: [CatalogScene] {
        componentScenes + panelScenes
    }

    @MainActor private static var componentScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.panel.status-item", title: "Status item", figmaNode: "17:135", backdrop: .wallpaper, padding: 24) {
                HStack(spacing: 16) {
                    StatusItemPreview(StatusItemImage(.symbol))
                    StatusItemPreview(StatusItemImage(.symbol, isOpen: true))
                    StatusItemPreview(StatusItemImage(.trial(secondsLeft: 12)))
                    StatusItemPreview(StatusItemImage(.resolution("1728 × 1117")))
                    StatusItemPreview(StatusItemImage(.waiting))
                }
            },
            CatalogScene(id: "ds.panel.header", title: "Panel header", figmaNode: "20:160", padding: 20) {
                PanelHeader(openWindow: {}).frame(width: Metrics.Panel.width - 2 * Metrics.Panel.padding)
            },
            CatalogScene(id: "ds.panel.row", title: "Panel row", figmaNode: "17:60", padding: 24) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 12) {
                        PanelRow("Settings…", symbol: .gearshape, action: {})
                        PanelRow("Settings…", symbol: .gearshape, trailing: .shortcut("⌘,"), action: {})
                        PanelRow("Settings…", symbol: .gearshape, trailing: .chevron, action: {})
                        PanelRow("Settings…", symbol: .gearshape, isOn: .constant(true))
                    }
                    VStack(spacing: 12) {
                        PanelRow("Settings…", symbol: .gearshape, isHighlighted: true, action: {})
                        PanelRow("Settings…", symbol: .gearshape, trailing: .shortcut("⌘,"), isHighlighted: true, action: {})
                        PanelRow("Settings…", symbol: .gearshape, trailing: .chevron, isHighlighted: true, action: {})
                    }
                }
                .frame(width: 2 * PanelSample.contentWidth + 24)
            },
            CatalogScene(id: "ds.panel.display-card", title: "Display card", figmaNode: "18:27", padding: 20) {
                PanelSample.builtInCard().frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.display-card.standard", title: "Display card, standard display", figmaNode: "59:704", padding: 20) {
                PanelSample.asusStandardCard().frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.display-card.not-responding", title: "Display card, not responding", figmaNode: "24:1157", padding: 20) {
                PanelSample.dellCard(summary: "Not responding · trying 2880 × 1620")
                    .disabled(true)
                    .frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.display-card.sharp", title: "Display card, Sharp Scaling on", figmaNode: "60:873", padding: 20) {
                PanelSample.asusSharpCard().frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.segments", title: "Refresh rates and tabs", figmaNode: "18:104", padding: 20) {
                VStack(spacing: 12) {
                    PanelSegments(PanelSample.choices(["120 Hz", "60 Hz", "50 Hz", "48 Hz"], selected: 0))
                    PanelSegments(PanelSample.choices(["HiDPI", "Low Resolution (1×)"], selected: 0))
                }
                .frame(width: PanelSample.contentWidth - 2 * Metrics.DisplayCard.padding)
            },
            CatalogScene(id: "ds.panel.offer", title: "Sharp Scaling offer", figmaNode: "59:720", padding: 20) {
                PanelSample.sharpScalingOffer().frame(width: PanelSample.contentWidth - 2 * Metrics.DisplayCard.padding)
            },
            CatalogScene(id: "ds.panel.waiting-banner", title: "Waiting banner", figmaNode: "20:1743", padding: 20) {
                PanelSample.waitingBanner().frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.preset-chip", title: "Preset chip", figmaNode: "17:78", padding: 24) {
                HStack(spacing: 16) {
                    PresetChip("Coding", symbol: .star, action: {})
                    PresetChip("Coding", isActive: true, symbol: .star, action: {})
                }
            },
            CatalogScene(id: "ds.panel.presets", title: "Presets", figmaNode: "20:402", padding: 20) {
                PanelSample.presets().frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.activity-row", title: "Activity row", figmaNode: "17:63", padding: 20) {
                ActivityRow(title: "DELL U2723QE → 2560 × 1440", detail: "From Terminal · 2 min ago", undo: {})
                    .frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.mode-row", title: "Mode row", figmaNode: "17:100", padding: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        ModeRow("1728 × 1117", tag: "Default", action: {})
                        ModeRow("1728 × 1117", tag: "Default", isSelected: true, action: {})
                        ModeRow("1728 × 1117", tag: "Default", isHidden: true, action: {})
                    }
                    HStack(spacing: 16) {
                        ModeRow("2560 × 1080", tag: "Hidden · 21:9", aspectRatio: 2560.0 / 1080, isSelected: true, isHidden: true, action: {})
                        ModeRow("1600 × 1200", aspectRatio: 4.0 / 3, action: {})
                    }
                }
                .frame(width: 3 * PanelSample.modeRowWidth + 2 * 16, alignment: .leading)
            },
            CatalogScene(id: "ds.panel.all-resolutions-header", title: "All Resolutions header", figmaNode: "22:373", padding: 20) {
                AllResolutionsHeader(name: "DELL U2723QE", picture: .display, back: {}).frame(width: PanelSample.contentWidth)
            },
            CatalogScene(id: "ds.panel.pop-up-row", title: "Refresh Rate pop-up", figmaNode: "22:468", padding: 20) {
                PanelPopUpRow("Refresh Rate", symbol: .arrowTriangle2Circlepath, choices: PanelSample.choices(["60 Hz", "50 Hz", "30 Hz"], selected: 0))
                    .frame(width: PanelSample.modeRowWidth)
            },
        ]
    }

    @MainActor private static var panelScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.panel.two-displays", title: "Panel, two displays", figmaNode: "20:156", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.builtInCard()
                    PanelSample.dellCard()
                    PanelSample.presets()
                    ActivityRow(title: "DELL U2723QE → 2560 × 1440", detail: "From Terminal · 2 min ago", undo: {})
                    PanelSample.actions(mirroring: false)
                }
            },
            CatalogScene(id: "ds.panel.all-resolutions", title: "Panel, All Resolutions", figmaNode: "22:369", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelSample.allResolutions()
                }
            },
            CatalogScene(id: "ds.panel.one-display", title: "Panel, one display", figmaNode: "23:818", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.builtInCard()
                    PanelSample.presets()
                    ActivityRow(title: "Built-in → 1496 × 967", detail: "From Claude Code · just now", undo: {})
                    PanelSample.actions(mirroring: nil)
                }
            },
            CatalogScene(id: "ds.panel.waiting", title: "Panel, waiting for a display", figmaNode: "24:1157", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.waitingBanner()
                    PanelSample.builtInCard()
                    PanelSample.dellCard(summary: "Not responding · trying 2880 × 1620").disabled(true)
                    PanelSample.presets()
                    ActivityRow(title: "DELL U2723QE → 2880 × 1620 (hidden)", detail: "From Claude Code · 40 s ago", undo: {})
                    PanelSample.actions(mirroring: false)
                }
            },
            CatalogScene(id: "ds.panel.mirroring", title: "Panel, mirroring", figmaNode: "24:1435", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.mirroringCard()
                    PanelSample.presets()
                    ActivityRow(title: "Mirroring turned on", detail: "From Shortcuts · 5 min ago", undo: {})
                    PanelSample.actions(mirroring: true)
                }
            },
            CatalogScene(id: "ds.panel.sharp-scaling-offer", title: "Panel, standard display", figmaNode: "60:547", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.builtInCard()
                    PanelSample.asusStandardCard()
                    PanelSample.presets()
                    PanelSample.actions(mirroring: false)
                }
            },
            CatalogScene(id: "ds.panel.sharp-scaling-on", title: "Panel, Sharp Scaling on", figmaNode: "60:873", backdrop: .wallpaper, padding: 40) {
                PanelSample.panel {
                    PanelHeader(openWindow: {})
                    PanelSample.builtInCard()
                    PanelSample.asusSharpCard()
                    PanelSample.presets()
                    ActivityRow(symbol: .sparkles, title: "ASUS PA278QV → 2560 × 1440 sharp", detail: "Sharp Scaling is ready · just now", undo: {})
                    PanelSample.actions(mirroring: false)
                }
            },
        ]
    }
}

/// Figma's sample displays and settings, for the panel scenes.
@MainActor
private enum PanelSample {
    /// The width inside the panel's padding: a card's, a row's.
    static let contentWidth = Metrics.Panel.width - 2 * Metrics.Panel.padding
    /// A mode row inside All Resolutions' card.
    static let modeRowWidth: CGFloat = contentWidth - 16

    static func choices(_ titles: [String], selected: Int?) -> [PanelChoice] {
        titles.indices.map { PanelChoice(titles[$0], isSelected: $0 == selected) {} }
    }

    /// A panel over the desktop, with the shadow its window casts.
    static func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        PanelSurface(content: content)
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.32), radius: 12, y: 18)
    }

    static func builtInCard() -> some View {
        DisplayCard(
            name: "Built-in Retina Display",
            summary: "1728 × 1117 · 120 Hz",
            picture: .macBookPro,
            badge: Badge("Default"),
            sizes: .stops(StopStrip(
                choices(["1168 × 755", "1312 × 848", "1496 × 967", "1728 × 1117", "2056 × 1329"], selected: 3),
                caption: "1728 × 1117 · Default",
                tone: .violet
            )),
            refreshRates: choices(["120 Hz", "60 Hz", "50 Hz", "48 Hz"], selected: 0),
            resolutionCount: 22,
            openDisplay: {},
            showAllResolutions: {}
        )
    }

    static func dellCard(summary: String = "2560 × 1440 · 60 Hz") -> some View {
        DisplayCard(
            name: "DELL U2723QE",
            summary: summary,
            picture: .display,
            sizes: .stops(StopStrip(
                choices(["1600 × 900", "1920 × 1080", "2304 × 1296", "2560 × 1440", "3008 × 1692"], selected: 3),
                caption: "2560 × 1440",
                tone: .teal
            )),
            refreshRates: choices(["60 Hz", "50 Hz", "30 Hz"], selected: 0),
            resolutionCount: 19,
            openDisplay: {},
            showAllResolutions: {}
        )
    }

    static func mirroringCard() -> some View {
        DisplayCard(
            name: "Built-in + DELL U2723QE",
            summary: "Mirroring · 1920 × 1080 · 60 Hz",
            picture: .display,
            sizes: .stops(StopStrip(
                choices(["1280 × 720", "1600 × 900", "1920 × 1080", "2304 × 1296", "2560 × 1440"], selected: 2),
                caption: "1920 × 1080",
                tone: .teal
            )),
            refreshRates: choices(["60 Hz", "50 Hz", "30 Hz"], selected: 0),
            resolutionCount: 9,
            openDisplay: {},
            showAllResolutions: {}
        )
    }

    static func asusStandardCard() -> some View {
        DisplayCard(
            name: "ASUS PA278QV",
            summary: "2560 × 1440 · 75 Hz",
            picture: .display,
            badge: Badge("Standard"),
            sizes: .resolutions(choices(
                ["2560 × 1440 · Native", "1920 × 1080", "1600 × 900", "1280 × 720"], selected: 0
            )),
            refreshRates: choices(["75 Hz", "60 Hz", "50 Hz"], selected: 0),
            resolutionCount: 14,
            openDisplay: {},
            showAllResolutions: {}
        ) {
            sharpScalingOffer()
        }
    }

    static func asusSharpCard() -> some View {
        DisplayCard(
            name: "ASUS PA278QV",
            summary: "2560 × 1440 · 75 Hz",
            picture: .display,
            badge: Badge("Sharp", tone: .accent),
            sizes: .stops(StopStrip(
                choices(["1280 × 720", "1600 × 900", "1920 × 1080", "2304 × 1296", "2560 × 1440"], selected: 4),
                caption: "2560 × 1440 · Sharp",
                tone: .teal
            )),
            refreshRates: choices(["75 Hz", "60 Hz", "50 Hz"], selected: 0),
            resolutionCount: 19,
            openDisplay: {},
            showAllResolutions: {}
        )
    }

    static func sharpScalingOffer() -> PanelOffer {
        PanelOffer(
            title: "Sharper text on this display",
            message: "Add Retina-style sizes, from Larger Text to More Space, like a 5K display.",
            actionTitle: "Set Up Sharp Scaling…",
            action: {},
            dismiss: {}
        )
    }

    static func waitingBanner() -> WaitingBanner {
        WaitingBanner(
            title: "Waiting for DELL U2723QE",
            message: "It went dark while trying 2880 × 1620. Resolute switches it back to 2560 × 1440 as soon as it reconnects.",
            stopWaiting: {}
        )
    }

    static func presets() -> PresetsRow {
        PresetsRow(choices(["Coding", "Presenting", "Gaming"], selected: 0), saveCurrentSetup: {})
    }

    /// The rows at the bottom of the panel; Mirror Displays only with two displays (nil
    /// leaves it out).
    @ViewBuilder
    static func actions(mirroring: Bool?) -> some View {
        PanelSeparator()
        VStack(spacing: 0) {
            if let mirroring {
                PanelRow("Mirror Displays", symbol: .rectangleOnRectangle, isOn: .constant(mirroring))
            }
            PanelRow("Custom Resolutions…", symbol: .plusRectangleOnRectangle, action: {})
            PanelRow("Settings…", symbol: .gearshape, trailing: .shortcut("⌘,"), action: {})
            PanelRow("Quit Resolute", symbol: .power, trailing: .shortcut("⌘Q"), action: {})
        }
    }

    @ViewBuilder
    static func allResolutions() -> some View {
        let wide = 16.0 / 9
        AllResolutionsHeader(name: "DELL U2723QE", picture: .display, back: {})
        ModeList(tabs: choices(["HiDPI", "Low Resolution (1×)"], selected: 0)) {
            ModeRow("3360 × 1890", aspectRatio: wide, action: {})
            ModeRow("3008 × 1692", aspectRatio: wide, action: {})
            ModeRow("2560 × 1440", aspectRatio: wide, isSelected: true, action: {})
            ModeRow("2304 × 1296", aspectRatio: wide, action: {})
            ModeRow("1920 × 1080", tag: "Default", aspectRatio: wide, action: {})
            ModeRow("1600 × 900", aspectRatio: wide, action: {})
            ModeRow("1280 × 720", aspectRatio: wide, action: {})
            PanelSeparator()
            PanelRow("Show Hidden Modes", symbol: .eye, isOn: .constant(true))
            PanelFootnote("Modes macOS doesn’t list. Each one runs for 15 seconds first and switches back unless you keep it.")
            ModeRow("2880 × 1620", tag: "Hidden", aspectRatio: wide, isHidden: true, action: {})
            ModeRow("2560 × 1080", tag: "Hidden · 21:9", aspectRatio: 2560.0 / 1080, isHidden: true, action: {})
            ModeRow("2048 × 1152", tag: "Hidden", aspectRatio: wide, isHidden: true, action: {})
            PanelSeparator()
            PanelPopUpRow("Refresh Rate", symbol: .arrowTriangle2Circlepath, choices: choices(["60 Hz", "50 Hz", "30 Hz"], selected: 0))
        }
        // Figma leaves 2 more points under the hint than under the other panels.
        PanelFootnote("Hold ⌥ while clicking the menu bar icon to also see mode numbers and pixel sizes.", tone: .tertiary)
            .padding(.bottom, Metrics.Spacing.xxSmall)
    }
}

/// A status item image as the menu bar shows it: in an image view, with template images
/// tinted in the appearance's text color.
private struct StatusItemPreview: NSViewRepresentable {
    var image: StatusItemImage

    init(_ image: StatusItemImage) {
        self.image = image
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        view.contentTintColor = .textColor
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image.nsImage()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        image.size
    }
}
