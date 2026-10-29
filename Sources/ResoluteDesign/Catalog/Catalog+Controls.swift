import SwiftUI

extension DesignCatalog {
    /// Scenes owned by the controls owner (badge, segments, banners, buttons, HUD).
    @MainActor static var controls: [CatalogScene] {
        badges + segments + banners + buttons + others
    }

    @MainActor private static var badges: [CatalogScene] {
        [
            CatalogScene(id: "ds.controls.badge", title: "Badge: Neutral, Accent, Warning", figmaNode: "17:15", padding: 24) {
                HStack(spacing: 16) {
                    ForEach(Badge.Tone.allCases, id: \.self) { tone in Badge("Default", tone: tone) }
                }
            },
            CatalogScene(id: "ds.controls.badge.in-use", title: "Every badge the screens use", figmaNode: "31:5", padding: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    BadgeRow(title: "Display header (31:5, 34:332, 34:866)", badges: [
                        Badge("Main"), Badge("Built-in"), Badge("HiDPI", tone: .accent),
                        Badge("Override installed", tone: .accent), Badge("Unsaved", tone: .warning),
                    ])
                    BadgeRow(title: "Panel (20:156, 60:547)", badges: [Badge("Default"), Badge("Standard")])
                    BadgeRow(title: "History (37:1957)", badges: [Badge("Kept", tone: .accent), Badge("Reverted"), Badge("Undone")])
                    BadgeRow(title: "Presets (37:2289)", badges: [Badge("Active", tone: .accent)])
                    BadgeRow(title: "Sharp Scaling (62:1020, 67:1585, 67:2175)", badges: [
                        Badge("Off"), Badge("Standard display"), Badge("Sharp Scaling saved", tone: .accent),
                        Badge("Waiting for reconnect"), Badge("Sharp Scaling", tone: .accent),
                    ])
                }
            },
        ]
    }

    @MainActor private static var segments: [CatalogScene] {
        [
            CatalogScene(id: "ds.controls.segment", title: "Segment: Selected, Default", figmaNode: "17:20", padding: 24) {
                HStack(spacing: 16) {
                    SegmentLabel(title: "120 Hz", isSelected: true, fillsWidth: false)
                    SegmentLabel(title: "120 Hz", isSelected: false, fillsWidth: false)
                }
            },
            tabsScene(id: "ds.controls.segmented.window-tabs", title: "Window tabs", node: "31:5",
                      titles: ["Resolution", "Custom Resolutions", "Picture & Name"]),
            tabsScene(id: "ds.controls.segmented.all-modes", title: "All Modes tabs", node: "31:5",
                      titles: ["HiDPI", "Low Resolution (1×)", "Hidden"]),
            tabsScene(id: "ds.controls.segmented.history-filters", title: "History filters", node: "37:1957",
                      titles: ["All", "Panel", "Terminal & Agents", "Shortcuts"]),
            tabsScene(id: "ds.controls.segmented.settings-tabs", title: "Settings tabs", node: "40:149",
                      titles: ["General", "Command Line & Agents", "About"]),
            CatalogScene(id: "ds.controls.segmented.refresh-rates", title: "Refresh rates in a display card", figmaNode: "18:104", backdrop: .wallpaper, padding: 30) {
                PanelCardContext {
                    SegmentedTabs([.init(120, "120 Hz"), .init(60, "60 Hz"), .init(50, "50 Hz"), .init(48, "48 Hz")], selection: .constant(120), size: .large)
                        .accessibilityLabel(Text("Refresh rate"))
                }
            },
            CatalogScene(id: "ds.controls.segmented.kind", title: "HiDPI and Low Resolution tabs in All Resolutions", figmaNode: "22:385", backdrop: .wallpaper, padding: 30) {
                PanelCardContext(innerPadding: Metrics.Spacing.medium) {
                    SegmentedTabs([.init(0, "HiDPI"), .init(1, "Low Resolution (1×)")], selection: .constant(0), size: .large)
                        .accessibilityLabel(Text("Kind of mode"))
                }
            },
        ]
    }

    @MainActor private static func tabsScene(id: String, title: String, node: String, titles: [String]) -> CatalogScene {
        CatalogScene(id: id, title: title, figmaNode: node, padding: 24) {
            SegmentedTabs(titles.map { SegmentedTabs.Item($0, $0) }, selection: .constant(titles[0]))
        }
    }

    @MainActor private static var banners: [CatalogScene] {
        [
            CatalogScene(id: "ds.controls.banner.warning", title: "Banner: Warning", figmaNode: "17:101", padding: 24) {
                Banner("Waiting for DELL U2723QE", message: "It went dark while trying 2880 × 1620.", tone: .warning,
                       action: .init("Stop Waiting") {})
                    .frame(width: 316)
            },
            CatalogScene(id: "ds.controls.banner.info", title: "Banner: Info", figmaNode: "17:108", padding: 24) {
                Banner("Waiting for DELL U2723QE", message: "It went dark while trying 2880 × 1620.", tone: .info,
                       action: .init("Stop Waiting") {})
                    .frame(width: 316)
            },
            CatalogScene(id: "ds.controls.banner.waiting", title: "The panel's waiting banner", figmaNode: "20:1743", backdrop: .wallpaper, padding: 30) {
                PanelContext {
                    Banner(
                        "Waiting for DELL U2723QE",
                        message: "It went dark while trying 2880 × 1620. Resolute switches it back to 2560 × 1440 as soon as it reconnects.",
                        tone: .warning,
                        action: .init("Stop Waiting") {}
                    )
                }
            },
            CatalogScene(id: "ds.controls.banner.offer", title: "The panel's Sharp Scaling offer (compact, with close)", figmaNode: "59:720", backdrop: .wallpaper, padding: 30) {
                PanelCardContext {
                    Banner(
                        "Sharper text on this display",
                        message: "Add Retina-style sizes, from Larger Text to More Space, like a 5K display.",
                        tone: .info,
                        symbol: .sparkles,
                        size: .compact,
                        action: .init("Set Up Sharp Scaling…") {},
                        onDismiss: {}
                    )
                }
            },
            CatalogScene(id: "ds.controls.banner.reconnect", title: "Custom Resolutions: appear after reconnecting", figmaNode: "34:742", padding: 24) {
                Banner(
                    "New resolutions appear after reconnecting",
                    message: "After saving, reconnect DELL U2723QE or restart your Mac. On Apple silicon, macOS may ignore some custom scaled resolutions.",
                    tone: .info
                )
                .frame(width: 704)
            },
            CatalogScene(id: "ds.controls.banner.saved", title: "Sharp Scaling saved: reconnect to finish", figmaNode: "67:1585", padding: 24) {
                Banner(
                    "Reconnect ASUS PA278QV to finish",
                    message: "Five sharp sizes are saved. Unplug the display and plug it back in, or restart your Mac. Resolute checks them as soon as the display is back.",
                    tone: .info
                )
                .frame(width: 704)
            },
            CatalogScene(id: "ds.controls.banner.ready", title: "Sharp Scaling is ready", figmaNode: "67:2175", padding: 24) {
                Banner(
                    "Sharp Scaling is ready",
                    message: "macOS accepted all 5 sizes, and ASUS PA278QV now uses the sharp 2560 × 1440. System Settings › Displays lists the same sizes.",
                    tone: .info
                )
                .frame(width: 704)
            },
            CatalogScene(id: "ds.controls.banner.partial", title: "macOS skipped a size", figmaNode: "68:2089", padding: 30) {
                Banner(
                    "macOS added 4 of 5 sizes",
                    message: "It skipped 2560 × 1440 on this Mac. Keep the other four, or remove the skipped size so the list matches what you can use.",
                    tone: .warning,
                    action: .init("Remove Skipped Size") {}
                )
                .frame(width: 500)
            },
        ]
    }

    @MainActor private static var buttons: [CatalogScene] {
        [
            CatalogScene(id: "ds.controls.button.dialog", title: "Dialog buttons: Keep (secondary), Revert (primary)", figmaNode: "28:64", backdrop: .wallpaper, padding: 30) {
                AlertContext {
                    HStack(spacing: Metrics.CapsuleButton.largeSpacing) {
                        Button("Keep") {}.buttonStyle(.capsule(.secondary))
                        Button("Revert") {}.buttonStyle(.capsule(.primary))
                    }
                }
            },
            CatalogScene(id: "ds.controls.button.dialog.window", title: "Dialog buttons on the window background, and disabled", figmaNode: "28:64", padding: 24) {
                VStack(spacing: 12) {
                    HStack(spacing: Metrics.CapsuleButton.largeSpacing) {
                        Button("Keep") {}.buttonStyle(.capsule(.secondary))
                        Button("Revert") {}.buttonStyle(.capsule)
                    }
                    HStack(spacing: Metrics.CapsuleButton.largeSpacing) {
                        Button("Keep") {}.buttonStyle(.capsule(.secondary))
                        Button("Revert") {}.buttonStyle(.capsule)
                    }
                    .disabled(true)
                }
                .frame(width: 268)
            },
            CatalogScene(id: "ds.controls.button.small", title: "Small capsule: Apply, and disabled", figmaNode: "36:463", padding: 24) {
                HStack(spacing: 16) {
                    Button("Apply") {}.buttonStyle(.capsule(.primary, size: .small))
                    Button("Apply") {}.buttonStyle(.capsule(.secondary, size: .small))
                    Button("Apply") {}.buttonStyle(.capsule(.primary, size: .small)).disabled(true)
                }
            },
            CatalogScene(id: "ds.controls.button.link", title: "Links: Undo, Try…, banner actions, disabled", figmaNode: "17:69", padding: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Button("Undo") {}.buttonStyle(.accentLink)
                    Button("Try…") {}.buttonStyle(.accentLink)
                    Button("Stop Waiting") {}.buttonStyle(.accentLink(.footnoteEmphasized))
                    Button("Set Up Sharp Scaling…") {}.buttonStyle(.accentLink(.footnoteEmphasized))
                    Button("Undo") {}.buttonStyle(.accentLink).disabled(true)
                }
            },
            CatalogScene(id: "ds.controls.button.push", title: "Push buttons are native: bordered, prominent, disabled", figmaNode: "34:758", padding: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: Metrics.Spacing.medium) {
                        Button("Add Resolution…") {}
                        Button("Remove") {}
                        Button("Open…") {}
                        Button("Remove") {}.disabled(true)
                    }
                    HStack(spacing: Metrics.Spacing.medium) {
                        Button("Set Up Sharp Scaling…") {}.buttonStyle(.borderedProminent)
                        Button("Undo Setup…") {}
                        Button("New Preset from Current Setup") {}
                        Button("Import…") {}
                    }
                }
            },
        ]
    }

    @MainActor private static var others: [CatalogScene] {
        [
            CatalogScene(id: "ds.controls.section-label", title: "Section label: panel (inset) and form", figmaNode: "17:61", padding: 24) {
                HStack(alignment: .top, spacing: 40) {
                    SectionLabel("Presets")
                        .padding(.top, Metrics.SectionLabel.panelTopPadding)
                        .padding(.bottom, Metrics.SectionLabel.panelBottomPadding)
                        .padding(.horizontal, Metrics.SectionLabel.panelHorizontalPadding)
                        .border(Palette.strokeHairline)
                    SectionLabel("Startup", style: .form)
                }
            },
            CatalogScene(id: "ds.controls.shortcut", title: "Shortcuts: chips, a panel row's, a form row's", figmaNode: "36:471", padding: 24) {
                HStack(spacing: 20) {
                    ShortcutLabel("⌃⌥1")
                    ShortcutLabel("⌃⌥2")
                    ShortcutLabel(key: "3", modifiers: [.control, .option])
                    ShortcutLabel("⌘,", style: .menuItem)
                    ShortcutLabel("⌘Q", style: .menuItem)
                    ShortcutLabel(key: "r", modifiers: [.option, .control], style: .formRow)
                }
            },
            CatalogScene(id: "ds.controls.countdown", title: "Countdown at 75%, with its caption", figmaNode: "28:34", backdrop: .wallpaper, padding: 30) {
                AlertContext {
                    VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
                        CountdownBar(fraction: 0.75)
                        Text("If the screen stays black, wait or press Return.")
                            .textBox(.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                }
            },
            CatalogScene(id: "ds.controls.countdown.states", title: "Countdown: full, 12 of 15 seconds, almost out, out", figmaNode: "28:35", padding: 24) {
                VStack(spacing: 12) {
                    CountdownBar(fraction: 1)
                    CountdownBar(remaining: 12, total: 15)
                    CountdownBar(remaining: 0.2, total: 15)
                    CountdownBar(remaining: 0, total: 15)
                }
                .frame(width: 268)
            },
            hudScene(id: "ds.controls.hud.switched-back", node: "29:68",
                     card: HUDCard("Switched back", subtitle: "DELL U2723QE · 2560 × 1440", symbol: .arrowUturnBackward)),
            hudScene(id: "ds.controls.hud.kept", node: "29:78",
                     card: HUDCard("Kept", subtitle: "2880 × 1620 until you log out", symbol: .checkmarkCircleFill, tone: .positive)),
            CatalogScene(id: "ds.controls.divider", title: "Hairline dividers: across a group, down a row", figmaNode: "20:430", padding: 24) {
                VStack(spacing: 0) {
                    ForEach(["Launch at Login", "Show the resolution next to the icon"], id: \.self) { title in
                        if title != "Launch at Login" { HairlineDivider() }
                        HStack {
                            Text(title).textBox(.body).foregroundStyle(Palette.labelPrimary)
                            Spacer()
                            HairlineDivider(.vertical).frame(height: 20)
                            Text("On").textBox(.body).foregroundStyle(Palette.labelSecondary)
                        }
                        .padding(.horizontal, Metrics.Group.horizontalPadding)
                        .frame(height: Metrics.Group.rowHeight)
                    }
                }
                .frame(width: 400)
                .background(RoundedRectangle(cornerRadius: Metrics.Group.cornerRadius, style: .continuous).fill(Palette.surfaceGroup))
            },
        ]
    }

    @MainActor private static func hudScene(id: String, node: String, card: HUDCard) -> CatalogScene {
        CatalogScene(id: id, title: "HUD: \(card.title)", figmaNode: node, size: CGSize(width: 620, height: 400), backdrop: .wallpaper) {
            card.glassBlending(.withinWindow)
        }
    }
}

