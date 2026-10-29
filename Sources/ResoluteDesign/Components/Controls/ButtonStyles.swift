import SwiftUI

/// A filled capsule button: Revert and Keep in the trial dialog (Figma 28:5), Apply on a
/// preset card (Figma 37:2289). Push buttons in the window ("Open…", "Add Resolution…",
/// "Set Up Sharp Scaling…") are the native bordered buttons, which match the kit.
///
///     Button("Revert") { … }.buttonStyle(.capsule(.primary)).keyboardShortcut(.defaultAction)
///     Button("Apply") { … }.buttonStyle(.capsule(.primary, size: .small))
public struct CapsuleButtonStyle: ButtonStyle {
    public enum Prominence: Sendable {
        /// The accent fill with white text: the default action (Revert, Apply).
        case primary
        /// A translucent fill with primary text, for glass (Keep).
        case secondary
    }

    public enum Size: Sendable {
        /// The trial dialog's buttons: 32 high in `macOS/Body Medium`, filling the width
        /// they are given so a row of them shares it equally.
        case large
        /// A button in a card (Apply): 23 high in `macOS/Callout Emphasized`, as wide as
        /// its title.
        case small
    }

    public var prominence: Prominence
    public var size: Size

    public init(_ prominence: Prominence = .primary, size: Size = .large) {
        self.prominence = prominence
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominence: prominence, size: size)
    }

    var textStyle: TextStyle {
        size == .large ? .bodyMedium : .calloutEmphasized
    }

    var height: CGFloat {
        size == .large ? Metrics.CapsuleButton.largeHeight : Metrics.CapsuleButton.smallHeight
    }

    var horizontalPadding: CGFloat {
        size == .large ? Metrics.CapsuleButton.largeHorizontalPadding : Metrics.CapsuleButton.smallHorizontalPadding
    }

    var foreground: Color {
        prominence == .primary ? Palette.labelWhite : Palette.labelPrimary
    }

    var fill: Color {
        prominence == .primary ? Palette.accent : Palette.fillVibrantSecondary
    }
}

private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: CapsuleButtonStyle.Prominence
    let size: CapsuleButtonStyle.Size
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let style = CapsuleButtonStyle(prominence, size: size)
        configuration.label
            .textStyle(style.textStyle)
            .lineLimit(1)
            .fixedSize(horizontal: size == .small, vertical: false)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, style.horizontalPadding)
            .frame(maxWidth: size == .large ? .infinity : nil)
            .frame(height: style.height)
            .background(Capsule().fill(style.fill))
            .contentShape(Capsule())
            .brightness(configuration.isPressed ? -0.1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Text in the accent color that acts when clicked: "Undo", "Try…", "Stop Waiting",
/// "Set Up Sharp Scaling…" (Figma 20:156, 22:369, 37:1957, 60:547). The text style
/// follows where it sits: `macOS/Callout Emphasized` in rows, `macOS/Footnote
/// Emphasized` under a banner's message.
public struct AccentLinkButtonStyle: ButtonStyle {
    public var textStyle: TextStyle

    public init(_ textStyle: TextStyle = .calloutEmphasized) {
        self.textStyle = textStyle
    }

    public func makeBody(configuration: Configuration) -> some View {
        AccentLinkBody(configuration: configuration, textStyle: textStyle)
    }
}

private struct AccentLinkBody: View {
    let configuration: ButtonStyleConfiguration
    let textStyle: TextStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .textBox(textStyle)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isEnabled ? Palette.accent : Palette.labelTertiary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    /// The primary, large capsule (Revert).
    public static var capsule: CapsuleButtonStyle { CapsuleButtonStyle() }

    public static func capsule(_ prominence: CapsuleButtonStyle.Prominence, size: CapsuleButtonStyle.Size = .large) -> CapsuleButtonStyle {
        CapsuleButtonStyle(prominence, size: size)
    }
}

extension ButtonStyle where Self == AccentLinkButtonStyle {
    /// An accent link in `macOS/Callout Emphasized` ("Undo", "Try…").
    public static var accentLink: AccentLinkButtonStyle { AccentLinkButtonStyle() }

    public static func accentLink(_ textStyle: TextStyle) -> AccentLinkButtonStyle {
        AccentLinkButtonStyle(textStyle)
    }
}
