import SwiftUI

/// A small picture of a desktop at one of the five "Larger Text ↔ More Space" sizes
/// (Figma: Components › Space Thumbnail). Stop 1 has the largest window; stop 5 the most
/// room around it. Drawn at any size in Figma's 100 × 64 frame.
///
/// The picture scales with the frame, as Figma's instances do, but its 7-point corners and
/// its edge keep their size. Selected draws a 2-point ring in the accent color just
/// outside the frame, so a container must leave 2 points around it rather than clip.
/// VoiceOver skips the picture: the control that shows it names the size.
///
/// Contract (Wave 0): the type, `Tone`, `init(stop:tone:isSelected:)` and the 100 × 64 frame
/// stay.
public struct SpaceThumbnail: View {
    public enum Tone: String, CaseIterable, Sendable {
        /// The built-in display's wallpaper.
        case violet
        /// An external display's wallpaper.
        case teal
    }

    public static let aspectRatio: CGFloat = 100.0 / 64.0
    public static let stops = 1...5

    public var stop: Int
    public var tone: Tone
    public var isSelected: Bool

    public init(stop: Int, tone: Tone, isSelected: Bool) {
        self.stop = min(max(stop, Self.stops.lowerBound), Self.stops.upperBound)
        self.tone = tone
        self.isSelected = isSelected
    }

    public var body: some View {
        Canvas { [stop, tone, isSelected] context, size in
            Self.draw(stop: stop, tone: tone, withEdge: !isSelected, in: &context, size: size)
        }
        .overlay {
            if isSelected {
                // Figma: the frame's 2-point outside stroke in Accents/Blue.
                RoundedRectangle(cornerRadius: Layout.cornerRadius + Layout.ringWidth, style: .circular)
                    .strokeBorder(Palette.accent, lineWidth: Layout.ringWidth)
                    .padding(-Layout.ringWidth)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Draws the wallpaper, the window and its contents, scaled from the 100 × 64 frame to
    /// `size`, and the unselected edge.
    nonisolated private static func draw(
        stop: Int,
        tone: Tone,
        withEdge: Bool,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        let scale = CGAffineTransform(scaleX: size.width / 100, y: size.height / 64)
        let layout = Layout(stop: stop)

        context.fill(
            Path(roundedRect: bounds, cornerRadius: Layout.cornerRadius, style: .circular),
            with: .linearGradient(
                Gradient(stops: tone.wallpaper),
                startPoint: Layout.wallpaperStart.applying(scale),
                endPoint: Layout.wallpaperEnd.applying(scale)
            )
        )
        context.fill(
            Path(roundedRect: layout.window, cornerRadius: layout.windowCornerRadius, style: .circular).applying(scale),
            with: .color(Paint.window)
        )
        for (light, color) in zip(layout.lights, Paint.lights) {
            context.fill(Path(ellipseIn: light).applying(scale), with: .color(color))
        }
        for line in layout.lines {
            context.fill(
                Path(roundedRect: line, cornerRadius: line.height / 2, style: .circular).applying(scale),
                with: .color(Paint.text)
            )
        }
        if withEdge {
            let inset = Layout.edgeWidth / 2
            context.stroke(
                Path(
                    roundedRect: bounds.insetBy(dx: inset, dy: inset),
                    cornerRadius: Layout.cornerRadius - inset,
                    style: .circular
                ),
                with: .color(Paint.edge),
                lineWidth: Layout.edgeWidth
            )
        }
    }
}

extension SpaceThumbnail {
    /// Figma's drawing of a stop, in the 100 × 64 frame. Every stop scales one window from
    /// the same top-left corner, (7, 8): by 0.9 at stop 1 down to 0.51 at stop 5.
    struct Layout: Equatable {
        /// The window's scale at stops 1 to 5.
        static let scales: [CGFloat] = [0.90, 0.79, 0.69, 0.60, 0.51]
        /// The ends of the wallpaper's gradient.
        static let wallpaperStart = CGPoint(x: 0, y: 0)
        static let wallpaperEnd = CGPoint(x: 58.1158, y: 90.8059)
        /// The picture's corner radius, in points at every size: Figma's instances scale
        /// their contents but not their corners or strokes.
        static let cornerRadius: CGFloat = 7
        /// The selected ring's width, outside the frame.
        static let ringWidth: CGFloat = 2
        /// The unselected edge's width, inside the frame.
        static let edgeWidth: CGFloat = 0.5

        var window: CGRect
        var windowCornerRadius: CGFloat
        /// The close, minimize and zoom buttons, left to right.
        var lights: [CGRect]
        /// Five lines of text, long and short in turn.
        var lines: [CGRect]

        init(stop: Int) {
            let scale = Self.scales[min(max(stop, 1), Self.scales.count) - 1]
            window = CGRect(x: 7, y: 8, width: 90 * scale, height: 54 * scale)
            windowCornerRadius = 3 + 3 * scale
            let left = 7 + 6 * scale
            let diameter = 3.2 * scale
            lights = (0..<3).map { index in
                CGRect(
                    x: left + 5 * scale * CGFloat(index) - diameter / 2,
                    y: 8 + 5.5 * scale - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            }
            lines = (0..<5).map { index in
                CGRect(
                    x: left,
                    y: 8 + 12 * scale + 8.5 * scale * CGFloat(index),
                    width: (index.isMultiple(of: 2) ? 65.52 : 46.8) * scale,
                    height: 3.6 * scale
                )
            }
        }
    }
}

extension SpaceThumbnail.Tone {
    /// The wallpaper's gradient from Figma, top left to bottom right.
    var wallpaper: [Gradient.Stop] {
        switch self {
        case .violet:
            [
                Gradient.Stop(color: Paint.srgb(0x3F7DFF), location: 0),
                Gradient.Stop(color: Paint.srgb(0x8A5CF6), location: 0.6),
                Gradient.Stop(color: Paint.srgb(0xFF7A59), location: 1),
            ]
        case .teal:
            [
                Gradient.Stop(color: Paint.srgb(0x0F9B8E), location: 0),
                Gradient.Stop(color: Paint.srgb(0x2CC48C), location: 0.6),
                Gradient.Stop(color: Paint.srgb(0x9BF08A), location: 1),
            ]
        }
    }
}

/// The picture's own colors, from Figma. They are part of the picture, like the colors of
/// a photo, so they are the same in Light and Dark; only the selection ring is a UI color.
private enum Paint {
    static let window = Color(.sRGB, white: 1, opacity: 0.95)
    static let text = Color(.sRGB, white: 0, opacity: 0.18)
    static let edge = Color(.sRGB, white: 0, opacity: 0.18)
    /// Close, minimize and zoom.
    static let lights = [srgb(0xFF5F57), srgb(0xFEBC2E), srgb(0x28C840)]

    static func srgb(_ rgb: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
