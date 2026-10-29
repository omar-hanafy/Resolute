import SwiftUI

extension DesignCatalog {
    /// Scenes owned by the window components owner. Component scenes are laid out like their
    /// Figma frames on the Components page (24 points around, the frame's spacing between
    /// states); the others reproduce a part of a window screen at its width in the window.
    @MainActor static var windowComponents: [CatalogScene] {
        sidebarScenes + headerScenes + sectionScenes + formScenes + spaceScenes + pictureScenes
            + tableScenes + bottomBarScenes + historyScenes + presetScenes
    }

    /// The width of a section in the window's page (Figma's 704-point column).
    private static let pageColumn: CGFloat = 704

    /// The page column at the window's minimum size: the window less the sidebar, the
    /// content area's 20-point margins and the page's 28-point ones.
    private static let narrowPageColumn = Metrics.Window.minimumSize.width - Metrics.Window.sidebarWidth - 2 * 20
        - 2 * Metrics.Window.contentPadding

    // MARK: - Sidebar

    @MainActor private static var sidebarScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.sidebar-header", title: "Sidebar Header", figmaNode: "18:129") {
                SidebarHeader("Displays")
                    .frame(width: 220)
            },
            CatalogScene(id: "ds.window.sidebar-item", title: "Sidebar Item", figmaNode: "18:128", padding: 24) {
                HStack(spacing: 16) {
                    SidebarItem("Built-in Retina Display", symbol: .laptopcomputer, detail: "Main")
                        .frame(width: 220)
                    SidebarItem("Built-in Retina Display", symbol: .laptopcomputer, detail: "Main", isSelected: true)
                        .frame(width: 220)
                }
            },
            CatalogScene(id: "ds.window.sidebar", title: "Sidebar, standalone", figmaNode: "31:5") {
                SampleSidebar()
            },
            CatalogScene(id: "ds.window.sidebar.list", title: "Sidebar, in a List", figmaNode: "31:5") {
                SampleSidebarList()
            },
        ]
    }

    // MARK: - Page and display headers

    @MainActor private static var headerScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.display-header", title: "Display Header", figmaNode: "31:5", padding: 28) {
                DisplayHeader(
                    name: "Built-in Retina Display",
                    facts: "16.2-inch Liquid Retina XDR · 3456 × 2234 pixels · ProMotion up to 120 Hz",
                    picture: .macBookPro,
                    badges: [Badge("Main"), Badge("Built-in"), Badge("HiDPI", tone: .accent)]
                )
                .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.display-header.not-connected", title: "Display Header, not connected", figmaNode: "37:1480", padding: 28) {
                DisplayHeader(
                    name: "LG UltraFine 5K",
                    facts: "Last connected 21 Oct · 5120 × 2880 pixels",
                    picture: .display,
                    badges: [Badge("Not connected"), Badge("Override installed", tone: .accent)],
                    isPictureDimmed: true
                )
                .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.page-header", title: "Page Header", figmaNode: "37:1957", padding: 28) {
                PageHeader(
                    "History",
                    description: "Every switch from the panel, the menu, the resolute command and agents. Undo puts back what was there before; a hidden mode undone after logout cannot come back."
                )
                .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.page-header.title-only", title: "Page Header, title only", figmaNode: "40:149", padding: 28) {
                PageHeader("Settings")
                    .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Grouped sections

    @MainActor private static var sectionScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.grouped-section", title: "Grouped Section with a symbol and badge", figmaNode: "62:1020", padding: 28) {
                SharpScalingOffSection()
                    .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.grouped-section.text", title: "Grouped Section with text", figmaNode: "42:789", padding: 28) {
                GroupedSection(insets: EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16), spacing: 6) {
                    Text("Credits")
                        .textStyle(.bodyEmphasized)
                        .foregroundStyle(Palette.labelPrimary)
                    Text("The idea and the override-file format come from RDM by Avi Alkalay and its forks, including usr-sse2’s resolution editor. Display mirroring follows fcanas/mirror-displays.")
                        .textStyle(.callout)
                        .foregroundStyle(Palette.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("MIT License · © 2026 Omar Khaled")
                        .textStyle(.subheadline)
                        .foregroundStyle(Palette.labelTertiary)
                }
                .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Forms

    @MainActor private static var formScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.form-row", title: "Form Row", figmaNode: "19:160", padding: 24) {
                FormRowControls()
                    .frame(width: 560)
            },
            CatalogScene(id: "ds.window.form-group", title: "Form Group", figmaNode: "40:149", padding: 28) {
                MenuBarFormGroup()
                    .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.form-group.symbol", title: "Form Group with a symbol and a chevron", figmaNode: "42:295", padding: 28) {
                CommandFormGroup()
                    .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.form-group.compact", title: "Form Group without help", figmaNode: "67:1585", padding: 28) {
                ResolutionFormGroup()
                    .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Larger Text ↔ More Space

    @MainActor private static var spaceScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.space-option", title: "Space Option", figmaNode: "18:176", padding: 24) {
                HStack(alignment: .top, spacing: 24) {
                    SpaceOption(stop: 4, tone: .violet, size: "1728 × 1117", caption: "Default")
                    SpaceOption(stop: 4, tone: .violet, size: "1728 × 1117", caption: "Default", isSelected: true)
                }
            },
            CatalogScene(id: "ds.window.stop-picker", title: "Stop Picker", figmaNode: "31:5", padding: 28) {
                StopPicker(
                    "Resolution",
                    options: [
                        StopPicker.Option(stop: 1, size: "1168 × 755"),
                        StopPicker.Option(stop: 2, size: "1312 × 848"),
                        StopPicker.Option(stop: 3, size: "1496 × 967"),
                        StopPicker.Option(stop: 4, size: "1728 × 1117", caption: "Default"),
                        StopPicker.Option(stop: 5, size: "2056 × 1329"),
                    ],
                    tone: .violet,
                    selection: .constant(4),
                    footnote: "Clicking a size switches right away. Hold ⌥ to see the pixel size of each."
                )
                .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.stop-picker.narrow", title: "Stop Picker at the window's minimum width", figmaNode: "31:5", padding: 28) {
                StopPicker(
                    "Resolution",
                    options: [
                        StopPicker.Option(stop: 1, size: "1168 × 755"),
                        StopPicker.Option(stop: 2, size: "1312 × 848"),
                        StopPicker.Option(stop: 3, size: "1496 × 967"),
                        StopPicker.Option(stop: 4, size: "1728 × 1117", caption: "Default"),
                        StopPicker.Option(stop: 5, size: "2056 × 1329"),
                    ],
                    tone: .violet,
                    selection: .constant(4),
                    footnote: "Clicking a size switches right away. Hold ⌥ to see the pixel size of each."
                )
                .frame(width: narrowPageColumn)
            },
            CatalogScene(id: "ds.window.stop-picker.sharp-scaling", title: "Stop Picker, Sharp Scaling", figmaNode: "67:2175", padding: 28) {
                StopPicker(
                    "Resolution",
                    options: [
                        StopPicker.Option(stop: 1, size: "1600 × 900"),
                        StopPicker.Option(stop: 2, size: "1920 × 1080"),
                        StopPicker.Option(stop: 3, size: "2048 × 1152"),
                        StopPicker.Option(stop: 4, size: "2304 × 1296"),
                        StopPicker.Option(stop: 5, size: "2560 × 1440", caption: "Same size, sharper"),
                    ],
                    tone: .teal,
                    selection: .constant(5),
                    footnote: "Clicking a size switches right away. The 1× sizes are still in the panel, under All Resolutions.",
                    spacing: 12
                )
                .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Picture & Name

    @MainActor private static var pictureScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.picture-choice", title: "Picture Choice", figmaNode: "18:147", padding: 24) {
                HStack(spacing: 16) {
                    PictureChoice(.studioDisplay)
                    PictureChoice(.studioDisplay, isSelected: true)
                }
            },
            CatalogScene(id: "ds.window.picture-grid", title: "Picture Choice grid", figmaNode: "34:866", padding: 28) {
                GroupedSection("Picture", detail: "How macOS draws this display in System Settings › Displays") {
                    PictureChoiceGrid(
                        [
                            .init(.macBookPro), .init(.iMac), .init(.studioDisplay), .init(.proDisplayXDR),
                            .init(.display, title: "Display (default)"), .init(.ultrawide), .init(.tv),
                        ],
                        selection: .constant(.studioDisplay)
                    )
                }
                .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Tables

    @MainActor private static var tableScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.table-header", title: "Table Header", figmaNode: "19:161") {
                DataTableHeader(columns: [
                    DataTableColumn("Resolution", width: 200), DataTableColumn("Type", width: 110),
                    DataTableColumn("Rendered At", width: 150), DataTableColumn("Aspect"),
                ])
                .frame(width: 600)
            },
            CatalogScene(id: "ds.window.table-row", title: "Table Row", figmaNode: "19:197", padding: 24) {
                VStack(spacing: 8) {
                    ForEach([DataTableRow.Style.plain, .alternate, .selected], id: \.self) { style in
                        DataTableRow(columns: DataTableColumn.customResolutions, values: ["5120 × 2160", "1×", "5120 × 2160", "64:27"], style: style)
                    }
                }
                .frame(width: 600)
            },
            CatalogScene(id: "ds.window.table.all-modes", title: "Table with filters", figmaNode: "31:5", padding: 28) {
                AllModesTable()
                    .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.table.narrow", title: "Table at the window's minimum width", figmaNode: "31:5", padding: 28) {
                AllModesTable()
                    .frame(width: narrowPageColumn)
            },
            CatalogScene(id: "ds.window.table.custom-resolutions", title: "Table with buttons and a footnote", figmaNode: "34:332", padding: 28) {
                CustomResolutionsTable()
                    .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.table.untitled", title: "Table without a title", figmaNode: "37:1480", padding: 28) {
                DataTable(
                    columns: DataTableColumn.customResolutions,
                    rows: [
                        .init(id: 0, values: ["2560 × 1440", "HiDPI", "5120 × 2880", "16:9"]),
                        .init(id: 1, values: ["3200 × 1800", "HiDPI", "6400 × 3600", "16:9"]),
                        .init(id: 2, values: ["5120 × 2880", "1×", "5120 × 2880", "16:9"]),
                    ],
                    selection: .constant(nil),
                    spacing: 4
                )
                .frame(width: pageColumn)
            },
            CatalogScene(id: "ds.window.table.backups", title: "Table in a sheet", figmaNode: "35:1103", padding: 22) {
                DataTable(
                    columns: [
                        DataTableColumn("Saved", width: 200), DataTableColumn("Resolutions", width: 110),
                        DataTableColumn("Note"),
                    ],
                    rows: [
                        .init(id: 0, values: ["Today, 9:12", "4", "Before adding 3008 × 1692"]),
                        .init(id: 1, values: ["Yesterday, 18:40", "2", "Before removing 3200 × 1800"]),
                        .init(id: 2, values: ["21 Oct, 10:02", "3", "First save by Resolute"]),
                        .init(id: 3, values: ["12 Oct, 22:15", "2", "Written by RDM"]),
                    ],
                    selection: .constant(0),
                    spacing: 2,
                    insets: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
                )
                .frame(width: 556)
            },
        ]
    }

    // MARK: - Unsaved Bar

    @MainActor private static var bottomBarScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.unsaved-bar", title: "Unsaved Bar", figmaNode: "19:198") {
                UnsavedBar("2 unsaved changes. Saving asks for an administrator password.", onRevert: {}, onSave: {})
                    .frame(width: 720)
            },
        ]
    }

    // MARK: - History

    @MainActor private static var historyScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.history-row", title: "History Row", figmaNode: "36:445") {
                HistoryRow(
                    time: "9:41",
                    source: .terminal,
                    title: "DELL U2723QE  2560 × 1440 → 2880 × 1620",
                    detail: "From Claude Code (Terminal) · hidden mode, trial",
                    status: .reverted,
                    onUndo: {}
                )
                .frame(width: 700)
            },
            CatalogScene(id: "ds.window.history-list", title: "History Rows in a section", figmaNode: "37:1957", padding: 28) {
                SampleHistory()
                    .frame(width: pageColumn)
            },
        ]
    }

    // MARK: - Presets

    @MainActor private static var presetScenes: [CatalogScene] {
        [
            CatalogScene(id: "ds.window.preset-card", title: "Preset Card", figmaNode: "36:475", padding: 24) {
                VStack(spacing: 32) {
                    PresetCard(name: "Coding", summary: "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz", shortcut: "⌃⌥1", onApply: {})
                    PresetCard(name: "Coding", summary: "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz", shortcut: "⌃⌥1", isActive: true, onApply: {})
                }
                .frame(width: 700)
                // Figma's frame is 204 high: 29 under the active card.
                .padding(.bottom, 5)
            },
            CatalogScene(id: "ds.window.preset-list", title: "Preset Cards in a list", figmaNode: "37:2289", padding: 28) {
                VStack(spacing: WindowMetrics.Preset.listSpacing) {
                    PresetCard(name: "Coding", summary: "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz", shortcut: "⌃⌥1", isActive: true, onApply: {})
                    PresetCard(name: "Presenting", summary: "Mirroring on · 1920 × 1080 at 60 Hz", shortcut: "⌃⌥2", onApply: {})
                    PresetCard(name: "Gaming", summary: "DELL U2723QE 1920 × 1080 at 60 Hz · Built-in 120 Hz", shortcut: "⌃⌥3", onApply: {})
                }
                .frame(width: pageColumn)
            },
        ]
    }
}

