import AppKit
import SwiftUI

/// Figma's panel geometry that `Metrics` doesn't name (Components › Menu Bar Panel, 50:706).
enum PanelMetrics {
    /// The panel's top and bottom padding; `Metrics.Panel.padding` is the sides.
    static let surfaceVerticalPadding: CGFloat = 10
    /// The round buttons in the panel: the window button, Back and Save Current Setup.
    static let circleButtonSize: CGFloat = 26
    /// A panel row's and a mode row's content: 8 points in on the left, 10 on the right.
    static let rowInsets = EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 10)
    /// The display's picture next to its name in All Resolutions.
    static let headerPictureSize = CGSize(width: 32, height: 24)
    /// A pop-up button's height in Figma's macOS 27 kit (`Global/Height`). Rows keep it
    /// where macOS draws its controls shorter.
    static let controlHeight: CGFloat = 24
    /// A display that isn't responding is drawn at this opacity (Figma 24:1157).
    static let unavailableOpacity: Double = 0.55

    enum Card {
        static let insets = EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12)
        /// Between the card's parts, and between the picture and the name.
        static let spacing: CGFloat = 10
        static let pictureSize = CGSize(width: 48, height: 36)
        /// Figma draws a Retina-style card 200 points tall (Display Card, 18:27), so the
        /// cards of two displays line up.
        static let stopsHeight: CGFloat = 200
        /// All Resolutions sits 8 points under the card's hairline, 2 above its padding.
        static let allResolutionsInsets = EdgeInsets(top: 8, leading: 0, bottom: 2, trailing: 0)
    }

    enum Segments {
        /// 3 points above and below a 15-point line.
        static let height: CGFloat = 21
        /// The track's inset around the segments.
        static let inset: CGFloat = 2
        static let horizontalPadding: CGFloat = 10
    }

    enum PopUpRow {
        static let insets = EdgeInsets(top: 4, leading: 8, bottom: 2, trailing: 4)
    }

    enum Offer {
        static let insets = EdgeInsets(top: 9, leading: 10, bottom: 10, trailing: 8)
        static let spacing: CGFloat = 10
        static let cornerRadius: CGFloat = 10
    }

    enum Banner {
        static let insets = EdgeInsets(top: 9, leading: 10, bottom: 10, trailing: 12)
        static let spacing: CGFloat = 9
        static let textSpacing: CGFloat = 3
        static let cornerRadius: CGFloat = 12
    }

    enum Chip {
        static let insets = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 10)
    }

    enum Presets {
        /// Figma's Section Label (17:61) pads its title like this.
        static let labelInsets = EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10)
        static let chipSpacing: CGFloat = 6
    }

    enum Activity {
        static let insets = EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 12)
        static let spacing: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let cornerRadius: CGFloat = 12
    }

    enum ModeList {
        static let padding: CGFloat = 8
        static let spacing: CGFloat = 2
        /// With the rows' spacing, 8 points between the tabs and the first row.
        static let gapBelowTabs: CGFloat = 4
    }

    enum ModeRow {
        static let spacing: CGFloat = 10
        static let cornerRadius: CGFloat = 7
        /// The outline's frame, and the largest outline in it.
        static let outlineFrame = CGSize(width: 20, height: 14)
        static let outlineBox = CGSize(width: 18, height: 11)
        static let outlineLineWidth: CGFloat = 1.5
        static let outlineCornerRadius: CGFloat = 2.5
        static let outlineDash: [CGFloat] = [3, 2]
    }
}

/// Colors the panel needs that `Palette` doesn't name yet.
enum PanelPalette {
    /// `Labels/White`: text and symbols on the accent fill of a highlighted row, a selected
    /// mode and the active preset.
    static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    /// The selected segment's drop shadow (Figma: 0, 1, blur 1, black at 18%).
    static let segmentShadow = Color(nsColor: .shadowColor).opacity(0.18)
}

/// An SF Symbol drawn the way Figma draws the panel's icons: in one of its icon frames,
/// with the glyph at the point size that matches Figma's artwork.
struct PanelIcon: View {
    enum Size {
        /// Rows, the activity row and Refresh Rate: an 18-point frame and a 13-point glyph,
        /// the body text's size.
        case row
        /// The waiting banner and the offer: 16-point frame.
        case notice
        /// The window button in the header: 15-point frame.
        case header
        /// Preset stars and the selected mode's checkmark: 14-point frame.
        case small
        /// Chevrons and the plus in round buttons, and a card's chevron: 14-point frame.
        case button
        /// Trailing chevrons: 12-point frame.
        case trailing
        /// The offer's dismiss button: 11-point frame.
        case dismiss

        var frame: CGFloat {
            switch self {
            case .row: 18
            case .notice: 16
            case .header: 15
            case .small, .button: 14
            case .trailing: 12
            case .dismiss: 11
            }
        }

        var pointSize: CGFloat {
            switch self {
            case .row: 13
            case .notice: 11.5
            case .header, .small: 10
            case .button: 9.5
            case .trailing: 8.5
            case .dismiss: 8
            }
        }
    }

    var symbol: Symbol
    var size: Size

    init(_ symbol: Symbol, size: Size) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(symbol: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size.pointSize))
            .frame(width: size.frame, height: size.frame)
    }
}

/// A round button in the panel: the window button, Back, and Save Current Setup
/// (Figma: 26-point circle on `surface/track`).
struct PanelCircleButton: View {
    var symbol: Symbol
    var iconSize: PanelIcon.Size
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PanelIcon(symbol, size: iconSize)
                .foregroundStyle(Palette.labelSecondary)
                .frame(width: PanelMetrics.circleButtonSize, height: PanelMetrics.circleButtonSize)
                .background(Circle().fill(Palette.surfaceTrack))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

extension View {
    /// A text style's font, with the line height SwiftUI gives it, which is already Figma's
    /// (16 points at 13, 15 at 12, 14 at 11, 13 at 10). `textStyle(_:)` adds its
    /// `lineSpacing` on top, which spreads the lines of the panel's two- and three-line
    /// notes a point or two further apart than Figma.
    func panelTextStyle(_ style: TextStyle) -> some View {
        font(style.font)
    }

    /// `panelTextStyle(_:)` in another weight: Figma's `macOS/Footnote Emphasized` is the
    /// footnote style in semibold.
    func panelTextStyle(_ style: TextStyle, weight: Font.Weight) -> some View {
        font(style.font.weight(weight))
    }
}

/// Text as VoiceOver should read it.
enum PanelSpeech {
    /// Reads sizes with "by" ("×" is read as "multiplied by"), a scale like "1×" as "1x",
    /// "→" as "to" and a "·" separator as a pause: "1728 × 1117 · 120 Hz" becomes
    /// "1728 by 1117, 120 Hz".
    static func text(_ text: String) -> String {
        text.replacingOccurrences(of: #"(\d)\s*×\s*(\d)"#, with: "$1 by $2", options: .regularExpression)
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: #"\s*→\s*"#, with: " to ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+·\s+"#, with: ", ", options: .regularExpression)
    }
}
