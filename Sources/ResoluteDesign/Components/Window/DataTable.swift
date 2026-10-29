import AppKit
import SwiftUI

/// A column of a `DataTable`: its heading and how wide it is.
public struct DataTableColumn: Hashable, Sendable {
    public var title: String
    /// Points, or nil to take the width the other columns leave.
    public var width: CGFloat?

    public init(_ title: String, width: CGFloat? = nil) {
        self.title = title
        self.width = width
    }

    /// All Modes on the Resolution tab (Figma 31:5): Resolution, Kind, Rendered At, Refresh
    /// Rates.
    public static let modes: [DataTableColumn] = [
        DataTableColumn("Resolution", width: 200),
        DataTableColumn("Kind", width: 110),
        DataTableColumn("Rendered At", width: 150),
        DataTableColumn("Refresh Rates"),
    ]

    /// Custom Resolutions (Figma 34:332): Resolution, Kind, Rendered At, Aspect.
    public static let customResolutions: [DataTableColumn] = [
        DataTableColumn("Resolution", width: 200),
        DataTableColumn("Kind", width: 110),
        DataTableColumn("Rendered At", width: 150),
        DataTableColumn("Aspect"),
    ]
}

/// A table's column headings over a hairline (Figma: Components › Table Header).
public struct DataTableHeader: View {
    public var columns: [DataTableColumn]

    public init(columns: [DataTableColumn]) {
        self.columns = columns
    }

    public var body: some View {
        DataTableCells(columns: columns) { index in
            Text(columns[index].title)
                .textStyle(.subheadlineEmphasized)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(1)
        }
        .frame(height: WindowMetrics.Table.rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.strokeHairline)
                .frame(height: Metrics.Group.dividerThickness)
        }
        .accessibilityHidden(true)
    }
}

/// A row of a table (Figma: Components › Table Row): the first value in the primary label
/// color, the rest secondary; every other row tinted; the selected row in the accent color,
/// and the row the arrow keys are on outlined in it, in a table that chooses with Return.
public struct DataTableRow: View {
    /// Figma's Default, Alternate and Selected.
    public enum Style: Sendable {
        case plain
        /// Every other row, lightly tinted.
        case alternate
        case selected
    }

    public var columns: [DataTableColumn]
    public var values: [String]
    public var style: Style
    public var isHighlighted: Bool

    public init(columns: [DataTableColumn], values: [String], style: Style = .plain, isHighlighted: Bool = false) {
        self.columns = columns
        self.values = values
        self.style = style
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        DataTableCells(columns: columns) { index in
            Text(index < values.count ? values[index] : "")
                .textStyle(.body)
                .foregroundStyle(foreground(column: index))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: WindowMetrics.Table.rowHeight)
        .background(background, in: RoundedRectangle(cornerRadius: WindowMetrics.Table.rowCornerRadius, style: .continuous))
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: WindowMetrics.Table.rowCornerRadius, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: WindowMetrics.Table.highlightLineWidth)
            }
        }
    }

    private func foreground(column: Int) -> Color {
        if style == .selected { return Palette.selectedRowText }
        return column == 0 ? Palette.labelPrimary : Palette.labelSecondary
    }

    private var background: Color {
        switch style {
        case .plain: .clear
        case .alternate: Palette.surfaceGroup
        case .selected: Palette.accent
        }
    }

    /// Figma tints every other row, starting with the second, and draws the selected one in
    /// the accent color.
    public static func style(forRowAt index: Int, isSelected: Bool) -> Style {
        if isSelected { return .selected }
        return index.isMultiple(of: 2) ? .plain : .alternate
    }
}

/// Lays out one cell per column, 12 points in from the row's ends.
private struct DataTableCells<Cell: View>: View {
    var columns: [DataTableColumn]
    @ViewBuilder var cell: (Int) -> Cell

    var body: some View {
        DataTableColumnLayout(widths: columns.map(\.width)) {
            ForEach(columns.indices, id: \.self) { index in
                cell(index)
            }
        }
        .padding(.horizontal, WindowMetrics.Table.horizontalPadding)
    }
}

