import AppKit
import SwiftUI

/// Resolute's colors, as SwiftUI colors. Every one adapts to Light and Dark.
///
/// Labels, accents and the window background are the macOS system colors that the Figma
/// kit mirrors (`Labels/Primary (kit)` is `labelColor`, and so on), so they also follow
/// Increase Contrast and the person's accent color. The surfaces and strokes are
/// Resolute's own collection in Figma (`surface/card`, `stroke/hairline`, …), with the
/// Light and Dark values given there. `NSPalette` has the same colors for AppKit.
public enum Palette {
    // MARK: Labels (kit)

    public static let labelPrimary = Color(nsColor: .labelColor)
    public static let labelSecondary = Color(nsColor: .secondaryLabelColor)
    public static let labelTertiary = Color(nsColor: .tertiaryLabelColor)
    public static let labelQuaternary = Color(nsColor: .quaternaryLabelColor)
    /// `Labels/White`: text and symbols on an accent fill (the primary button, the
    /// selected mode, the active preset).
    public static let labelWhite = Color(nsColor: .alternateSelectedControlTextColor)

    // MARK: Fills (kit)

    public static let fillPrimary = Color(nsColor: NSPalette.fillPrimary)
    public static let fillSecondary = Color(nsColor: NSPalette.fillSecondary)
    /// `Fills - Vibrant/Secondary`: a secondary button on glass, like Keep in the trial dialog.
    public static let fillVibrantSecondary = Color(nsColor: NSPalette.fillVibrantSecondary)

    // MARK: Accents (kit)

    /// The person's accent color: selection, primary buttons, the chosen size.
    public static let accent = Color(nsColor: .controlAccentColor)
    public static let blue = Color(nsColor: .systemBlue)
    public static let orange = Color(nsColor: .systemOrange)
    public static let green = Color(nsColor: .systemGreen)
    public static let red = Color(nsColor: .systemRed)

    public static let windowBackground = Color(nsColor: .windowBackgroundColor)

    // MARK: Progress bars (kit)

    /// The unfilled track of a progress bar: `Labels/Primary` at 10%, as the kit draws it.
    public static let progressTrack = Color(nsColor: NSPalette.progressTrack)
    /// `Miscellaneous/Progress Bars/Track - Stroke`: the hairline around the track.
    public static let progressTrackStroke = Color(nsColor: NSPalette.progressTrackStroke)

    // MARK: Surfaces (Resolute)

    /// `surface/card`: a display card in the panel, and other raised cards.
    public static let surfaceCard = Color(nsColor: NSPalette.surfaceCard)
    /// `surface/selected-control`: the selected segment of a segmented control.
    public static let surfaceSelectedControl = Color(nsColor: NSPalette.surfaceSelectedControl)
    /// `surface/track`: the track behind segments and switches.
    public static let surfaceTrack = Color(nsColor: NSPalette.surfaceTrack)
    /// `surface/row-hover`: a highlighted panel row.
    public static let surfaceRowHover = Color(nsColor: NSPalette.surfaceRowHover)
    /// `surface/sidebar-selection`: the selected sidebar item.
    public static let surfaceSidebarSelection = Color(nsColor: NSPalette.surfaceSidebarSelection)
    /// `surface/group`: a grouped form or table in the window.
    public static let surfaceGroup = Color(nsColor: NSPalette.surfaceGroup)
    /// `surface/warning-tint`: behind warnings and hidden modes.
    public static let surfaceWarningTint = Color(nsColor: NSPalette.surfaceWarningTint)
    /// Orange text, such as Unsaved and Hidden: darker than `Accents/Orange` in Light, so it
    /// reads at 4.5:1 or more on light surfaces and the warning tint. Symbols stay orange.
    public static let warningText = Color(nsColor: NSPalette.warningText)
    /// `surface/accent-tint`: behind information, and the active preset.
    public static let surfaceAccentTint = Color(nsColor: NSPalette.surfaceAccentTint)

    // MARK: Strokes (Resolute)

    /// `stroke/hairline`: dividers and outlines.
    public static let strokeHairline = Color(nsColor: NSPalette.strokeHairline)
    /// `stroke/window-edge`: the edge of the panel and of floating windows.
    public static let strokeWindowEdge = Color(nsColor: NSPalette.strokeWindowEdge)

