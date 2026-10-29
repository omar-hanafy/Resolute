import SwiftUI

/// A row in the window's sidebar: an accent-tinted symbol, a title and an optional detail
/// such as "Main" or a preset count (Figma: Components › Sidebar Item, Default and
/// Selected).
///
/// On its own it is drawn as in Figma: 28 points high, padded, with the selected
/// background. In a sidebar `List`, give the list `.sidebarItemStyle(.list)`: the list then
/// sizes the rows and draws the selection like its own, and the colors follow it.
public struct SidebarItem: View {
    public var title: String
    public var symbol: Symbol
    public var detail: String?
    /// Standalone, draws Figma's selected background; in a list, which draws its own, it
    /// only keeps a dimmed row at full strength.
    public var isSelected: Bool
    /// A display that isn't connected: drawn faintly, as Figma draws the displays under
    /// "Not Connected", unless it is selected.
    public var isDimmed: Bool

    @Environment(\.sidebarItemStyle) private var style
    @Environment(\.backgroundProminence) private var backgroundProminence

    public init(_ title: String, symbol: Symbol, detail: String? = nil, isSelected: Bool = false, isDimmed: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.isSelected = isSelected
        self.isDimmed = isDimmed
    }

    public var body: some View {
        Group {
            switch style {
            case .standalone:
                content
                    .padding(.leading, WindowMetrics.Sidebar.leadingPadding)
                    .padding(.trailing, WindowMetrics.Sidebar.trailingPadding)
                    .frame(height: WindowMetrics.Sidebar.rowHeight)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: WindowMetrics.Sidebar.cornerRadius, style: .continuous)
                                .fill(Palette.surfaceSidebarSelection)
                        }
                    }
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            case .list:
                content
            }
        }
        .opacity(isDimmed && !isSelected ? WindowMetrics.Sidebar.dimmedOpacity : 1)
    }

    private var content: some View {
        HStack(spacing: WindowMetrics.Sidebar.spacing) {
            Image(symbol: symbol)
                .font(.system(size: WindowMetrics.Sidebar.symbolPointSize))
                .foregroundStyle(isEmphasized ? Palette.selectedRowText : Palette.accent)
                .frame(width: WindowMetrics.Sidebar.symbolFrame, height: WindowMetrics.Sidebar.symbolFrame)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.body)
                .foregroundStyle(isEmphasized ? Palette.selectedRowText : Palette.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(detail)
                    .textStyle(.subheadline)
                    .foregroundStyle(isEmphasized ? Palette.selectedRowText : Palette.labelTertiary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Whether a list draws this row selected in the accent color, as macOS does while the
    /// sidebar has focus; the text then turns white like the list's own rows.
    private var isEmphasized: Bool {
        backgroundProminence == .increased
    }
}

/// How `SidebarItem` and `SidebarHeader` are drawn.
public enum SidebarItemStyle: Sendable {
    /// On their own, as in Figma: padded, in 28-point rows, with the selected background.
    case standalone
    /// As the rows and section headers of a sidebar `List`, which sizes, insets and
    /// selects them.
    case list
}

extension View {
    /// Sets how the `SidebarItem`s and `SidebarHeader`s inside are drawn: `.list` for the
    /// rows of a sidebar `List`.
    public func sidebarItemStyle(_ style: SidebarItemStyle) -> some View {
        environment(\.sidebarItemStyle, style)
    }
}

private struct SidebarItemStyleKey: EnvironmentKey {
    static let defaultValue = SidebarItemStyle.standalone
}

extension EnvironmentValues {
    var sidebarItemStyle: SidebarItemStyle {
        get { self[SidebarItemStyleKey.self] }
        set { self[SidebarItemStyleKey.self] = newValue }
    }
}
