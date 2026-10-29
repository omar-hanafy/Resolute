import SwiftUI

/// A stand-in for the macOS 27 desktop picture, drawn behind panels and dialogs in the
/// gallery so their glass is judged against something like what people see. Never used
/// in the app itself.
///
/// It traces Figma's `Desktop Wallpaper` (Light and Dark): sheets that sweep from the
/// top right to the bottom left, each lit toward its curled edge, with a bright rim and
/// a soft shadow on the sheet below. The wallpaper itself is Apple's artwork from the
/// macOS kit, so it is redrawn here rather than embedded. It fills its frame the way a
/// desktop picture fills a screen, cropping the long side.
public struct WallpaperBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let dark = colorScheme == .dark
        Canvas { context, size in
            Self.draw(in: &context, size: size, dark: dark)
        }
        .accessibilityHidden(true)
    }

    /// The artwork is traced in a 1000 × 649 frame, the wallpaper's 1512 × 982 shape.
    static let artboard = CGSize(width: 1000, height: 649)

    static func draw(in context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let scale = max(size.width / artboard.width, size.height / artboard.height)
        let origin = CGPoint(
            x: (size.width - artboard.width * scale) / 2,
            y: (size.height - artboard.height * scale) / 2
        )
        let place = { (point: CGPoint) in CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: (dark ? WallpaperSheet.groundDark : WallpaperSheet.groundLight).shading(place)
        )
        for sheet in WallpaperSheet.all {
            let edge = sheet.edgePath(place)
            let region = sheet.regionPath(place)

            // The sheet's shadow on the one below, pushed away from the sheet.
            var shadow = context
            shadow.translateBy(x: 6 * scale, y: 9 * scale)
            shadow.addFilter(.blur(radius: 16 * scale))
            shadow.fill(region, with: .color(dark ? .black.opacity(0.65) : Color(red: 0.23, green: 0.16, blue: 0.11).opacity(0.45)))

            context.fill(region, with: (dark ? sheet.dark : sheet.light).shading(place))

            // The curled edge: a soft glow, then a crisp rim.
            var glow = context
            glow.addFilter(.blur(radius: 3 * scale))
            glow.stroke(edge, with: .color(dark ? Color(red: 0.55, green: 0.54, blue: 0.95).opacity(0.55) : .white.opacity(0.8)), lineWidth: 5 * scale)
            context.stroke(edge, with: .color(dark ? Color(red: 0.72, green: 0.71, blue: 1).opacity(0.9) : Color(red: 1, green: 0.99, blue: 0.96)), lineWidth: 1.6 * scale)
        }
    }
}

/// One sheet of the wallpaper: its edge, the corners that close it toward the top left,
/// and its shading in each appearance.
private struct WallpaperSheet {
    /// Points along the edge, from where it leaves the top or right side to where it
    /// leaves the bottom or left side.
    var edge: [CGPoint]
    /// The corners that close the sheet around the top-left of the artboard.
    var closing: [CGPoint]
    var light: Shading
    var dark: Shading

    /// A linear gradient across a sheet, from its shaded side to its lit edge.
    struct Shading {
        var start: CGPoint
        var end: CGPoint
        var colors: [Color]

