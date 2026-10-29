import AppKit
import SwiftUI
import Testing
@testable import ResoluteDesign

@MainActor
@Suite struct WindowComponentsTests {
    /// The size SwiftUI gives `view` when nothing constrains it.
    private func size(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    // MARK: - What VoiceOver reads

    @Test(arguments: [
        ("DELL U2723QE  2560 × 1440 → 2880 × 1620", "DELL U2723QE  2560 by 1440 to 2880 by 1620"),
        ("Built-in Retina Display  120 Hz → 60 Hz", "Built-in Retina Display  120 Hz to 60 Hz"),
        ("16.2-inch Liquid Retina XDR · 3456 × 2234 pixels", "16.2-inch Liquid Retina XDR, 3456 by 2234 pixels"),
        ("1× · New", "1x, New"),
        ("Larger Text  ↔  More Space", "Larger Text to More Space"),
        ("Every command takes --json.", "Every command takes --json."),
    ])
    func sizesAreReadInWords(_ text: String, _ spoken: String) {
        #expect(SpokenText.sizes(text) == spoken)
    }

    @Test(arguments: [
        ("⌃⌥1", "Control-Option-1"),
        ("⌃⌥R", "Control-Option-R"),
        ("⇧⌘↩", "Shift-Command-Return"),
        ("F5", "F5"),
    ])
    func shortcutsAreReadAsMenusNameThem(_ keys: String, _ spoken: String) {
        #expect(SpokenText.shortcut(keys) == spoken)
    }

    @Test func tableRowsReadWithTheirColumns() {
        let row = DataTable<Int, EmptyView>.Row(id: 0, values: ["2560 × 1080", "HiDPI", "5120 × 2160", "64:27"])
        #expect(
            row.spokenLabel(columns: DataTableColumn.customResolutions)
                == "2560 by 1080, Kind: HiDPI, Rendered At: 5120 by 2160, Aspect: 64:27"
        )
        let named = DataTable<Int, EmptyView>.Row(id: 0, values: ["1280 × 800"], accessibilityLabel: "1280 by 800, HiDPI")
        #expect(named.spokenLabel(columns: DataTableColumn.customResolutions) == "1280 by 800, HiDPI")
    }

    @Test func historyRowsReadAsOneLine() {
        let row = HistoryRow(
            time: "9:38", source: .terminal, title: "DELL U2723QE  1920 × 1080 → 2560 × 1440",
            detail: "From Terminal", status: .kept
        )
        #expect(row.spokenLabel == "9:38, DELL U2723QE  1920 by 1080 to 2560 by 1440, From Terminal, Kept")
    }

    @Test func presetCardsReadTheirShortcutAndState() {
        let active = PresetCard(name: "Coding", summary: "Built-in 1496 × 967", shortcut: "⌃⌥1", isActive: true) {}
        #expect(active.spokenLabel == "Coding, Built-in 1496 by 967, Control-Option-1, active")
        let plain = PresetCard(name: "Gaming", summary: "DELL U2723QE 1920 × 1080 at 60 Hz") {}
        #expect(plain.spokenLabel == "Gaming, DELL U2723QE 1920 by 1080 at 60 Hz")
    }

    @Test func spaceOptionsReadTheirSizeAndCaption() {
        #expect(SpaceOption.spokenLabel(size: "1728 × 1117", caption: "Default") == "1728 by 1117, Default")
        #expect(SpaceOption.spokenLabel(size: "2056 × 1329", caption: nil) == "2056 by 1329")
    }

    // MARK: - Rules from Figma

    @Test func historyStatusesUseFigmaWordsAndTones() {
        #expect(HistoryRow.Status.allCases.map(\.title) == ["Kept", "Reverted", "Undone", "Failed"])
        #expect(HistoryRow.Status.kept.tone == .accent)
        #expect(HistoryRow.Status.reverted.tone == .neutral)
        #expect(HistoryRow.Status.undone.tone == .neutral)
        #expect(HistoryRow.Status.failed.tone == .warning)
    }

    /// Every other row is tinted, from the second; selection wins.
    @Test func tableRowsAlternateAndShowSelection() {
        let styles = (0..<4).map { DataTableRow.style(forRowAt: $0, isSelected: false) }
        #expect(styles == [.plain, .alternate, .plain, .alternate])
        #expect(DataTableRow.style(forRowAt: 1, isSelected: true) == .selected)
        #expect(DataTableRow.style(forRowAt: 2, isSelected: true) == .selected)
    }

