import SwiftUI

/// The panel that opens from the menu bar (Figma: Panel / Two Displays, 20:156): its
/// sections stacked 8 points apart, 340 points wide, on glass with 22-point corners.
///
/// The window that hosts it draws the shadow. Where the system already draws the panel's
/// material (a status item's expanded interface on macOS 27), pass `drawsBackground: false`.
public struct PanelSurface<Content: View>: View {
    public var drawsBackground: Bool
    private let content: Content

    public init(drawsBackground: Bool = true, @ViewBuilder content: () -> Content) {
        self.drawsBackground = drawsBackground
        self.content = content()
    }

    public var body: some View {
        let stack = VStack(alignment: .leading, spacing: Metrics.Panel.sectionSpacing) {
            content
        }
        .padding(.horizontal, Metrics.Panel.padding)
        .padding(.vertical, PanelMetrics.surfaceVerticalPadding)
        .frame(width: Metrics.Panel.width, alignment: .leading)
        if drawsBackground {
            stack.glassBackground(.panel, cornerRadius: Metrics.Panel.cornerRadius)
        } else {
            stack
        }
    }
}

/// The top of the panel: "Resolute" and the button that opens the Resolute window
/// (Figma 20:160).
public struct PanelHeader: View {
    public var title: String
    public var openWindow: () -> Void

    public init(title: String = "Resolute", openWindow: @escaping () -> Void) {
        self.title = title
        self.openWindow = openWindow
    }

    public var body: some View {
        HStack(spacing: Metrics.Spacing.medium) {
            Text(title)
                .panelTextStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            PanelCircleButton(symbol: .macwindow, iconSize: .header, label: "Open Resolute Window", action: openWindow)
        }
        .padding(.leading, Metrics.Spacing.small)
        .padding(.trailing, Metrics.Spacing.xxSmall)
        .padding(.vertical, Metrics.Spacing.xxSmall)
    }
}

/// A full-width hairline between groups in the panel (Figma: Separator, `Labels/Quaternary`).
public struct PanelSeparator: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Palette.labelQuaternary)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Small print in the panel: the explanation under Show Hidden Modes, and the hint about ⌥
/// at the bottom of All Resolutions (Figma 22:445, 22:476).
public struct PanelFootnote: View {
    public enum Tone: Sendable {
        /// `Labels/Secondary`: an explanation that goes with a control.
        case secondary
        /// `Labels/Tertiary`: a hint at the bottom of the panel.
        case tertiary
    }

    public var text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone = .secondary) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .panelTextStyle(.footnote)
            .foregroundStyle(tone == .secondary ? Palette.labelSecondary : Palette.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