        func shading(_ place: (CGPoint) -> CGPoint) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: colors), startPoint: place(start), endPoint: place(end))
        }
    }

    func edgePath(_ place: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        Self.addSmoothCurve(through: edge.map(place), to: &path)
        return path
    }

    func regionPath(_ place: (CGPoint) -> CGPoint) -> Path {
        var path = edgePath(place)
        for corner in closing { path.addLine(to: place(corner)) }
        path.closeSubpath()
        return path
    }

    /// A Catmull-Rom curve through the points, as cubic Béziers.
    static func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let before = points[max(index - 1, 0)]
            let from = points[index]
            let to = points[index + 1]
            let after = points[min(index + 2, points.count - 1)]
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + (to.x - before.x) / 6, y: from.y + (to.y - before.y) / 6),
                control2: CGPoint(x: to.x - (after.x - from.x) / 6, y: to.y - (after.y - from.y) / 6)
            )
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The sheet under all the others, on the right.
    static let groundLight = Shading(start: CGPoint(x: 740, y: 640), end: CGPoint(x: 990, y: 320), colors: [rgb(0x5D7385), rgb(0xA9B0B6), rgb(0xE7E3DD)])
    static let groundDark = Shading(start: CGPoint(x: 700, y: 560), end: CGPoint(x: 1000, y: 320), colors: [rgb(0x181B31), rgb(0x343D5E), rgb(0x6C7BA0)])

    /// Bottom to top, so each sheet is drawn over the ones it lies on.
    static let all: [WallpaperSheet] = [
        WallpaperSheet(
            edge: [
                CGPoint(x: 1012, y: 50), CGPoint(x: 975, y: 130), CGPoint(x: 935, y: 200), CGPoint(x: 870, y: 300),
                CGPoint(x: 780, y: 400), CGPoint(x: 715, y: 500), CGPoint(x: 682, y: 600), CGPoint(x: 676, y: 660),
            ],
            closing: [CGPoint(x: -10, y: 660), CGPoint(x: -10, y: -10), CGPoint(x: 1012, y: -10)],
            light: Shading(start: CGPoint(x: 900, y: 150), end: CGPoint(x: 600, y: 640), colors: [rgb(0x9C8C80), rgb(0x7B7A80), rgb(0x6E7E98)]),
            dark: Shading(start: CGPoint(x: 650, y: 220), end: CGPoint(x: 860, y: 330), colors: [rgb(0x101020), rgb(0x161C38), rgb(0x1C2446)])
        ),
        WallpaperSheet(
            edge: [
                CGPoint(x: 1012, y: 22), CGPoint(x: 950, y: 100), CGPoint(x: 895, y: 150), CGPoint(x: 810, y: 200),
                CGPoint(x: 715, y: 250), CGPoint(x: 615, y: 300), CGPoint(x: 540, y: 350), CGPoint(x: 470, y: 400),
                CGPoint(x: 410, y: 450), CGPoint(x: 365, y: 500), CGPoint(x: 330, y: 550), CGPoint(x: 310, y: 600),
                CGPoint(x: 298, y: 660),
            ],
            closing: [CGPoint(x: -10, y: 660), CGPoint(x: -10, y: -10), CGPoint(x: 1012, y: -10)],
            light: Shading(start: CGPoint(x: 850, y: 30), end: CGPoint(x: 330, y: 640), colors: [rgb(0x5E524C), rgb(0xC8BCB2), rgb(0x8A8088), rgb(0x353248)]),
            dark: Shading(start: CGPoint(x: 850, y: 30), end: CGPoint(x: 330, y: 640), colors: [rgb(0x121120), rgb(0x1E2138), rgb(0x23263F), rgb(0x0C0C19)])
        ),
        WallpaperSheet(
            edge: [
                CGPoint(x: 600, y: -12), CGPoint(x: 700, y: 50), CGPoint(x: 728, y: 100), CGPoint(x: 712, y: 150),
                CGPoint(x: 655, y: 200), CGPoint(x: 560, y: 250), CGPoint(x: 420, y: 300), CGPoint(x: 290, y: 350),
                CGPoint(x: 200, y: 400), CGPoint(x: 130, y: 450), CGPoint(x: 75, y: 500), CGPoint(x: 35, y: 550),
                CGPoint(x: 0, y: 602), CGPoint(x: -12, y: 620),
            ],
            closing: [CGPoint(x: -12, y: -12)],
            light: Shading(start: CGPoint(x: 330, y: 120), end: CGPoint(x: 600, y: 250), colors: [rgb(0x6A5240), rgb(0xD8C4B0), rgb(0xF0E9DD)]),
            dark: Shading(start: CGPoint(x: 330, y: 120), end: CGPoint(x: 600, y: 250), colors: [rgb(0x141322), rgb(0x34344F), rgb(0x48476E)])
        ),
        WallpaperSheet(
            edge: [
                CGPoint(x: 245, y: -12), CGPoint(x: 330, y: 50), CGPoint(x: 355, y: 100), CGPoint(x: 340, y: 150),
                CGPoint(x: 300, y: 200), CGPoint(x: 250, y: 250), CGPoint(x: 195, y: 300), CGPoint(x: 145, y: 350),
                CGPoint(x: 100, y: 400), CGPoint(x: 60, y: 450), CGPoint(x: 30, y: 500), CGPoint(x: 12, y: 550),
                CGPoint(x: 0, y: 598), CGPoint(x: -12, y: 615),
            ],
            closing: [CGPoint(x: -12, y: -12)],
            light: Shading(start: CGPoint(x: 60, y: 60), end: CGPoint(x: 240, y: 300), colors: [rgb(0x7A5A40), rgb(0xC2A88C), rgb(0xECE0CA)]),
            dark: Shading(start: CGPoint(x: 60, y: 60), end: CGPoint(x: 240, y: 330), colors: [rgb(0x1C1B2E), rgb(0x343352), rgb(0x504E78)])
        ),
    ]
}
