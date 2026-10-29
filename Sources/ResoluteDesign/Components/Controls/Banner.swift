import SwiftUI

/// An inline notice in the panel or a window: an icon, a title, a message, and
/// optionally a link and a close button (Figma: Components › Banner, tones Warning and
/// Info). "Waiting for DELL U2723QE", "New resolutions appear after reconnecting",
/// "macOS added 4 of 5 sizes", and the panel's Sharp Scaling offer.
///
/// The banner fills the width it is given; the message wraps.
public struct Banner: View {
    public enum Tone: Sendable, CaseIterable {
        /// Something needs attention: a revert is waiting, macOS skipped a size.
        case warning
        /// Context: resolutions appear after reconnecting, Sharp Scaling is ready.
        case info
    }

    public enum Size: Sendable {
        /// On its own in the panel or a window (Figma 17:115).
        case regular
        /// Inside a panel card, like the Sharp Scaling offer (Figma 60:547): a smaller
        /// title in a tighter frame.
        case compact
    }

    /// The link under the message: "Stop Waiting", "Set Up Sharp Scaling…".
    public struct Action {
        public var title: String
        public var perform: @MainActor () -> Void

        public init(_ title: String, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    public var title: String
    public var message: String
    public var tone: Tone
    public var symbol: Symbol
    public var size: Size
    public var action: Action?
    /// Shows a close button that calls this; nil for a banner that stays.
    public var onDismiss: (@MainActor () -> Void)?

    /// - Parameter symbol: the icon, when the tone's own one doesn't fit (the Sharp
    ///   Scaling offer's sparkles).
    public init(
        _ title: String,
        message: String,
        tone: Tone,
        symbol: Symbol? = nil,
        size: Size = .regular,
        action: Action? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.symbol = symbol ?? tone.symbol
        self.size = size
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let compact = size == .compact
        HStack(alignment: .top, spacing: compact ? Metrics.Banner.Compact.iconSpacing : Metrics.Banner.iconSpacing) {
            SymbolIcon(symbol, size: Metrics.Banner.iconSize)
                .foregroundStyle(tone.symbolColor)
                .accessibilityLabel(Text(tone.accessibilityLabel))
            VStack(alignment: .leading, spacing: compact ? Metrics.Banner.Compact.textSpacing : Metrics.Banner.textSpacing) {
                Text(title)
                    .textBox(compact ? .subheadlineEmphasized : .calloutEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                    .accessibilityLabel(Text(SpokenText.sizes(title)))
                Text(message)
                    .textBox(.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(SpokenText.sizes(message)))
                if let action {
                    Button(action.title) { action.perform() }
                        .buttonStyle(.accentLink(.footnoteEmphasized))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    SymbolIcon(.xmark, size: Metrics.Banner.dismissSize)
                        .foregroundStyle(Palette.labelTertiary)
                        // A larger target than the 11-point glyph, without moving it.
                        .padding(Metrics.Spacing.xSmall)
                        .contentShape(Rectangle())
                        .padding(-Metrics.Spacing.xSmall)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.top, Metrics.Banner.topPadding)
        .padding(.leading, Metrics.Banner.leadingPadding)
        .padding(.bottom, Metrics.Banner.bottomPadding)
        .padding(.trailing, compact ? Metrics.Banner.Compact.trailingPadding : Metrics.Banner.trailingPadding)
        .background(
            RoundedRectangle(
                cornerRadius: compact ? Metrics.Banner.Compact.cornerRadius : Metrics.Banner.cornerRadius,
                style: .continuous
            )
            .fill(tone.background)
        )
        .accessibilityElement(children: .contain)
    }
}

extension Banner.Tone {
    /// The tone's icon: a filled warning triangle or information circle.
    var symbol: Symbol {
        switch self {
        case .warning: .exclamationmarkTriangleFill
        case .info: .infoCircleFill
        }
    }

    var symbolColor: Color {
        switch self {
        case .warning: Palette.orange
        case .info: Palette.accent
        }
    }

    var background: Color {
        switch self {
        case .warning: Palette.surfaceWarningTint
        case .info: Palette.surfaceAccentTint
        }
    }

    /// What VoiceOver reads for the icon, before the title.
    var accessibilityLabel: String {
        switch self {
        case .warning: "Warning"
        case .info: "Information"
        }
    }
}
