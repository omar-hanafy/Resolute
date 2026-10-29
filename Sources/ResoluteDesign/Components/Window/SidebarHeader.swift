import SwiftUI

/// A section title in the window's sidebar: "Displays", "Not Connected", "Resolute"
/// (Figma: Components › Sidebar Header).
///
/// On its own it takes Figma's 28-point row, with the title on its bottom edge. As the
/// header of a `Section` in a sidebar `List` with `.sidebarItemStyle(.list)`, the list
/// places it.
public struct SidebarHeader: View {
    public var title: String

    @Environment(\.sidebarItemStyle) private var style

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        switch style {
        case .standalone:
            label
                .padding(.leading, WindowMetrics.Sidebar.headerInsets.leading)
                .padding(.bottom, WindowMetrics.Sidebar.headerInsets.bottom)
                // Figma pads the top by 12 but fixes the row at 28, so the title sits on
                // the bottom edge.
                .frame(maxWidth: .infinity, minHeight: WindowMetrics.Sidebar.rowHeight, alignment: .bottomLeading)
        case .list:
            label
        }
    }

    private var label: some View {
        Text(title)
            .textStyle(.subheadlineEmphasized)
            .foregroundStyle(Palette.labelTertiary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}
