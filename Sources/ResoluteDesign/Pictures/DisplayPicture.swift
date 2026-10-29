import AppKit
import SwiftUI

/// The kinds of display Resolute draws (Figma: Components › Display Picture). A display's
/// picture in the panel and window, and the "skin" a person can choose for it.
public enum DisplayPictureModel: String, CaseIterable, Sendable, Codable {
    case macBookPro
    case iMac
    case studioDisplay
    case proDisplayXDR
    case display
    case ultrawide
    case tv

    /// The name under the picture in Picture & Name.
    public var title: String {
        switch self {
        case .macBookPro: "MacBook Pro"
        case .iMac: "iMac"
        case .studioDisplay: "Studio Display"
        case .proDisplayXDR: "Pro Display XDR"
        case .display: "Display"
        case .ultrawide: "Ultrawide Display"
        case .tv: "TV"
        }
    }

    /// The picture for AppKit views: Figma's vector artwork in its 160 × 120 frame, sharp
    /// at any size, described as `title` for VoiceOver. Each call returns a new image, so
    /// changing its size or other properties affects only the caller's copy.
    public func nsImage() -> NSImage {
        let image = artwork.makeImage()
        image.accessibilityDescription = title
        return image
    }

    /// The model's artwork, from Design/DisplayPictures (one PDF per Figma variant).
    var artwork: Artwork {
        switch self {
        case .macBookPro: Artwork.DisplayPictures.macBookPro
        case .iMac: Artwork.DisplayPictures.iMac
        case .studioDisplay: Artwork.DisplayPictures.studioDisplay
        case .proDisplayXDR: Artwork.DisplayPictures.proDisplayXDR
        case .display: Artwork.DisplayPictures.display
        case .ultrawide: Artwork.DisplayPictures.ultrawide
        case .tv: Artwork.DisplayPictures.tv
        }
    }
}

/// A display's picture, drawn at any size in Figma's 4:3 frame (160 × 120): the exact
/// Figma artwork, as vectors, with the room Figma leaves around each model.
///
/// Contract (Wave 0): the type, `init(_:)` and the 4:3 frame stay.
public struct DisplayPicture: View {
    public static let aspectRatio: CGFloat = 160.0 / 120.0

    public var model: DisplayPictureModel

    public init(_ model: DisplayPictureModel) {
        self.model = model
    }

    public var body: some View {
        Image(nsImage: ArtworkImages.image(for: model.artwork))
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .accessibilityLabel(Text(model.title))
    }
}
