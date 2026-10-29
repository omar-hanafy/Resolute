import SwiftUI

/// A grouped section of a window page: the rounded `surface/group` container, with an
/// optional header row (a symbol, a title, a detail such as "Larger Text ↔ More Space" and
/// a trailing accessory such as a badge or filters), its content and an optional footnote
/// (Figma: the Picture and Preview sections of 34:866, Sharp Scaling in 62:1020, Credits in
/// 42:789).
///
/// Without `insets` and `spacing` it is spaced like the Picture section: 14 above, 16 at the
/// sides and below, 12 between the header, the content and the footnote. Sections that
/// Figma spaces differently pass their own.
public struct GroupedSection<Content: View, Accessory: View>: View {
    public var title: String?
    public var symbol: Symbol?
    public var symbolColor: Color
    public var detail: String?
    public var footnote: String?
    public var insets: EdgeInsets
    public var spacing: CGFloat
    private let content: Content
    private let accessory: Accessory

    public init(
        _ title: String? = nil,
        symbol: Symbol? = nil,
        symbolColor: Color = Palette.accent,
        detail: String? = nil,
        footnote: String? = nil,
        insets: EdgeInsets? = nil,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.detail = detail
        self.footnote = footnote
        self.insets = insets ?? WindowMetrics.Section.insets
        self.spacing = spacing ?? WindowMetrics.Section.spacing
        self.content = content()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if hasHeader {
                header
            }
            content
            if let footnote {
                SectionFootnote(footnote)
            }
        }
        .padding(insets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
    }

    private var hasHeader: Bool {
        title != nil || symbol != nil || detail != nil || Accessory.self != EmptyView.self
    }

    private var header: some View {
        HStack(spacing: WindowMetrics.Section.headerSpacing) {
            if let symbol {
                Image(symbol: symbol)
                    .font(.system(size: WindowMetrics.Section.symbolPointSize))
                    .foregroundStyle(symbolColor)
                    .frame(width: WindowMetrics.Section.symbolFrame, height: WindowMetrics.Section.symbolFrame)
                    .accessibilityHidden(true)
            }
            if let title {
                Text(title)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.labelPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
                    .accessibilityLabel(SpokenText.sizes(detail))
            }
            accessory
        }
    }
}

extension GroupedSection where Accessory == EmptyView {
    public init(
        _ title: String? = nil,
        symbol: Symbol? = nil,
        symbolColor: Color = Palette.accent,
        detail: String? = nil,
        footnote: String? = nil,
        insets: EdgeInsets? = nil,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title, symbol: symbol, symbolColor: symbolColor, detail: detail, footnote: footnote,
            insets: insets, spacing: spacing, content: content, accessory: { EmptyView() }
        )
    }
}

/// The small note under a section's content: "Clicking a size switches right away. Hold ⌥
/// to see the pixel size of each."
struct SectionFootnote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textStyle(.footnote)
            .foregroundStyle(Palette.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(SpokenText.sizes(text))
    }
}

extension View {
    /// Figma's grouped container: `surface/group` in a 12-point rounded rectangle, which
    /// also clips what is inside, such as row dividers that run to the edges.
    func groupSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Group.cornerRadius, style: .continuous)
        return background(Palette.surfaceGroup, in: shape)
            .clipShape(shape)
    }
}
