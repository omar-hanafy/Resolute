import SwiftUI

/// A row at the bottom of the panel: Mirror Displays, Custom Resolutions…, Settings…,
/// Quit Resolute (Figma: Panel Row, 17:60). A symbol and a title, then a shortcut, a chevron
/// for a row that opens a page, a switch, or nothing.
///
/// Hovering highlights a row with the accent color, as in a menu; so does `isHighlighted`,
/// for the row the keyboard is on. A row with a switch doesn't highlight: clicking anywhere
/// on it flips the switch.
public struct PanelRow: View {
    public enum Trailing {
        case none
        /// The row's key equivalent as menus show it: "⌘,".
        case shortcut(String)
        /// The row opens a page.
        case chevron
    }

    public var title: String
    public var symbol: Symbol?
    public var trailing: Trailing
    public var isHighlighted: Bool
    private var isOn: Binding<Bool>?
    private var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    public init(
        _ title: String,
        symbol: Symbol? = nil,
        trailing: Trailing = .none,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.isHighlighted = isHighlighted
        self.action = action
    }

    /// A row with a switch on the right (Figma: Trailing=Switch), like Mirror Displays.
    public init(_ title: String, symbol: Symbol? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        trailing = .none
        isHighlighted = false
        self.isOn = isOn
        action = { isOn.wrappedValue.toggle() }
    }

    public var body: some View {
        if let isOn {
            HStack(spacing: Metrics.Spacing.medium) {
                HStack(spacing: Metrics.Spacing.medium) {
                    label(highlighted: false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEnabled { action() }
                }
                .accessibilityHidden(true)
                // Figma's switch is 72% of the kit's; the small size is the nearest native one.
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .modifier(PanelRowFrame(highlighted: false))
        } else {
            let highlighted = isEnabled && (isHighlighted || isHovering)
            Button(action: action) {
                HStack(spacing: Metrics.Spacing.medium) {
                    label(highlighted: highlighted)
                    trailingView(highlighted: highlighted)
                }
                .modifier(PanelRowFrame(highlighted: highlighted))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func label(highlighted: Bool) -> some View {
        if let symbol {
            PanelIcon(symbol, size: .row)
                .foregroundStyle(highlighted ? PanelPalette.onAccent : isEnabled ? Palette.labelSecondary : Palette.labelQuaternary)
        }
        Text(title)
            .panelTextStyle(.body)
            .foregroundStyle(highlighted ? PanelPalette.onAccent : isEnabled ? Palette.labelPrimary : Palette.labelTertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func trailingView(highlighted: Bool) -> some View {
        switch trailing {
        case .none:
            EmptyView()
        case .shortcut(let keys):
            Text(keys)
                .panelTextStyle(.body)
                .foregroundStyle(highlighted ? PanelPalette.onAccent : Palette.labelTertiary)
                .fixedSize()
        case .chevron:
            PanelIcon(.chevronRight, size: .trailing)
                .foregroundStyle(highlighted ? PanelPalette.onAccent : Palette.labelTertiary)
        }
    }
}

/// A panel row's frame: 26 points high, 8 points in on the left and 10 on the right, and the
/// accent fill when highlighted.
private struct PanelRowFrame: ViewModifier {
    var highlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(PanelMetrics.rowInsets)
            .frame(height: Metrics.PanelRow.height)
            .background(
                RoundedRectangle(cornerRadius: Metrics.PanelRow.cornerRadius, style: .continuous)
                    .fill(highlighted ? Palette.accent : Color.clear)
            )
            .contentShape(Rectangle())
    }
}