    @Test func clicksSelectRowsAsMacOSTablesDo() {
        let order = ["a", "b", "c", "d"]
        // A click selects only that row.
        let plain = DataTableSelection.click("c", order: order, selected: ["a", "b"], anchor: "a", command: false, shift: false)
        #expect(plain.selected == ["c"] && plain.anchor == "c")
        // ⌘ adds a row, or removes a selected one.
        let added = DataTableSelection.click("d", order: order, selected: ["a"], anchor: "a", command: true, shift: false)
        #expect(added.selected == ["a", "d"] && added.anchor == "d")
        let removed = DataTableSelection.click("a", order: order, selected: ["a", "d"], anchor: "d", command: true, shift: false)
        #expect(removed.selected == ["d"])
        // ⇧ selects from the anchor to the row, either way, and keeps the anchor.
        let range = DataTableSelection.click("d", order: order, selected: ["b"], anchor: "b", command: false, shift: true)
        #expect(range.selected == ["b", "c", "d"] && range.anchor == "b")
        let back = DataTableSelection.click("a", order: order, selected: ["b", "c", "d"], anchor: "b", command: false, shift: true)
        #expect(back.selected == ["a", "b"])
        // ⌘⇧ adds the range to what is selected; ⇧ without an anchor is a plain click.
        let union = DataTableSelection.click("b", order: order, selected: ["d"], anchor: "a", command: true, shift: true)
        #expect(union.selected == ["a", "b", "d"])
        #expect(DataTableSelection.click("c", order: order, selected: [], anchor: nil, command: false, shift: true).selected == ["c"])
    }

    /// In a table that chooses with Return, the arrows move a highlight from the selection
    /// and leave the selection where it is.
    @Test func arrowKeysMoveAHighlightInATableThatChoosesWithReturn() {
        let order = [10, 20, 30]
        #expect(DataTableSelection.highlight(by: 1, order: order, highlighted: nil, selected: 10) == 20)
        #expect(DataTableSelection.highlight(by: 1, order: order, highlighted: 20, selected: 10) == 30)
        #expect(DataTableSelection.highlight(by: -1, order: order, highlighted: 20, selected: 30) == 10)
        #expect(DataTableSelection.highlight(by: 1, order: order, highlighted: nil, selected: nil) == 10)
    }

    /// A filter tab took the highlighted row away: the arrows move from the selection, not
    /// to the table's ends.
    @Test func arrowKeysMoveFromTheSelectionOnceTheHighlightedRowIsGone() {
        let order = [10, 20, 30, 40, 50]
        #expect(DataTableSelection.highlight(by: 1, order: order, highlighted: 99, selected: 30) == 40)
        #expect(DataTableSelection.highlight(by: -1, order: order, highlighted: 99, selected: 30) == 20)
    }

    @Test func arrowKeysMoveTheSelectionWithinTheTable() {
        let order = [10, 20, 30]
        #expect(DataTableSelection.move(by: 1, order: order, from: 10) == 20)
        #expect(DataTableSelection.move(by: -1, order: order, from: 20) == 10)
        #expect(DataTableSelection.move(by: 1, order: order, from: 30) == 30)
        #expect(DataTableSelection.move(by: -1, order: order, from: 10) == 10)
        // Nothing selected: down starts at the top, up at the bottom.
        #expect(DataTableSelection.move(by: 1, order: order, from: nil) == 10)
        #expect(DataTableSelection.move(by: -1, order: order, from: nil) == 30)
        #expect(DataTableSelection.move(by: 1, order: [Int](), from: nil) == nil)
    }

    @Test func tableSectionsAreInsetAsInFigma() {
        // All Modes (31:5): a title row, no footnote.
        #expect(DataTableLayout.insets(hasTitle: true, hasFootnote: false) == EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8))
        // Custom Resolutions (34:332): a title row and a footnote.
        #expect(DataTableLayout.insets(hasTitle: true, hasFootnote: true) == EdgeInsets(top: 12, leading: 8, bottom: 10, trailing: 8))
        // The table of a display that isn't connected (37:1480).
        #expect(DataTableLayout.insets(hasTitle: false, hasFootnote: false) == EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    @Test func tableColumnsMatchFigma() {
        #expect(DataTableColumn.modes.map(\.title) == ["Resolution", "Kind", "Rendered At", "Refresh Rates"])
        #expect(DataTableColumn.customResolutions.map(\.title) == ["Resolution", "Kind", "Rendered At", "Aspect"])
        for columns in [DataTableColumn.modes, DataTableColumn.customResolutions] {
            #expect(columns.map(\.width) == [200, 110, 150, nil])
        }
    }

    @Test func formRowsAreTallerWithHelp() {
        #expect(FormRowLayout.minimumHeight(hasHelp: true) == 52)
        #expect(FormRowLayout.minimumHeight(hasHelp: false) == 44)
    }

