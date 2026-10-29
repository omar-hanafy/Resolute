import AppKit

/// A file from Design/ (Figma's artwork, exported as PDF), embedded in the binary by
/// `Scripts/embed-assets.swift` as `Artwork.<Folder>.<file>` in Assets/EmbeddedArtwork.swift.
///
/// The artwork is data in Swift rather than a SwiftPM resource: `Bundle.module` looks for
/// its bundle at the root of the .app, where it can't be signed, and falls back to a
/// build-folder path that doesn't exist on other Macs.
struct Artwork: Sendable {
    /// The file the artwork came from, relative to the repository root
    /// ("Design/DisplayPictures/tv.pdf").
    let source: String
    /// The file's bytes.
    ///
    /// Each artwork is a `static let`, which Swift initializes once, on first use, so a
    /// file is decoded only when something first draws it, and only once.
    let data: Data

    init(source: String, base64: String) {
        self.source = source
        if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            self.data = data
        } else {
            assertionFailure("\(source) is not valid base64; run Scripts/embed-assets.swift again.")
            self.data = Data()
        }
    }

    /// A new image of the artwork. A PDF stays vector, so it is sharp at any size.
    func makeImage() -> NSImage {
        if let image = NSImage(data: data) { return image }
        assertionFailure("\(source) is not an image NSImage can read.")
        return NSImage(size: .zero)
    }
}

/// One image per artwork, shared by the views that draw it, so SwiftUI sees the same
/// image on every update and parses each file once.
@MainActor
enum ArtworkImages {
    private static var images: [String: NSImage] = [:]

    static func image(for artwork: Artwork) -> NSImage {
        if let image = images[artwork.source] { return image }
        let image = artwork.makeImage()
        images[artwork.source] = image
        return image
    }
}