/// Places a row's cells at their columns' widths, centered on the row. A column without a
/// width takes what the others leave. In a row too narrow to leave it
/// `minimumFlexibleWidth`, the other columns narrow alike, so every column stays readable
/// at the window's smallest size.
struct DataTableColumnLayout: Layout {
    var widths: [CGFloat?]

    static let minimumFlexibleWidth: CGFloat = 80

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Self.idealWidth(widths)
        let columns = Self.columnWidths(widths, in: width)
        let height = zip(subviews, columns)
            .map { subview, column in subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, column) in zip(subviews, Self.columnWidths(widths, in: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
            x += column
        }
    }

    /// The row's width with every column at its own width.
    static func idealWidth(_ widths: [CGFloat?]) -> CGFloat {
        widths.reduce(0) { $0 + ($1 ?? minimumFlexibleWidth) }
    }

    /// Each column's width in a row `available` points wide.
    static func columnWidths(_ widths: [CGFloat?], in available: CGFloat) -> [CGFloat] {
        let fixed = widths.reduce(0) { $0 + ($1 ?? 0) }
        let flexibleCount = widths.filter { $0 == nil }.count
        let flexibleMinimum = minimumFlexibleWidth * CGFloat(flexibleCount)
        let scale = fixed > 0 && fixed + flexibleMinimum > available ? max(0, available - flexibleMinimum) / fixed : 1
        let flexible = flexibleCount > 0 ? max(0, available - fixed * scale) / CGFloat(flexibleCount) : 0
        return widths.map { width in width.map { $0 * scale } ?? flexible }
    }
}

/// A table in its section: an optional title row with accessories at its end ("All Modes"
/// with its filters, "Custom Resolutions" with Add Resolution… and Remove), the column
/// headings, the rows and an optional footnote (Figma: All Modes in 31:5, Custom
/// Resolutions in 34:332 and 37:1480, the backups of 35:1103).
///
/// Like a macOS table, clicking a row selects it, ⌘-click and ⇧-click add to a multiple
/// selection, and ↑ and ↓ move the selection while the table has focus; a page adds
/// `.onDeleteCommand` for the Delete key. In a table whose choice acts at once, such as
/// All Modes, where choosing a row switches the display, ↑ and ↓ move a highlight instead
/// and Return or Space chooses the row (`choosesWithReturn`). The table shows every row;
/// the page around it scrolls.
public struct DataTable<ID: Hashable, Accessory: View>: View {
    /// One row of values, in column order.
    public struct Row: Identifiable {
        public var id: ID
        public var values: [String]
        /// What VoiceOver reads for the row, such as "1280 by 800, HiDPI, rendered at 2560
        /// by 1600". Without it, VoiceOver reads the values after their columns' titles.
        public var accessibilityLabel: String?

        public init(id: ID, values: [String], accessibilityLabel: String? = nil) {
            self.id = id
            self.values = values
            self.accessibilityLabel = accessibilityLabel
        }

        /// The row as one line, since VoiceOver doesn't read the headings: "2560 by 1080,
        /// Kind: HiDPI, Rendered At: 5120 by 2160, Aspect: 64:27".
        func spokenLabel(columns: [DataTableColumn]) -> String {
            if let accessibilityLabel {
                return accessibilityLabel
            }
            return values.enumerated().compactMap { index, value -> String? in
                guard !value.isEmpty else { return nil }
                let spoken = SpokenText.sizes(value)
                guard index > 0, index < columns.count else { return spoken }
                return "\(columns[index].title): \(spoken)"
            }
            .joined(separator: ", ")
        }
    }

    public var title: String?
    public var columns: [DataTableColumn]
    public var rows: [Row]
    public var footnote: String?
    /// Between the title row, the headings, the rows and the footnote: 6, as in All Modes.
    /// The table without a title (37:1480) uses 4, the backups sheet's (35:1103) 2.
    public var spacing: CGFloat
    /// The section's edges; nil spaces them as Figma's window tables: 12 above a title row,
    /// 8 above the headings without one, 10 under a footnote, 8 elsewhere. The backups
    /// sheet's table is inset 6 all round.
    public var insets: EdgeInsets?
    private let selection: Selection
    private let accessory: Accessory
    private let choosesWithReturn: Bool
    /// The row a ⇧-click extends the selection from.
    @State private var anchor: ID?
    /// The row ↑ and ↓ are on, in a table that chooses with Return; nil when on the selection.
    @State private var highlighted: ID?
    @FocusState private var isFocused: Bool

