import AppKit
import SwiftUI

/// The SF Symbols the design uses (Figma's Foundations › Icon Sheet). Use these rather than
/// symbol-name strings, so a typo can't draw nothing.
public enum Symbol: String, CaseIterable, Sendable {
    case display
    case display2 = "display.2"
    case laptopcomputer
    case desktopcomputer
    case tv
    case gearshape
    case macwindow
    case rectangleOnRectangle = "rectangle.on.rectangle"
    case rectangleOnRectangleSlash = "rectangle.on.rectangle.slash"
    case plusRectangleOnRectangle = "plus.rectangle.on.rectangle"
    case rectangleBadgePlus = "rectangle.badge.plus"
    case power
    case chevronRight = "chevron.right"
    case chevronLeft = "chevron.left"
    case chevronDown = "chevron.down"
    case chevronUpChevronDown = "chevron.up.chevron.down"
    case checkmark
    case terminal
    case arrowUturnBackward = "arrow.uturn.backward"
    case plus
    case minus
    case textformatSize = "textformat.size"
    case rectangleExpandDiagonal = "rectangle.expand.diagonal"
    case exclamationmarkTriangle = "exclamationmark.triangle"
    case exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
    case clock
    case clockArrowCirclepath = "clock.arrow.circlepath"
    case infoCircle = "info.circle"
    case infoCircleFill = "info.circle.fill"
    case lock
    case lockFill = "lock.fill"
    case folder
    case trash
    case sparkles
    case keyboard
    case command
    case sliderHorizontal3 = "slider.horizontal.3"
    case arrowTriangle2Circlepath = "arrow.triangle.2.circlepath"
    case photo
    case pencil
    case magnifyingglass
    case eye
    case eyeSlash = "eye.slash"
    case ellipsis
    case ellipsisCircle = "ellipsis.circle"
    case questionmarkCircle = "questionmark.circle"
    case xmark
    case xmarkCircleFill = "xmark.circle.fill"
    case arrowCounterclockwise = "arrow.counterclockwise"
    case listBullet = "list.bullet"
    case checkmarkCircleFill = "checkmark.circle.fill"
    case docOnDoc = "doc.on.doc"
    case star
    case starFill = "star.fill"
    case rectangleStack = "rectangle.stack"
    case menubarRectangle = "menubar.rectangle"
    case dockRectangle = "dock.rectangle"
    case wifi
    case switch2 = "switch.2"
    case hourglass
    case timer
    case arrowClockwise = "arrow.clockwise"
    case arrowLeftArrowRight = "arrow.left.arrow.right"
    case arrowDownCircle = "arrow.down.circle"
    case docText = "doc.text"
    case link
    case handRaised = "hand.raised"
    case lockShield = "lock.shield"
    case squareDashed = "square.dashed"
    case appleLogo = "apple.logo"
    case arrowDownToLine = "arrow.down.to.line"
    case displayTrianglebadgeExclamationmark = "display.trianglebadge.exclamationmark"
    case sidebarLeft = "sidebar.left"
    case rectangleDashed = "rectangle.dashed"

    /// The symbol's name in SF Symbols.
    public var name: String { rawValue }

    /// The symbol as an AppKit image; nil only if this macOS lacks it.
    public func nsImage(accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: rawValue, accessibilityDescription: accessibilityDescription)
    }
}

extension Symbol {
    /// The point size that draws a symbol as large as Figma's icons in a square frame
    /// `side` points wide. The kit's icons are SF Pro glyphs set at 13 points in an
    /// 18-point frame and scaled with the frame, so a 16-point frame holds an 11.6-point
    /// glyph and the HUD's 48-point frame a 34.7-point one.
    public static func pointSize(inFrame side: CGFloat) -> CGFloat {
        side * 13 / 18
    }
}

extension Image {
    public init(symbol: Symbol) {
        self.init(systemName: symbol.rawValue)
    }
}

/// A symbol drawn like Figma's icon components: centered in a square frame, at the size
/// that frame implies, in one color. Color it with `foregroundStyle`; it is decorative
/// unless given an accessibility label.
public struct SymbolIcon: View {
    public var symbol: Symbol
    /// The side of the square frame, as Figma sizes the icon.
    public var size: CGFloat
    public var weight: Font.Weight

    public init(_ symbol: Symbol, size: CGFloat, weight: Font.Weight = .regular) {
        self.symbol = symbol
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Image(symbol: symbol)
            // Some symbols prefer a hierarchical look (display's screen in a lighter
            // shade); Figma's icons are one color.
            .symbolRenderingMode(.monochrome)
            .font(.system(size: Symbol.pointSize(inFrame: size), weight: weight))
            .frame(width: size, height: size)
    }
}
