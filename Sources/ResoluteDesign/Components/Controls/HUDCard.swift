import SwiftUI

/// The two-second notice after a trial ends: a symbol, a title and a subtitle on glass
/// (Figma 29:68 "Switched back" and 29:78 "Kept").
///
///     HUDCard("Switched back", subtitle: "DELL U2723QE · 2560 × 1440", symbol: .arrowUturnBackward)
///     HUDCard("Kept", subtitle: "2880 × 1620 until you log out", symbol: .checkmarkCircleFill, tone: .positive)
///
/// VoiceOver reads it as one element, with sizes read "by".
public struct HUDCard: View {
    public enum Tone: Sendable, CaseIterable {
        /// The symbol in `Labels/Primary`: "Switched back".
        case neutral
        /// The symbol in `Accents/Green`: "Kept".
        case positive
    }

    public var title: String
    public var subtitle: String
    public var symbol: Symbol
    public var tone: Tone

    public init(_ title: String, subtitle: String, symbol: Symbol, tone: Tone = .neutral) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: Metrics.HUD.spacing) {
            SymbolIcon(symbol, size: Metrics.HUD.symbolSize)
                .foregroundStyle(tone.symbolColor)
            Text(title)
                .textBox(.title3)
                .foregroundStyle(Palette.labelPrimary)
            Text(subtitle)
                .textBox(.callout)
                .foregroundStyle(Palette.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.Spacing.large)
        .frame(width: Metrics.HUD.size.width, height: Metrics.HUD.size.height)
        .glassBackground(.hud, cornerRadius: Metrics.HUD.cornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(SpokenText.sizes(subtitle))"))
    }
}

extension HUDCard.Tone {
    var symbolColor: Color {
        switch self {
        case .neutral: Palette.labelPrimary
        case .positive: Palette.green
        }
    }
}