    /// Rows one of which can be selected; `selection` is nil when none is. With
    /// `choosesWithReturn`, ↑ and ↓ only highlight a row, and Return or Space chooses it.
    public init(
        _ title: String? = nil,
        columns: [DataTableColumn],
        rows: [Row],
        selection: Binding<ID?>,
        choosesWithReturn: Bool = false,
        footnote: String? = nil,
        spacing: CGFloat? = nil,
        insets: EdgeInsets? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title, columns, rows, .single(selection), choosesWithReturn, footnote, spacing, insets, accessory())
    }

    /// Rows any number of which can be selected, such as custom resolutions to remove.
    public init(
        _ title: String? = nil,
        columns: [DataTableColumn],
        rows: [Row],
        selection: Binding<Set<ID>>,
        footnote: String? = nil,
        spacing: CGFloat? = nil,
        insets: EdgeInsets? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title, columns, rows, .multiple(selection), false, footnote, spacing, insets, accessory())
    }

    private init(
        _ title: String?,
        _ columns: [DataTableColumn],
        _ rows: [Row],
        _ selection: Selection,
        _ choosesWithReturn: Bool,
        _ footnote: String?,
        _ spacing: CGFloat?,
        _ insets: EdgeInsets?,
        _ accessory: Accessory
    ) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.selection = selection
        self.choosesWithReturn = choosesWithReturn
        self.footnote = footnote
        self.spacing = spacing ?? WindowMetrics.Table.spacing
        self.insets = insets
        self.accessory = accessory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if hasTitleRow {
                titleRow
            }
            DataTableHeader(columns: columns)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, at: index)
            }
            if let footnote {
                SectionFootnote(footnote)
            }
        }
        .padding(insets ?? DataTableLayout.insets(hasTitle: hasTitleRow, hasFootnote: footnote != nil))
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
        // One focus stop for the whole table, as a macOS table is; the selected rows show
        // where it is, so the focus ring would only box the section.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onMoveCommand(perform: move)
        .onKeyPress(keys: [.return, .space]) { _ in chooseHighlighted() ? .handled : .ignored }
        .onChange(of: isFocused) { _, focused in
            if !focused { highlighted = nil }
        }
        .accessibilityElement(children: .contain)
    }

    private var hasTitleRow: Bool {
        title != nil || Accessory.self != EmptyView.self
    }

    private var titleRow: some View {
        HStack(spacing: WindowMetrics.Table.titleSpacing) {
            if let title {
                Text(title)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.labelPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(WindowMetrics.Table.titleInsets)
    }

    private func rowView(_ row: Row, at index: Int) -> some View {
        let isSelected = selection.contains(row.id)
        return DataTableRow(
            columns: columns,
            values: row.values,
            style: DataTableRow.style(forRowAt: index, isSelected: isSelected),
            isHighlighted: highlighted == row.id && !isSelected
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            click(row.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel(columns: columns))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            click(row.id, command: false, shift: false)
        }
    }

    private func click(_ id: ID, command: Bool, shift: Bool) {
        isFocused = true
        highlighted = nil
        switch selection {
        case .single(let binding):
            binding.wrappedValue = id
            anchor = id
        case .multiple(let binding):
            let result = DataTableSelection.click(
                id, order: rows.map(\.id), selected: binding.wrappedValue, anchor: anchor, command: command, shift: shift
            )
            binding.wrappedValue = result.selected
            anchor = result.anchor
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let order = rows.map(\.id)
        let current: ID?
        switch selection {
        case .single(let binding): current = binding.wrappedValue
        case .multiple(let binding): current = anchor.flatMap { binding.wrappedValue.contains($0) ? $0 : nil }
            ?? order.last(where: binding.wrappedValue.contains)
        }
        let step: Int
        switch direction {
        case .up: step = -1
        case .down: step = 1
        default: return
        }
        if choosesWithReturn {
            highlighted = DataTableSelection.highlight(by: step, order: order, highlighted: highlighted, selected: current)
            return
        }
        guard let next = DataTableSelection.move(by: step, order: order, from: current) else { return }
        switch selection {
        case .single(let binding): binding.wrappedValue = next
        case .multiple(let binding): binding.wrappedValue = [next]
        }
        anchor = next
    }

    /// Return or Space: chooses the highlighted row, as a click would. False when no row is
    /// highlighted, so the key goes on to the page.
    private func chooseHighlighted() -> Bool {
        guard choosesWithReturn, let id = highlighted, rows.contains(where: { $0.id == id }) else { return false }
        click(id, command: false, shift: false)
        return true
    }

    /// Which rows the table selects.
    private enum Selection {
        case single(Binding<ID?>)
        case multiple(Binding<Set<ID>>)

        func contains(_ id: ID) -> Bool {
            switch self {
            case .single(let binding): binding.wrappedValue == id
            case .multiple(let binding): binding.wrappedValue.contains(id)
            }
        }
    }
}

extension DataTable where Accessory == EmptyView {
    /// Rows one of which can be selected, without a title row's accessories.
    public init(
        _ title: String? = nil,
        columns: [DataTableColumn],
        rows: [Row],
        selection: Binding<ID?>,
        footnote: String? = nil,
        spacing: CGFloat? = nil,
        insets: EdgeInsets? = nil
    ) {
        self.init(
            title, columns: columns, rows: rows, selection: selection, footnote: footnote, spacing: spacing,
            insets: insets, accessory: { EmptyView() }
        )
    }

    /// Rows any number of which can be selected, without a title row's accessories.
    public init(
        _ title: String? = nil,
        columns: [DataTableColumn],
        rows: [Row],
        selection: Binding<Set<ID>>,
        footnote: String? = nil,
        spacing: CGFloat? = nil,
        insets: EdgeInsets? = nil
    ) {
        self.init(
            title, columns: columns, rows: rows, selection: selection, footnote: footnote, spacing: spacing,
            insets: insets, accessory: { EmptyView() }
        )
    }
}

/// How a table's selection answers clicks and arrow keys, as macOS tables do.
enum DataTableSelection {
    /// A click on `id`: on its own it selects only that row; with ⌘ it adds or removes
    /// the row; with ⇧ it selects every row from the anchor to it (added to the selection
    /// with ⌘ too). Returns the selection and the anchor for the next ⇧-click.
    static func click<ID: Hashable>(
        _ id: ID,
        order: [ID],
        selected: Set<ID>,
        anchor: ID?,
        command: Bool,
        shift: Bool
    ) -> (selected: Set<ID>, anchor: ID) {
        if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            let range = Set(order[min(from, to)...max(from, to)])
            return (command ? selected.union(range) : range, anchor)
        }
        if command {
            return (selected.symmetricDifference([id]), id)
        }
        return ([id], id)
    }

    /// Where ↑ or ↓ goes in a table that chooses with Return: `step` rows from the
    /// highlight, or from the selection when no row it shows is highlighted (a filter may
    /// have taken that row away). The selection stays until Return or Space chooses the
    /// highlighted row.
    static func highlight<ID: Hashable>(by step: Int, order: [ID], highlighted: ID?, selected: ID?) -> ID? {
        let shown = highlighted.flatMap { order.contains($0) ? $0 : nil }
        return move(by: step, order: order, from: shown ?? selected)
    }

    /// The row `step` rows from `current`, kept within the table: the first row going
    /// down and the last going up when nothing is selected. Nil for a table without rows.
    static func move<ID: Hashable>(by step: Int, order: [ID], from current: ID?) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            return step > 0 ? order.first : order.last
        }
        return order[min(max(index + step, 0), order.count - 1)]
    }
}

/// The table section's edges, as Figma spaces them.
enum DataTableLayout {
    static func insets(hasTitle: Bool, hasFootnote: Bool) -> EdgeInsets {
        let side = WindowMetrics.Table.sideInset
        return EdgeInsets(
            top: hasTitle ? WindowMetrics.Table.titledTopInset : side,
            leading: side,
            bottom: hasFootnote ? WindowMetrics.Table.footnoteBottomInset : side,
            trailing: side
        )
    }
}