/// A titled row of badges, for the scene that collects every badge.
private struct BadgeRow: View {
    var title: String
    var badges: [Badge]

    var body: some View {
        HStack(spacing: 6) {
            Text(title).textBox(.callout).foregroundStyle(Palette.labelSecondary).frame(width: 260, alignment: .leading)
            ForEach(badges.indices, id: \.self) { badges[$0] }
        }
    }
}

/// The panel's glass around a control, as wide as the panel, blending within the
/// gallery window.
private struct PanelContext<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Metrics.Panel.padding)
            .frame(width: Metrics.Panel.width)
            .glassBackground(.panel, cornerRadius: Metrics.Panel.cornerRadius)
            .glassBlending(.withinWindow)
    }
}

/// A display card in the panel around a control, so it is judged on the surface it sits on.
private struct PanelCardContext<Content: View>: View {
    var innerPadding = Metrics.DisplayCard.padding
    @ViewBuilder var content: Content

    var body: some View {
        PanelContext {
            content
                .padding(innerPadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.DisplayCard.cornerRadius, style: .continuous)
                        .fill(Palette.surfaceCard)
                )
        }
    }
}

/// The trial dialog's glass around a control, as wide as the dialog.
private struct AlertContext<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Metrics.Spacing.xLarge)
            .frame(width: Metrics.Trial.width)
            .glassBackground(.alert, cornerRadius: Metrics.Trial.cornerRadius)
            .glassBlending(.withinWindow)
    }
}
