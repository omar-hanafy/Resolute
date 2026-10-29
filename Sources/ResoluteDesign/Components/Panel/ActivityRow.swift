import SwiftUI

/// The latest change made from outside the panel, with Undo (Figma: Activity Row, 17:63):
/// "DELL U2723QE → 2560 × 1440", "From Terminal · 2 min ago". The symbol names where the
/// change came from: `terminal` for the command line, `sparkles` for Sharp Scaling.
public struct ActivityRow: View {
    public var symbol: Symbol
    public var title: String
    public var detail: String
    /// Undoes the change; nil leaves out Undo.
    public var undo: (() -> Void)?

    public init(symbol: Symbol = .terminal, title: String, detail: String, undo: (() -> Void)?) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: PanelMetrics.Activity.spacing) {
            PanelIcon(symbol, size: .row)
                .foregroundStyle(Palette.labelSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PanelMetrics.Activity.textSpacing) {
                Text(title)
                    .panelTextStyle(.callout)
                    .foregroundStyle(Palette.labelPrimary)
                Text(detail)
                    .panelTextStyle(.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(PanelSpeech.text(title)), \(PanelSpeech.text(detail))")
            if let undo {
                Button(action: undo) {
                    Text("Undo")
                        .panelTextStyle(.calloutEmphasized)
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(PanelMetrics.Activity.insets)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.Activity.cornerRadius, style: .continuous)
                .fill(Palette.fillSecondary)
        )
        .accessibilityElement(children: .contain)
    }
}
