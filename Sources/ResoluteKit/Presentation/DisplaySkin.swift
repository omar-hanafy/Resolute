import Foundation

/// The picture Resolute draws for a display, which a person can change in Picture & Name.
/// The cases are ResoluteDesign's `DisplayPictureModel` cases with the same raw values, so
/// the app turns one into the other by raw value.
public enum DisplaySkin: String, CaseIterable, Hashable, Sendable, Codable {
    case macBookPro
    case iMac
    case studioDisplay
    case proDisplayXDR
    case display
    case ultrawide
    case tv

    /// The picture that suits `display` until someone picks one: the Mac's own for its
    /// built-in display, Apple's displays by product ID, then the panel's shape, then its name.
    public static func suggestion(for display: Display, details: DisplayDetails) -> DisplaySkin {
        if display.isBuiltin {
            return details.isIMacScreen ? .iMac : .macBookPro
        }
        if display.vendorID == DisplayFacts.appleVendorID {
            if studioDisplayProducts.contains(display.productID) { return .studioDisplay }
            if proDisplayXDRProducts.contains(display.productID) { return .proDisplayXDR }
        }
        let panel = DisplayFacts.nativeSize(of: display)
            ?? display.currentMode.map { DisplayFacts.PixelSize(width: $0.pixelWidth, height: $0.pixelHeight) }
        // 21:9 and 32:9 panels; 16:9 is 1.78.
        if let panel, panel.aspectRatio >= 2.1 { return .ultrawide }
        if looksLikeTV(display.name) { return .tv }
        return .display
    }

    /// Product IDs of the override files macOS ships for its displays, under
    /// /System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610: Studio
    /// Display (ae3a, ae3b, ae3e, ae3f, ae46, ae47) and Studio Display XDR (ae42, ae43).
    static let studioDisplayProducts: Set<UInt32> = [0xAE3A, 0xAE3B, 0xAE3E, 0xAE3F, 0xAE42, 0xAE43, 0xAE46, 0xAE47]
    /// Pro Display XDR, from the same folder.
    static let proDisplayXDRProducts: Set<UInt32> = [0xAE21, 0xAE22, 0xAE23, 0xAE2D, 0xAE2E, 0xAE2F]

    /// Televisions name themselves "LG TV SSCR2", "SONY TV  *00" or "Panasonic-TV", or by
    /// a TV-only brand; AirPlay receivers carry the name a person gave them, such as
    /// "Living Room TV".
    static func looksLikeTV(_ name: String) -> Bool {
        name.uppercased()
            .split { !$0.isLetter && !$0.isNumber }
            .contains { televisionWords.contains(String($0)) }
    }

    static let televisionWords: Set<String> = ["TV", "HDTV", "UHDTV", "TELEVISION", "BRAVIA", "VIZIO", "HISENSE", "ROKU"]
}
