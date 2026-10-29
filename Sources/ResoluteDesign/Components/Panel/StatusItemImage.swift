import AppKit

/// The image on Resolute's status item button (Figma: Components › Status Item, 17:135):
/// the display symbol, alone or with the current resolution, an orange countdown while a
/// hidden mode is on trial, or an orange hourglass while a revert waits for its display.
///
/// The monochrome states are template images, so macOS draws them in the menu bar's own
/// color over light and dark wallpapers. The trial and waiting states carry orange, so they
/// are drawn in color, resolved against the appearance they are drawn in. Every image
/// includes Figma's 7-point side padding: give the status item a fixed length of
/// `size.width`, so the button doesn't pad it again.
public struct StatusItemImage: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        /// The display symbol on its own (Figma: Normal).
        case symbol
        /// The symbol and the current resolution: "1728 × 1117".
        case resolution(String)
        /// A hidden mode on trial: an orange capsule with the time left, "0:12".
        case trial(secondsLeft: Int)
        /// A revert waiting for its display to reconnect: the symbol and an orange hourglass.
        case waiting
    }

    public var content: Content
    /// Whether the panel is showing (Figma: Open), drawn as Figma's capsule behind the
    /// content. macOS draws its own highlight on a highlighted status item button, so use
    /// this only where nothing else does; the width stays the same either way, so the menu
    /// bar doesn't shift as the panel opens.
    public var isOpen: Bool
    /// Figma's 24-point status item by default. Pass `NSStatusBar.system.thickness` when the
    /// menu bar is shorter, so the button doesn't scale the image down.
    public var height: CGFloat

    public init(_ content: Content = .symbol, isOpen: Bool = false, height: CGFloat = Metrics.MenuBar.statusItemHeight) {
        self.content = content
        self.isOpen = isOpen
        self.height = height
    }

    /// Whether macOS should tint the image for the menu bar: every state but the colored
    /// trial and waiting ones.
    public var isTemplate: Bool {
        switch content {
        case .symbol, .resolution: true
        case .trial, .waiting: false
        }
    }

    /// The text next to the symbol, if any: the resolution, or the trial's time left.
    public var text: String? {
        switch content {
        case .symbol, .waiting: nil
        case .resolution(let resolution): resolution
        case .trial(let secondsLeft): Self.countdown(secondsLeft: secondsLeft)
        }
    }

    /// The image's size in points: Figma's 32 points wide for the symbol, 49 with the
    /// hourglass, and wider by the text and a 5-point gap when there is text.
    public var size: CGSize {
        var width = Layout.sidePadding * 2 + Layout.symbolBox
        if let text {
            width += Layout.gap + ceil(attributedText(text, color: nil).size().width)
        }
        if content == .waiting {
            width += Layout.gap + Layout.hourglassBox
        }
        return CGSize(width: width, height: height)
    }

    /// What VoiceOver reads for the status item.
    public var accessibilityDescription: String {
        switch content {
        case .symbol:
            "Resolute"
        case .resolution(let resolution):
            "Resolute, \(PanelSpeech.text(resolution))"
        case .trial(let secondsLeft):
            "Resolute, hidden mode on trial, \(Self.spokenTime(secondsLeft: secondsLeft)) left"
        case .waiting:
            "Resolute, a revert is waiting for its display"
        }
    }

    /// The image to put on the status item button. It draws itself each time AppKit draws
    /// it, so its colors follow the menu bar's appearance.
    public func nsImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = isTemplate
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// The trial's time left as the status item shows it: minutes and two-digit seconds,
    /// "0:12" or "1:05". Never negative.
    public static func countdown(secondsLeft: Int) -> String {
        let seconds = max(0, secondsLeft)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    // MARK: - Drawing

    /// Figma's status item geometry (17:135).
    enum Layout {
        static let sidePadding: CGFloat = 7
        static let symbolBox: CGFloat = 18
        /// The 13-point glyph matches Figma's display symbol in its 18-point frame.
        static let symbolPointSize: CGFloat = 13
        static let gap: CGFloat = 5
        static let hourglassBox: CGFloat = 12
        static let hourglassPointSize: CGFloat = 8.5
        /// Half a point under the menu bar's 13-point clock, as Figma sets it.
        static let textSize: CGFloat = 12.5
        static let openFillAlpha: CGFloat = 0.26
        static let openStrokeAlpha: CGFloat = 0.45
        static let openStrokeWidth: CGFloat = 0.5
    }

    private func draw(in rect: NSRect) {
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        // A template image is a mask: only its alpha counts, so it is drawn opaque. The
        // colored states take the menu bar's label color from the appearance being drawn.
        let ink: NSColor
        switch content {
        case .trial:
            Self.resolved(.systemOrange).setFill()
            capsule.fill()
            // Figma's near-black on the orange, in either menu bar appearance.
            ink = Self.resolved(.labelColor, in: .aqua)
        case .symbol, .resolution:
            ink = .black
        case .waiting:
            ink = Self.resolved(.labelColor).withAlphaComponent(1)
        }
        // The trial's orange capsule already marks the item.
        if isOpen, !isTrial {
            ink.withAlphaComponent(Layout.openFillAlpha).setFill()
            capsule.fill()
            let edge = NSBezierPath(
                roundedRect: rect.insetBy(dx: Layout.openStrokeWidth / 2, dy: Layout.openStrokeWidth / 2),
                xRadius: (rect.height - Layout.openStrokeWidth) / 2,
                yRadius: (rect.height - Layout.openStrokeWidth) / 2
            )
            edge.lineWidth = Layout.openStrokeWidth
            ink.withAlphaComponent(Layout.openStrokeAlpha).setStroke()
            edge.stroke()
        }

        var x = rect.minX + Layout.sidePadding
        Self.drawSymbol(
            .display, pointSize: Layout.symbolPointSize, color: ink,
            centeredIn: NSRect(x: x, y: rect.midY - Layout.symbolBox / 2, width: Layout.symbolBox, height: Layout.symbolBox)
        )
        x += Layout.symbolBox
        if let text {
            x += Layout.gap
            let string = attributedText(text, color: ink)
            string.draw(at: NSPoint(x: x, y: (rect.midY - string.size().height / 2).rounded()))
        }
        if content == .waiting {
            x += Layout.gap
            Self.drawSymbol(
                .hourglass, pointSize: Layout.hourglassPointSize, color: Self.resolved(.systemOrange),
                centeredIn: NSRect(x: x, y: rect.midY - Layout.hourglassBox / 2, width: Layout.hourglassBox, height: Layout.hourglassBox)
            )
        }
    }

    private var isTrial: Bool {
        if case .trial = content { return true }
        return false
    }

    /// The trial counts down in figures of one width, so the item doesn't twitch each second.
    private func attributedText(_ text: String, color: NSColor?) -> NSAttributedString {
        let font: NSFont = isTrial
            ? .monospacedDigitSystemFont(ofSize: Layout.textSize, weight: .bold)
            : .systemFont(ofSize: Layout.textSize, weight: .medium)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        attributes[.foregroundColor] = color
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Draws the symbol's monochrome glyph in `color`. Drawn as it comes, or with a palette
    /// color, the display symbol's screen is filled in.
    private static func drawSymbol(_ symbol: Symbol, pointSize: CGFloat, color: NSColor, centeredIn box: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(.preferringMonochrome())
        guard let image = symbol.nsImage()?.withSymbolConfiguration(configuration),
              let context = NSGraphicsContext.current?.cgContext else { return }
        let size = image.size
        // On whole points, so the glyph stays sharp on a 1× display.
        let rect = NSRect(
            x: (box.midX - size.width / 2).rounded(), y: (box.midY - size.height / 2).rounded(),
            width: size.width, height: size.height
        )
        // In a transparency layer, the fill colors only the glyph's own pixels.
        context.saveGState()
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// `color` as the current drawing appearance shows it, or as `appearance` shows it.
    private static func resolved(_ color: NSColor, in appearance: NSAppearance.Name? = nil) -> NSColor {
        guard let appearance, let named = NSAppearance(named: appearance) else {
            return color.usingColorSpace(.sRGB) ?? color
        }
        var resolved = color
        named.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    /// "12 seconds", "1 minute, 5 seconds".
    static func spokenTime(secondsLeft: Int) -> String {
        Duration.seconds(max(0, secondsLeft)).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
