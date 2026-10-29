import AppKit
import SwiftUI

/// Resolute's app icon at any size (Figma: Components › App Icon, page App Icon): the
/// Default artwork in Light and the Dark artwork in Dark. Welcome, About and the trial
/// dialog show it.
///
/// The artwork is Figma's 128-point frame: the rounded square, inset 12 points, with its
/// drop shadow. Give the view a square frame of the icon's size (64 points in the trial
/// dialog). It is decorative, so VoiceOver skips it: the app's name is always beside it.
public struct AppIconView: View {
    /// Figma's appearances of the icon. Tinted is left to Icon Composer.
    public enum Appearance: String, CaseIterable, Sendable {
        /// Light: blue to indigo.
        case `default`
        /// Dark: near-black with a blue glow.
        case dark

        /// The appearance the icon takes in `colorScheme`.
        public init(_ colorScheme: ColorScheme) {
            self = colorScheme == .dark ? .dark : .default
        }

        /// The appearance's artwork, from Design/AppIcon.
        var artwork: Artwork {
            switch self {
            case .default: Artwork.AppIcon.default
            case .dark: Artwork.AppIcon.dark
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    private let appearance: Appearance?

    /// The icon in the appearance of the color scheme it is shown in.
    public init() {
        appearance = nil
    }

    /// The icon in one appearance, whatever the color scheme.
    public init(_ appearance: Appearance) {
        self.appearance = appearance
    }

    public var body: some View {
        Image(nsImage: ArtworkImages.image(for: (appearance ?? Appearance(colorScheme)).artwork))
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    /// The icon for AppKit (an alert's icon, the About panel): the 128-point vector
    /// artwork, sharp at any size. Each call returns a new image.
    nonisolated public static func nsImage(_ appearance: Appearance = .default) -> NSImage {
        let image = appearance.artwork.makeImage()
        image.accessibilityDescription = "Resolute"
        return image
    }
}