// MARK: - Sample content

/// The sidebar of Figma's window (31:5), built from Sidebar Headers and Items on their own.
private struct SampleSidebar: View {
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader("Displays")
            SidebarItem("Built-in Retina Display", symbol: .laptopcomputer, detail: "Main", isSelected: true)
            SidebarItem("DELL U2723QE", symbol: .display)
            SidebarHeader("Not Connected")
            SidebarItem("LG UltraFine 5K", symbol: .display, isDimmed: true)
            SidebarHeader("Resolute")
            SidebarItem("Presets", symbol: .star, detail: "3")
            SidebarItem("History", symbol: .clockArrowCirclepath)
            SidebarItem("Settings", symbol: .gearshape)
        }
        .padding(.horizontal, 14)
        .frame(width: Metrics.Window.sidebarWidth)
    }
}

/// The same sidebar as a sidebar `List`, the way the window builds it.
private struct SampleSidebarList: View {
    @State private var selection: String? = "built-in"

    var body: some View {
        List(selection: $selection) {
            Section {
                item("built-in", "Built-in Retina Display", .laptopcomputer, detail: "Main")
                item("dell", "DELL U2723QE", .display)
            } header: {
                SidebarHeader("Displays")
            }
            Section {
                item("lg", "LG UltraFine 5K", .display, isConnected: false)
            } header: {
                SidebarHeader("Not Connected")
            }
            Section {
                item("presets", "Presets", .star, detail: "3")
                item("history", "History", .clockArrowCirclepath)
                item("settings", "Settings", .gearshape)
            } header: {
                SidebarHeader("Resolute")
            }
        }
        .listStyle(.sidebar)
        .sidebarItemStyle(.list)
        .scrollDisabled(true)
        .frame(width: Metrics.Window.sidebarWidth, height: 300)
    }