    /// Figma's switch is the macOS 26 switch at 72 %; the older, narrower switch fills its height.
    @Test func switchesFitFigmasBox() {
        let current = FormSwitchFit(native: CGSize(width: 54, height: 24))
        #expect(abs(current.scale - 0.72) < 0.0001)
        #expect(abs(current.size.width - 38.88) < 0.0001 && abs(current.size.height - 17.28) < 0.0001)
        let classic = FormSwitchFit(native: CGSize(width: 38, height: 22))
        #expect(abs(classic.size.height - 17.28) < 0.0001)
        #expect(classic.size.width < 38.88)
        // A switch that reports no size is taken to be the classic one.
        #expect(FormSwitchFit(native: CGSize(width: -1, height: -1)) == classic)
    }

    /// Picture & Name (34:866): five 118-point pictures fit in 672 points, the other two wrap.
    @Test func picturesWrapLikeFigma() {
        let sizes = Array(repeating: CGSize(width: 118, height: 110), count: 7)
        let frames = WrappingLayout.frames(for: sizes, width: 672, spacing: 12, lineSpacing: 12)
        #expect(frames.map(\.minX) == [0, 130, 260, 390, 520, 0, 130])
        #expect(frames.map(\.minY) == [0, 0, 0, 0, 0, 122, 122])
    }

    @Test func aViewWiderThanTheLineTakesALineOfItsOwn() {
        let sizes = [CGSize(width: 50, height: 10), CGSize(width: 300, height: 20), CGSize(width: 50, height: 10)]
        let frames = WrappingLayout.frames(for: sizes, width: 200, spacing: 8, lineSpacing: 4)
        #expect(frames.map(\.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 14), CGPoint(x: 0, y: 38)])
    }

    /// The Resolution tab (31:5): five 116-point sizes spread over 668 points, 22 apart.
    @Test func sizesSpreadAcrossTheSection() {
        #expect(SpreadLayout.itemWidth(count: 5, width: 668, idealWidth: 116, minimumGap: 8) == 116)
        #expect(SpreadLayout.positions(count: 5, width: 668, idealWidth: 116, minimumGap: 8) == [0, 138, 276, 414, 552])
    }

    /// At the window's minimum size the sizes narrow rather than spill out of the section.
    @Test func sizesNarrowWhenTheyDoNotFit() {
        let width: CGFloat = 448
        let itemWidth = SpreadLayout.itemWidth(count: 5, width: width, idealWidth: 116, minimumGap: 8)
        #expect(itemWidth < 116)
        let positions = SpreadLayout.positions(count: 5, width: width, idealWidth: 116, minimumGap: 8)
        #expect(positions.first == 0)
        #expect(abs((positions.last ?? 0) + itemWidth - width) < 0.001)
        #expect(SpreadLayout.positions(count: 1, width: width, idealWidth: 116, minimumGap: 8) == [0])
    }

    /// All Modes at Figma's width keeps Figma's columns; narrower, every column stays readable.
    @Test func tableColumnsKeepFigmaWidthsAndNarrowTogether() {
        let widths = DataTableColumn.modes.map(\.width)
        #expect(DataTableColumnLayout.columnWidths(widths, in: 664) == [200, 110, 150, 204])
        let narrow = DataTableColumnLayout.columnWidths(widths, in: 444)
        #expect(abs(narrow.reduce(0, +) - 444) < 0.001)
        #expect(narrow[3] == DataTableColumnLayout.minimumFlexibleWidth)
        #expect(narrow[0] > narrow[2] && narrow[2] > narrow[1])
        #expect(DataTableColumnLayout.columnWidths([100, 100], in: 100) == [50, 50])
        #expect(DataTableColumnLayout.idealWidth(widths) == 540)
    }

    @Test func theStopPickerSaysWhichEndIsWhich() {
        #expect(StopPicker.scaleTitle == "Larger Text  ↔  More Space")
    }

    // MARK: - Sizes from Figma

    @Test func sidebarRowsAreFigmaSizedOnTheirOwn() {
        #expect(size(of: SidebarHeader("Displays").frame(width: 220)).height == 28)
        #expect(size(of: SidebarItem("Built-in Retina Display", symbol: .laptopcomputer, detail: "Main").frame(width: 220)).height == 28)
        #expect(size(of: SidebarItem("History", symbol: .clockArrowCirclepath, isSelected: true).frame(width: 220)).height == 28)
    }

    /// In a sidebar `List` the list sizes the rows, so the item adds no padding or height.
    @Test func sidebarRowsLeaveTheirSizeToAList() {
        let item = SidebarItem("History", symbol: .clockArrowCirclepath).sidebarItemStyle(.list)
        #expect(size(of: item).height == 18)
        let header = SidebarHeader("Resolute").sidebarItemStyle(.list)
        #expect(size(of: header).height < 28)
    }

    @Test func picturesAreFigmaSizedInBothStates() {
        #expect(size(of: PictureChoice(.studioDisplay)) == CGSize(width: 118, height: 110))
        #expect(size(of: PictureChoice(.studioDisplay, isSelected: true)) == CGSize(width: 118, height: 110))
    }

