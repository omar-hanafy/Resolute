import SwiftUI

/// An invitation inside a display card, with a link that acts on it and a button that hides
/// it: Sharp Scaling's "Sharper text on this display" (Figma: Sharp Scaling Offer, 59:720).
public struct PanelOffer: View {
    public var symbol: Symbol
    public var title: String
    public var message: String
    public var actionTitle: String
    public var action: () -> Void
    /// Hides the offer; nil leaves out the × button.
    public var dismiss: (() -> Void)?

    public init(
        symbol: Symbol = .sparkles,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void,
        dismiss: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: PanelMetrics.Offer.spacing) {
            PanelIcon(symbol, size: .notice)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                Text(title)
                    .panelTextStyle(.subheadlineEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .panelTextStyle(.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PanelLink(actionTitle, action: action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) {
                    PanelIcon(.xmark, size: .dismiss)
                        .foregroundStyle(Palette.labelTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide for This Display")
                .help("Hide for This Display")
            }
        }
        .padding(PanelMetrics.Offer.insets)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.Offer.cornerRadius, style: .continuous)
                .fill(Palette.surfaceAccentTint)
        )
        .accessibilityElement(children: .contain)
    }
}

/// The notice at the top of the panel while a revert waits for a display that went dark
/// during a trial, with Stop Waiting (Figma: Waiting Banner 20:1743, Banner 17:115 in its
/// Warning tone).
public struct WaitingBanner: View {
    /// "Waiting for DELL U2723QE".
    public var title: String
    /// "It went dark while trying 2880 × 1620. Resolute switches it back to 2560 × 1440 as
    /// soon as it reconnects."
    public var message: String
    public var stopWaiting: () -> Void

    public init(title: String, message: String, stopWaiting: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.stopWaiting = stopWaiting
    }

    public var body: some View {
        HStack(alignment: .top, spacing: PanelMetrics.Banner.spacing) {
            PanelIcon(.exclamationmarkTriangleFill, size: .notice)
                .foregroundStyle(Palette.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PanelMetrics.Banner.textSpacing) {
                Text(title)
                    .panelTextStyle(.calloutEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .panelTextStyle(.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(PanelSpeech.text(message))
                PanelLink("Stop Waiting", action: stopWaiting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PanelMetrics.Banner.insets)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.Banner.cornerRadius, style: .continuous)
                .fill(Palette.surfaceWarningTint)
        )
        .accessibilityElement(children: .contain)
    }
}

/// A small accent-colored text button in a notice: "Stop Waiting", "Set Up Sharp Scaling…"
/// (Figma: `macOS/Footnote Emphasized` in `Accents/Blue`).
struct PanelLink: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .panelTextStyle(.footnote, weight: .semibold)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