    private func item(_ id: String, _ title: String, _ symbol: Symbol, detail: String? = nil, isConnected: Bool = true) -> some View {
        SidebarItem(title, symbol: symbol, detail: detail, isSelected: selection == id, isDimmed: !isConnected)
            .tag(id)
    }
}

/// Figma's five Form Row controls (19:160), 12 points apart.
private struct FormRowControls: View {
    @State private var isOn = true
    @State private var trial = 15

    var body: some View {
        let title = "Launch at Login"
        let help = "Resolute starts quietly in the menu bar when you log in."
        VStack(spacing: 12) {
            FormRow(title, help: help, isOn: $isOn)
            FormRow(title, help: help, selection: $trial, options: [.init(15, "15 seconds"), .init(30, "30 seconds")])
            FormRow(title, help: help, value: "Installed")
            FormRow(title, help: help, buttonTitle: "Install…") {}
            FormRow(title, help: help, value: "Installed") {}
        }
    }
}

/// Settings › General › Menu Bar (40:149).
private struct MenuBarFormGroup: View {
    @State private var showsResolution = false

    var body: some View {
        FormGroup {
            FormRow(
                "Show Resolute in the menu bar",
                help: "macOS controls this in System Settings › Menu Bar.",
                buttonTitle: "Open…"
            ) {}
            FormRow(
                "Show the resolution next to the icon",
                help: "For example 1728 × 1117. The icon alone takes the least space.",
                isOn: $showsResolution
            )
            FormRow("Open the panel", help: "A keyboard shortcut that opens the panel from anywhere.", value: "⌃⌥R")
        }
    }
}