    @Test func spaceOptionsAreFigmaSized() {
        #expect(size(of: SpaceOption(stop: 4, tone: .violet, size: "1728 × 1117", caption: "Default")) == CGSize(width: 116, height: 116))
        #expect(size(of: SpaceOption(stop: 1, tone: .violet, size: "1168 × 755")) == CGSize(width: 116, height: 96))
    }

    @Test func formRowsAndGroupsAreFigmaSized() {
        let help = "Resolute starts quietly in the menu bar when you log in."
        #expect(size(of: FormRow("Launch at Login", help: help, value: "Installed").frame(width: 704)).height == 52)
        #expect(size(of: FormRow("Refresh Rate", value: "75 Hz").frame(width: 704)).height == 44)
        // Three rows and the two hairlines between them, as in Settings › General (40:149).
        let group = FormGroup {
            FormRow("Show Resolute in the menu bar", help: help, value: "On")
            FormRow("Show the resolution next to the icon", help: help, value: "Off")
            FormRow("Open the panel", help: help, value: "⌃⌥R")
        }
        #expect(size(of: group.frame(width: 704)).height == 158)
        let compact = FormGroup {
            FormRow("Resolution", value: "2560 × 1440 · Native")
            FormRow("Refresh Rate", value: "75 Hz")
        }
        #expect(size(of: compact.frame(width: 704)).height == 89)
    }

    @Test func tableRowsAndHeadingsAre28High() {
        #expect(size(of: DataTableHeader(columns: DataTableColumn.modes).frame(width: 600)).height == 28)
        #expect(size(of: DataTableRow(columns: DataTableColumn.modes, values: ["5120 × 2160"]).frame(width: 600)).height == 28)
    }

    /// The table of a display that isn't connected (37:1480): three rows 4 apart.
    @Test func anUntitledTableIsFigmaSized() {
        let table = DataTable(
            columns: DataTableColumn.customResolutions,
            rows: (0..<3).map { DataTable<Int, EmptyView>.Row(id: $0, values: ["2560 × 1440", "HiDPI", "5120 × 2880", "16:9"]) },
            selection: .constant(nil),
            spacing: 4
        )
        #expect(size(of: table.frame(width: 704)).height == 140)
    }

    @Test func historyRowsAre50High() {
        let row = HistoryRow(time: "9:41", source: .terminal, title: "DELL U2723QE", detail: "From Terminal", status: .reverted) {}
        #expect(size(of: row.frame(width: 700)).height == 50)
    }

    /// Figma lays the active outline out inside the card, so the active card is 3 taller.
    @Test func presetCardsAreFigmaSized() {
        let summary = "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz"
        #expect(size(of: PresetCard(name: "Coding", summary: summary, shortcut: "⌃⌥1") {}.frame(width: 700)).height == 58)
        #expect(size(of: PresetCard(name: "Coding", summary: summary, shortcut: "⌃⌥1", isActive: true) {}.frame(width: 700)).height == 61)
    }

    @Test func theUnsavedBarIs52High() {
        let bar = UnsavedBar("2 unsaved changes. Saving asks for an administrator password.", onRevert: {}, onSave: {})
        #expect(size(of: bar.frame(width: 720)).height == 52)
    }

    /// The Resolution tab's section (31:5) is 203 high; the Sharp Scaling page's (67:2175),
    /// spaced 12 instead of 14, is 199.
    @Test func theStopPickerIsFigmaSized() {
        let options = (1...5).map { StopPicker.Option(stop: $0, size: "1728 × 1117", caption: $0 == 4 ? "Default" : nil) }
        let footnote = "Clicking a size switches right away. Hold ⌥ to see the pixel size of each."
        let resolution = StopPicker("Resolution", options: options, tone: .violet, selection: .constant(4), footnote: footnote)
        #expect(size(of: resolution.frame(width: 704)).height == 203)
        let sharp = StopPicker("Resolution", options: options, tone: .teal, selection: .constant(5), footnote: footnote, spacing: 12)
        #expect(size(of: sharp.frame(width: 704)).height == 199)
    }

    // MARK: - Catalog

    @Test func everyWindowSceneIsNamedAndTraced() {
        let scenes = DesignCatalog.windowComponents
        #expect(scenes.count >= 32)
        for scene in scenes {
            #expect(scene.id.hasPrefix("ds.window."), "\(scene.id)")
            #expect(scene.figmaNode != nil, "\(scene.id) has no Figma node")
        }
        #expect(Set(scenes.map(\.id)).count == scenes.count)
    }

    @Test func everyWindowSceneDraws() {
        for scene in DesignCatalog.windowComponents {
            let fitted = size(of: scene.make())
            #expect(fitted.width > 0 && fitted.height > 0, "\(scene.id) draws nothing")
        }
    }
}
