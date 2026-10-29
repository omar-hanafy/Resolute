import SwiftUI

/// A row with a title and a pop-up of choices at the right: Refresh Rate in All Resolutions
/// (Figma 22:468). The pop-up is the native one, so it opens and reads like any macOS menu.
public struct PanelPopUpRow: View {
    public var title: String
    public var symbol: Symbol
    public var choices: [PanelChoice]

    public init(_ title: String, symbol: Symbol, choices: [PanelChoice]) {
        self.title = title
        self.symbol = symbol
        self.choices = choices
    }

    public var body: some View {
        HStack(spacing: Metrics.Spacing.medium) {
            PanelIcon(symbol, size: .row)
                .foregroundStyle(Palette.labelSecondary)
                .accessibilityHidden(true)
            Text(title)
                .panelTextStyle(.body)
                .foregroundStyle(Palette.labelPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            PanelPopUp(title: title, choices: choices)
        }
        .padding(PanelMetrics.PopUpRow.insets)
    }
}

/// The native pop-up button for a list of choices, as wide as its longest choice. Choosing
/// an item runs that choice; nothing changes until the app updates the choices.
struct PanelPopUp: View {
    var title: String
    var choices: [PanelChoice]

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(choices.indices, id: \.self) { index in
                Text(choices[index].title)
                    .accessibilityLabel(choices[index].spokenLabel)
                    .tag(Optional(index))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .frame(minHeight: PanelMetrics.controlHeight)
    }

    /// The selected choice's position; setting it runs the choice at that position.
    var selection: Binding<Int?> {
        Binding {
            choices.selectedIndex
        } set: { index in
            if let index, choices.indices.contains(index) {
                choices[index].select()
            }
        }
    }
}
