import AppKit
import SwiftUI

/// The macOS type scale from Figma's `macOS/*` text styles, in SF Pro (Figma draws them
/// in Inter as a stand-in, so its letter spacing is not carried over) and SF Mono.
public enum TextStyle: String, CaseIterable, Sendable {
    case largeTitle
    case title1
    case title2
    case title3
    case headline
    case body
    case bodyMedium
    case bodyEmphasized
    case callout
    case calloutEmphasized
    case subheadline
    case subheadlineEmphasized
    case footnote
    /// `macOS/Footnote Emphasized`: badges, shortcut keys and banner actions. Figma's
    /// type-scale frame leaves it out, but the components use it.
    case footnoteEmphasized
    case caption
    case mono

    public var pointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title1: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body, .bodyMedium, .bodyEmphasized: 13
        case .callout, .calloutEmphasized, .mono: 12
        case .subheadline, .subheadlineEmphasized: 11
        case .footnote, .footnoteEmphasized, .caption: 10
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .largeTitle, .title1, .headline: .bold
        case .title2, .title3, .bodyEmphasized, .calloutEmphasized, .subheadlineEmphasized, .footnoteEmphasized: .semibold
        case .bodyMedium, .caption: .medium
        case .body, .callout, .subheadline, .footnote, .mono: .regular
        }
    }

    /// The line height Figma gives the style, in points.
    public var lineHeight: CGFloat {
        switch self {
        case .largeTitle: 32
        case .title1: 26
        case .title2: 22
        case .title3: 20
        case .headline, .body, .bodyMedium, .bodyEmphasized: 16
        case .callout, .calloutEmphasized: 15
        case .subheadline, .subheadlineEmphasized: 14
        case .footnote, .footnoteEmphasized, .caption: 13
        case .mono: 18
        }
    }

    public var isMonospaced: Bool { self == .mono }

    public var font: Font {
        .system(size: pointSize, weight: weight, design: isMonospaced ? .monospaced : .default)
    }

    public var nsFont: NSFont {
        isMonospaced
            ? .monospacedSystemFont(ofSize: pointSize, weight: weight.nsWeight)
            : .systemFont(ofSize: pointSize, weight: weight.nsWeight)
    }

    /// The extra space between lines that gives the font Figma's line height. Where the
    /// font's own line is already taller (Title 1), there is none.
    public var lineSpacing: CGFloat {
        max(0, lineHeight - naturalLineHeight)
    }

    /// The height of one line of the font as SwiftUI lays it out on this Mac. `Text`
    /// spaces lines like AppKit's string drawing without the font's leading, which rounds
    /// the font's ascent and descent its own way (a 13-point line is 16 points, a 15-point
    /// one 19), so this measures rather than adds them up.
    public var naturalLineHeight: CGFloat {
        Self.naturalLineHeights[self] ?? lineHeight
    }

    private static let naturalLineHeights: [TextStyle: CGFloat] = Dictionary(
        uniqueKeysWithValues: allCases.map { style in
            let line = NSAttributedString(string: "Hg", attributes: [.font: style.nsFont])
            let bounds = line.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]
            )
            return (style, bounds.height)
        }
    )
}

extension View {
    /// Sets the font and line height of a Figma `macOS/*` text style.
    public func textStyle(_ style: TextStyle) -> some View {
        font(style.font).lineSpacing(style.lineSpacing)
    }

    /// Sets a Figma text style and gives the text the height of its Figma text box.
    ///
    /// Figma centers every line in its line height, so a text box is a whole number of
    /// lines tall; SwiftUI adds the extra space only between lines. Half of it above the
    /// first line and below the last puts stacked text where Figma puts it.
    public func textBox(_ style: TextStyle) -> some View {
        textStyle(style).padding(.vertical, style.lineSpacing / 2)
    }
}

extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
