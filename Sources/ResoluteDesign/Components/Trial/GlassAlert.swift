import SwiftUI

/// The macOS 27 alert on glass that Resolute shows for a hidden mode on trial and before
/// quitting while a revert waits (Figma 28:5, 28:82, 28:132): the app icon, a bold title,
/// a description, an optional accessory (the countdown), and two capsule buttons sharing
/// the row, the secondary one first and the default one, filled with the accent, last.
///
///     GlassAlert(
///         title: "Keep this display setting?",
///         message: "DELL U2723QE is trying 2880 × 1620, …",
///         secondary: .init("Keep") { … },
///         primary: .init("Revert") { … }
///     ) {
///         CountdownBar(remaining: 12, total: 15)
///     }
///
/// It doesn't handle keys: the window it is in decides what Return and Esc do, since the
/// default may not be the button a SwiftUI shortcut would pick.
public struct GlassAlert<Accessory: View>: View {
    /// One of the two buttons.
    public struct Action {
        public var title: String
        /// What the button does, for VoiceOver, when the title alone doesn't say.
        public var hint: String?
        public var perform: () -> Void

        public init(_ title: String, hint: String? = nil, perform: @escaping () -> Void) {
            self.title = title
            self.hint = hint
            self.perform = perform
        }
    }

    public var title: String
    public var message: String
    public var secondary: Action
    public var primary: Action
    private let accessory: Accessory

    public init(
        title: String, message: String, secondary: Action, primary: Action,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.message = message
        self.secondary = secondary
        self.primary = primary
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: Metrics.Trial.spacing) {
            HStack {
                AppIconView()
                    .frame(width: Metrics.Trial.iconSize, height: Metrics.Trial.iconSize)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.Trial.textInset)
            VStack(alignment: .leading, spacing: Metrics.Trial.textSpacing) {
                Text(title)
                    .textBox(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .textBox(.subheadline)
            }
            .foregroundStyle(Palette.labelPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.Trial.textInset)
            .padding(.bottom, Metrics.Trial.textBottomInset)
            accessory
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metrics.CapsuleButton.largeSpacing) {
                button(secondary, prominence: .secondary)
                button(primary, prominence: .primary)
            }
        }
        .padding(.top, Metrics.Trial.topPadding)
        .padding(.bottom, Metrics.Trial.bottomPadding)
        .padding(.horizontal, Metrics.Trial.horizontalPadding)
        .frame(width: Metrics.Trial.width)
        .glassBackground(.alert, cornerRadius: Metrics.Trial.cornerRadius)
        .accessibilityElement(children: .contain)
    }

    private func button(_ action: Action, prominence: CapsuleButtonStyle.Prominence) -> some View {
        Button(action.title, action: action.perform)
            .buttonStyle(.capsule(prominence))
            .accessibilityHint(action.hint.map { Text($0) } ?? Text(""))
    }
}

extension GlassAlert where Accessory == EmptyView {
    /// An alert with only its text and buttons (Figma 28:132).
    public init(title: String, message: String, secondary: Action, primary: Action) {
        self.init(title: title, message: message, secondary: secondary, primary: primary) { EmptyView() }
    }
}

/// A note on an accent tint under the countdown: who asked for a request from `resolute`
/// (Figma 28:88), with the terminal symbol. VoiceOver reads its text.
public struct GlassAlertNote: View {
    public var text: String
    public var symbol: Symbol

    public init(_ text: String, symbol: Symbol = .terminal) {
        self.text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Metrics.Trial.noteIconSpacing) {
            SymbolIcon(symbol, size: Metrics.Trial.noteIconSize)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(text)
                .textBox(.footnote)
                .foregroundStyle(Palette.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metrics.Trial.noteHorizontalPadding)
        .padding(.vertical, Metrics.Trial.noteVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Trial.noteCornerRadius, style: .continuous)
                .fill(Palette.surfaceAccentTint)
        )
        .accessibilityElement(children: .combine)
    }
}

extension Metrics.Trial {
    /// Above the icon (Figma 28:57).
    public static let topPadding: CGFloat = 20
    /// Below the buttons.
    public static let bottomPadding: CGFloat = 16
    public static let horizontalPadding: CGFloat = 16
    /// Between the icon, the text, the accessory and the buttons.
    public static let spacing: CGFloat = 14
    /// The icon and the text sit 6 points further in than the accessory and the buttons.
    public static let textInset: CGFloat = 6
    /// Between the title and the description.
    public static let textSpacing: CGFloat = 10
    public static let textBottomInset: CGFloat = 2
    /// Between the countdown bar and what is under it.
    public static let countdownSpacing: CGFloat = 8
    /// The requester note (Figma 28:88).
    public static let noteCornerRadius: CGFloat = 10
    public static let noteHorizontalPadding: CGFloat = 10
    public static let noteVerticalPadding: CGFloat = 8
    public static let noteIconSize: CGFloat = 16
    public static let noteIconSpacing: CGFloat = 8
}
