import SwiftUI

/// The Set Up Sharp Scaling sheet (Figma 66:1271): what Resolute adds, a preview of the
/// chosen sizes, one row per size with what macOS draws for it and how much larger text
/// looks, the switch once the sizes are ready, a note about what this Mac can draw, and
/// Cancel and Add N Sizes….
///
/// Plain values: the app turns its plan into rows and keeps the selection.
public struct SharpScalingSetupForm: View {
    /// One size the sheet offers.
    public struct Row: Identifiable, Hashable, Sendable {
        /// What `selection` holds for it.
        public var id: Int
        /// "1600 × 900".
        public var size: String
        /// "Drawn at 3200 × 1800".
        public var drawn: String
        /// "Text 60% larger", "Same size as now", or why it is left out.
        public var note: String
        /// Draws the note like a label rather than a hint: the size the display has now.
        public var isNoteEmphasized: Bool
        /// False for a size this Mac can't draw: it can't be chosen.
        public var isAvailable: Bool

        public init(id: Int, size: String, drawn: String, note: String, isNoteEmphasized: Bool = false, isAvailable: Bool = true) {
            self.id = id
            self.size = size
            self.drawn = drawn
            self.note = note
            self.isNoteEmphasized = isNoteEmphasized
            self.isAvailable = isAvailable
        }
    }

    public var title: String
    public var message: String
    /// The chosen sizes, as pictures.
    public var preview: [StopPicker.Option]
    /// The preview's highlighted size: the one the display moves to.
    public var previewSelection: Int?
    public var rows: [Row]
    @Binding public var selection: Set<Int>
    /// "Switch to the sharp 2560 × 1440 when it’s ready"; nil leaves the checkbox out.
    public var switchTitle: String?
    @Binding public var switchWhenReady: Bool
    /// "This Mac can draw up to 6144 pixels wide on this display, so all five sizes fit. …"
    public var limitNote: String
    public var footnote: String
    /// "Add 5 Sizes…".
    public var confirmTitle: String
    public var canConfirm: Bool
    /// While the sizes are being written: the controls are off and a spinner shows.
    public var isWorking: Bool
    public var cancel: @MainActor () -> Void
    public var confirm: @MainActor () -> Void

    public init(
        title: String,
        message: String,
        preview: [StopPicker.Option],
        previewSelection: Int?,
        rows: [Row],
        selection: Binding<Set<Int>>,
        switchTitle: String?,
        switchWhenReady: Binding<Bool>,
        limitNote: String,
        footnote: String,
        confirmTitle: String,
        canConfirm: Bool,
        isWorking: Bool,
        cancel: @escaping @MainActor () -> Void,
        confirm: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.message = message
        self.preview = preview
        self.previewSelection = previewSelection
        self.rows = rows
        _selection = selection
        self.switchTitle = switchTitle
        _switchWhenReady = switchWhenReady
        self.limitNote = limitNote
        self.footnote = footnote
        self.confirmTitle = confirmTitle
        self.canConfirm = canConfirm
        self.isWorking = isWorking
        self.cancel = cancel
        self.confirm = confirm
    }

    private typealias Layout = SharpScalingMetrics.Sheet

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(title)
                .textStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textStyle(.subheadline)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(SpokenText.sizes(message))
            if !preview.isEmpty {
                SpreadLayout(idealWidth: Layout.thumbnailSize.width, minimumGap: Layout.previewMinimumGap) {
                    ForEach(preview) { option in
                        PreviewSize(option: option, isSelected: option.stop == previewSelection)
                    }
                }
            }
            sizeList
            if let switchTitle {
                Toggle(isOn: $switchWhenReady) {
                    Text(switchTitle)
                        .textStyle(.body)
                        .foregroundStyle(Palette.labelPrimary)
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(SpokenText.sizes(switchTitle))
            }
            limitNoteView
            Text(footnote)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .disabled(isWorking)
        .padding(Layout.insets)
        .frame(width: Layout.width, alignment: .leading)
    }

    private var sizeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.strokeHairline)
                        .frame(height: Metrics.Group.dividerThickness)
                        .accessibilityHidden(true)
                }
                rowView(row)
            }
        }
        .padding(Layout.listPadding)
        .frame(maxWidth: .infinity)
        .groupSurface()
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            Toggle(isOn: binding(for: row)) {
                Text(row.size)
                    .textStyle(.body)
                    .foregroundStyle(row.isAvailable ? Palette.labelPrimary : Palette.labelTertiary)
            }
            .toggleStyle(.checkbox)
            .disabled(!row.isAvailable)
            .accessibilityLabel(SpokenText.sizes(row.size))
            .accessibilityHint(SpokenText.sizes("\(row.drawn), \(row.note)"))
            .frame(width: Layout.sizeColumnWidth, height: Layout.checkboxHeight, alignment: .leading)
            Text(row.drawn)
                .textStyle(.subheadline)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(1)
                .frame(width: Layout.drawnColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            Text(row.note)
                .textStyle(.subheadline)
                .foregroundStyle(row.isNoteEmphasized ? Palette.labelPrimary : Palette.labelTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(Layout.rowInsets)
    }

    private func binding(for row: Row) -> Binding<Bool> {
        Binding(
            get: { selection.contains(row.id) },
            set: { isOn in
                if isOn { selection.insert(row.id) } else { selection.remove(row.id) }
            }
        )
    }

    private var limitNoteView: some View {
        HStack(alignment: .top, spacing: Layout.noteSpacing) {
            SymbolIcon(.infoCircle, size: Layout.noteIconSize)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(limitNote)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(SpokenText.sizes(limitNote))
        }
        .padding(Layout.noteInsets)
        .background(
            RoundedRectangle(cornerRadius: Layout.noteCornerRadius, style: .continuous)
                .fill(Palette.surfaceAccentTint)
        )
    }

    private var buttons: some View {
        HStack(spacing: Layout.buttonSpacing) {
            Spacer(minLength: 0)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Writing the override file")
            }
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle) { confirm() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
        }
    }
}

/// One size in the sheet's preview: its picture, its size, and a caption.
private struct PreviewSize: View {
    var option: StopPicker.Option
    var isSelected: Bool

    var body: some View {
        VStack(spacing: SharpScalingMetrics.Sheet.previewSpacing) {
            SpaceThumbnail(stop: option.stop, tone: .teal, isSelected: isSelected)
                .frame(
                    width: SharpScalingMetrics.Sheet.thumbnailSize.width,
                    height: SharpScalingMetrics.Sheet.thumbnailSize.height
                )
            Text(option.size)
                .textStyle(isSelected ? .calloutEmphasized : .callout)
                .foregroundStyle(isSelected ? Palette.labelPrimary : Palette.labelSecondary)
                .lineLimit(1)
            if let caption = option.caption {
                Text(caption)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.labelTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpaceOption.spokenLabel(size: option.size, caption: option.caption))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