    // MARK: Shadows

    /// The shadow under the selected segment (Figma: 0, 1, blur 1, black 18%).
    public static let shadowSelectedControl = Color(nsColor: NSPalette.shadowSelectedControl)
}

/// `Palette`'s colors for AppKit. Each access returns a dynamic `NSColor` that resolves
/// against the appearance it is drawn in.
public enum NSPalette {
    public static var fillPrimary: NSColor { dynamic(light: (0x000000, 0x1A), dark: (0xFFFFFF, 0x1A)) }
    public static var fillSecondary: NSColor { dynamic(light: (0x000000, 0x14), dark: (0xFFFFFF, 0x14)) }

    /// Figma blends #E6E6E6 with plus-darker in Light and #141414 with plus-lighter in
    /// Dark. Over the glass the trial dialog sits on, these alphas give the same color with
    /// ordinary blending, which works on every surface and macOS version.
    public static var fillVibrantSecondary: NSColor { dynamic(light: (0x000000, 0x1A), dark: (0xFFFFFF, 0x16)) }

    public static var progressTrack: NSColor { dynamic(light: (0x000000, 0x16), dark: (0xFFFFFF, 0x16)) }
    public static var progressTrackStroke: NSColor { dynamic(light: (0x000000, 0x12), dark: (0xFFFFFF, 0x0A)) }

    public static var surfaceCard: NSColor { dynamic(light: (0xFFFFFF, 0x99), dark: (0xFFFFFF, 0x12)) }
    public static var surfaceSelectedControl: NSColor { dynamic(light: (0xFFFFFF, 0xFF), dark: (0xFFFFFF, 0x3D)) }
    public static var surfaceTrack: NSColor { dynamic(light: (0x000000, 0x0F), dark: (0xFFFFFF, 0x14)) }
    public static var surfaceRowHover: NSColor { dynamic(light: (0x000000, 0x0D), dark: (0xFFFFFF, 0x0F)) }
    public static var surfaceSidebarSelection: NSColor { dynamic(light: (0x000000, 0x14), dark: (0xFFFFFF, 0x1A)) }
    public static var surfaceGroup: NSColor { dynamic(light: (0x000000, 0x08), dark: (0xFFFFFF, 0x0A)) }
    public static var surfaceWarningTint: NSColor { dynamic(light: (0xFF8C29, 0x1F), dark: (0xFF9130, 0x29)) }
    public static var warningText: NSColor { dynamic(light: (0x995900, 0xFF), dark: (0xFF9F0A, 0xFF)) }

    /// The accent tint follows the person's accent color, at Figma's opacity.
    public static var surfaceAccentTint: NSColor {
        NSColor(name: "surfaceAccentTint") { appearance in
            NSColor.controlAccentColor.withAlphaComponent(isDark(appearance) ? 0x33 / 255 : 0x1F / 255)
        }
    }

    public static var strokeHairline: NSColor { dynamic(light: (0x000000, 0x1A), dark: (0xFFFFFF, 0x1A)) }
    public static var strokeWindowEdge: NSColor { dynamic(light: (0x000000, 0x26), dark: (0xFFFFFF, 0x24)) }

    public static var shadowSelectedControl: NSColor { dynamic(light: (0x000000, 0x2E), dark: (0x000000, 0x2E)) }

    /// Whether `appearance` is one of the dark ones, vibrant or not.
    public static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]).map { [.darkAqua, .vibrantDark].contains($0) }
            ?? false
    }

    /// A color with a Light and a Dark value, each an sRGB hex color and an alpha byte.
    static func dynamic(light: (rgb: UInt32, alpha: UInt8), dark: (rgb: UInt32, alpha: UInt8)) -> NSColor {
        let lightColor = srgb(light.rgb, alpha: light.alpha)
        let darkColor = srgb(dark.rgb, alpha: dark.alpha)
        return NSColor(name: nil) { appearance in isDark(appearance) ? darkColor : lightColor }
    }

    static func srgb(_ rgb: UInt32, alpha: UInt8) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