/// Settings › Command Line & Agents › The resolute command (42:295).
private struct CommandFormGroup: View {
    var body: some View {
        FormGroup {
            FormRow(
                "resolute 0.4.0 is installed",
                help: "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute",
                buttonTitle: "Uninstall…"
            ) {}
            .symbol(.checkmarkCircleFill, color: Palette.green)
            FormRow(
                "Diagnostic report",
                help: "Runs resolute doctor: versions, displays, modes and overrides, ready for a bug report.",
                buttonTitle: "Copy Report"
            ) {}
            FormRow(
                "JSON output",
                help: "Most commands take --json. Keys are always present, null when there is no value.",
                value: "docs/json.md"
            ) {}
        }
    }
}

/// The Resolution and Refresh Rate rows of a standard display (67:1585).
private struct ResolutionFormGroup: View {
    @State private var resolution = 0
    @State private var refreshRate = 75

    var body: some View {
        FormGroup {
            FormRow("Resolution", selection: $resolution, options: [.init(0, "2560 × 1440 · Native")])
            FormRow("Refresh Rate", selection: $refreshRate, options: [.init(75, "75 Hz"), .init(60, "60 Hz")])
        }
    }
}

/// Sharp Scaling before it is set up (62:1020): a section with a symbol and a badge, the
/// sizes it would add, shown faintly, and its button.
private struct SharpScalingOffSection: View {
    var body: some View {
        GroupedSection(
            "Sharp Scaling",
            symbol: .sparkles,
            insets: WindowMetrics.Space.pickerInsets,
            spacing: 12
        ) {
            Text("Give this display the sizes a 5K display has: five steps from Larger Text to More Space. Each is drawn at twice its size, then scaled to the panel, so text stays sharp at every step.")
                .textStyle(.body)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SpaceOptionRow(
                [
                    StopPicker.Option(stop: 1, size: "1600 × 900", caption: "Larger Text"),
                    StopPicker.Option(stop: 2, size: "1920 × 1080"),
                    StopPicker.Option(stop: 3, size: "2048 × 1152"),
                    StopPicker.Option(stop: 4, size: "2304 × 1296"),
                    StopPicker.Option(stop: 5, size: "2560 × 1440", caption: "Same as now"),
                ],
                tone: .teal
            )
            .opacity(0.55)
            HStack(spacing: 12) {
                Button("Set Up Sharp Scaling…") {}
                    .buttonStyle(.borderedProminent)
                SectionFootnote("Asks for an administrator password. The sizes appear after the display reconnects.")
            }
        } accessory: {
            Badge("Off")
        }
    }
}

