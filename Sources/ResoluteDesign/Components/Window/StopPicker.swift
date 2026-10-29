import SwiftUI

/// The window's "Larger Text ↔ More Space" picker: a titled section with the display's
/// sizes as `SpaceOption`s spread across it, and a footnote (Figma: the Resolution section
/// of 31:5, and of the Sharp Scaling page, 67:2175). Clicking a size selects it.
public struct StopPicker: View {
    /// One size the picker offers.
    public struct Option: Identifiable, Hashable, Sendable {
        /// Which of the five pictures to draw, 1 (largest text) to 5 (most space); also
        /// what `selection` holds.
        public var stop: Int
        /// "1728 × 1117".
        public var size: String
        /// "Default", "Same size, sharper".
        public var caption: String?

        public var id: Int { stop }

        public init(stop: Int, size: String, caption: String? = nil) {
            self.stop = stop
            self.size = size
            self.caption = caption
        }
    }

    public var title: String
    public var options: [Option]
    public var tone: SpaceThumbnail.Tone
    /// The selected option's `stop`, or nil when the display uses none of these sizes.
    @Binding public var selection: Int?
    public var footnote: String?
    /// Between the header, the sizes and the footnote: 14 by default, as on the Resolution
    /// tab; the Sharp Scaling page uses 12.
    public var spacing: CGFloat?

    public init(
        _ title: String,
        options: [Option],
        tone: SpaceThumbnail.Tone,
        selection: Binding<Int?>,
        footnote: String? = nil,
        spacing: CGFloat? = nil
    ) {
        self.title = title
        self.options = options
        self.tone = tone
        _selection = selection
        self.footnote = footnote
        self.spacing = spacing
    }

    public var body: some View {
        GroupedSection(
            title,
            detail: Self.scaleTitle,
            footnote: footnote,
            insets: WindowMetrics.Space.pickerInsets,
            spacing: spacing ?? WindowMetrics.Space.pickerSpacing
        ) {
            SpaceOptionRow(options, tone: tone, selection: selection) { stop in
                selection = stop
            }
        }
    }

    /// The scale's ends, as Figma writes them over the sizes.
    static let scaleTitle = "Larger Text  ↔  More Space"
}

/// Sizes side by side, spread across the width with the first and last at the edges, as
/// in the Stop Picker; in a window too narrow for them, they narrow instead. Without
/// `onSelect` they are only shown, as in the Sharp Scaling preview (62:1020).
public struct SpaceOptionRow: View {
    public var options: [StopPicker.Option]
    public var tone: SpaceThumbnail.Tone
    public var selection: Int?
    public var onSelect: ((Int) -> Void)?

    public init(_ options: [StopPicker.Option], tone: SpaceThumbnail.Tone, selection: Int? = nil, onSelect: ((Int) -> Void)? = nil) {
        self.options = options
        self.tone = tone
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        SpreadLayout(idealWidth: WindowMetrics.Space.thumbnailSize.width, minimumGap: WindowMetrics.Space.minimumGap) {
            ForEach(options) { option in
                optionView(option)
            }
        }
    }

    @ViewBuilder
    private func optionView(_ option: StopPicker.Option) -> some View {
        let space = SpaceOption(
            stop: option.stop,
            tone: tone,
            size: option.size,
            caption: option.caption,
            isSelected: option.stop == selection
        )
        if let onSelect {
            Button {
                onSelect(option.stop)
            } label: {
                space.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(option.stop == selection ? .isSelected : [])
        } else {
            space
        }
    }
}

/// Lays views out side by side, the first at the leading edge and the last at the trailing
/// one, with the same room between each, like a Figma frame that spaces its children
/// between. Each view is `idealWidth` wide unless the views wouldn't fit with
/// `minimumGap` between them; then all of them narrow alike. Views sit at the top.
struct SpreadLayout: Layout {
    var idealWidth: CGFloat
    var minimumGap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(subviews.count)
        let width = proposal.width ?? idealWidth * count + minimumGap * max(count - 1, 0)
        let itemWidth = Self.itemWidth(count: subviews.count, width: width, idealWidth: idealWidth, minimumGap: minimumGap)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = Self.positions(count: subviews.count, width: bounds.width, idealWidth: idealWidth, minimumGap: minimumGap)
        let itemWidth = Self.itemWidth(count: subviews.count, width: bounds.width, idealWidth: idealWidth, minimumGap: minimumGap)
        for (subview, x) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: itemWidth, height: nil)
            )
        }
    }

    /// How wide each of `count` views is in `width`.
    static func itemWidth(count: Int, width: CGFloat, idealWidth: CGFloat, minimumGap: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let fitting = (width - minimumGap * CGFloat(count - 1)) / CGFloat(count)
        return max(0, min(idealWidth, fitting))
    }

    /// Where each of `count` views starts in `width`.
    static func positions(count: Int, width: CGFloat, idealWidth: CGFloat, minimumGap: CGFloat) -> [CGFloat] {
        let itemWidth = itemWidth(count: count, width: width, idealWidth: idealWidth, minimumGap: minimumGap)
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let gap = (width - itemWidth * CGFloat(count)) / CGFloat(count - 1)
        return (0..<count).map { CGFloat($0) * (itemWidth + gap) }
    }
}