/// All Modes on the Resolution tab (31:5), with its filters.
private struct AllModesTable: View {
    @State private var filter = 0
    @State private var selection: Int? = 2

    var body: some View {
        let rates = "120 · 60 · 50 · 48 Hz"
        DataTable(
            "All Modes",
            columns: DataTableColumn.modes,
            rows: [
                .init(id: 0, values: ["2056 × 1329", "HiDPI", "4112 × 2658", rates]),
                .init(id: 1, values: ["2056 × 1285", "HiDPI", "4112 × 2570", rates]),
                .init(id: 2, values: ["1728 × 1117", "HiDPI · Default", "3456 × 2234", rates]),
                .init(id: 3, values: ["1728 × 1080", "HiDPI", "3456 × 2160", rates]),
                .init(id: 4, values: ["1496 × 967", "HiDPI", "2992 × 1934", rates]),
                .init(id: 5, values: ["1312 × 848", "HiDPI", "2624 × 1696", rates]),
            ],
            selection: $selection
        ) {
            SegmentedTabs([.init(0, "HiDPI"), .init(1, "Low Resolution (1×)"), .init(2, "Hidden")], selection: $filter)
        }
    }
}

/// Custom Resolutions (34:332), with Add Resolution…, Remove and a footnote. Several rows
/// can be selected, to remove them together.
private struct CustomResolutionsTable: View {
    @State private var selection: Set<Int> = [1]

    var body: some View {
        DataTable(
            "Custom Resolutions",
            columns: DataTableColumn.customResolutions,
            rows: [
                .init(id: 0, values: ["5120 × 2160", "1×", "5120 × 2160", "64:27"]),
                .init(id: 1, values: ["2560 × 1080", "HiDPI", "5120 × 2160", "64:27"]),
                .init(id: 2, values: ["3008 × 1692", "HiDPI · New", "6016 × 3384", "16:9"]),
                .init(id: 3, values: ["6016 × 3384", "1× · New", "6016 × 3384", "16:9"]),
            ],
            selection: $selection,
            footnote: "Adding a HiDPI size also adds the 1× size it renders at, as RDM did. Removing it removes that 1× size only if they were added together."
        ) {
            Button("Add Resolution…") {}
            Button("Remove") {}
        }
    }
}

/// History's list of changes (37:1957).
private struct SampleHistory: View {
    var body: some View {
        GroupedSection(insets: EdgeInsets(), spacing: 0) {
            HistoryRow(
                time: "9:41", source: .terminal, title: "DELL U2723QE  2560 × 1440 → 2880 × 1620",
                detail: "From Claude Code (Terminal) · hidden mode · nobody answered", status: .reverted
            )
            HistoryRow(
                time: "9:38", source: .terminal, title: "DELL U2723QE  1920 × 1080 → 2560 × 1440",
                detail: "From Terminal", status: .kept, onUndo: {}
            )
            HistoryRow(
                time: "9:20", source: .menubarRectangle, title: "Built-in Retina Display  120 Hz → 60 Hz",
                detail: "From the panel", status: .kept, onUndo: {}
            )
            HistoryRow(
                time: "Yesterday", source: .switch2, title: "Mirroring on: Built-in + DELL U2723QE",
                detail: "From Shortcuts · “Presenting” preset", status: .kept, onUndo: {}
            )
            HistoryRow(
                time: "Yesterday", source: .menubarRectangle, title: "Built-in Retina Display  1728 × 1117 → 1496 × 967",
                detail: "From the panel", status: .undone
            )
        }
    }
}
