import Foundation

/// The pictures ("skins") a person can choose for a display, as the override keys that make
/// macOS draw them, built from the artwork macOS ships: the icons in CoreTypes, and the
/// pictures System Settings › Displays shows, which Apple's Icons.plist lists by model.
///
/// Skins are named by text, the raw values of the app's picture choices: macBookPro, iMac,
/// studioDisplay, proDisplayXDR, display, ultrawide and tv. `display` removes the picture
/// keys, so macOS draws the display as it would without an override. macOS ships no picture
/// of an ultrawide display or a TV, so there is no picture for those two.
public struct DisplayIcons: Sendable {
    /// What `skin(for:)` says about a picture Resolute did not write. It is kept as it is.
    public static let custom = "custom"
    /// The skin that leaves the picture to macOS.
    public static let defaultSkin = "display"
    /// Every skin, in the order Picture & Name offers them.
    public static let skins = ["macBookPro", "iMac", "studioDisplay", "proDisplayXDR", "display", "ultrawide", "tv"]

    /// This Mac's artwork, as its Icons.plist lists it.
    public static let system = DisplayIcons(
        appleIcons: (try? Data(contentsOf: iconsFile)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        } ?? [:],
        fileExists: { FileManager.default.fileExists(atPath: $0) }
    )

    /// Apple's list of display pictures.
    static let iconsFile = OverrideLocations.standard.systemRoot.appending(path: "Icons.plist", directoryHint: .notDirectory)
    /// Where macOS keeps the icons of Apple's devices, named by type identifier.
    static let iconFolder = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
    /// The folders whose files an icon or a picture can name and still be read back as a skin.
    static let appleFolders = [
        "/System/Library/CoreServices/CoreTypes.bundle/", "/System/Library/Displays/Contents/Resources/Overrides/",
    ]
    /// "aapl": the vendor under which Icons.plist lists Apple's models by type identifier.
    static let appleVendor = "6161706c"

    /// A model whose artwork macOS ships: an icon in CoreTypes named by its type identifier,
    /// and a picture that Icons.plist lists under that identifier.
    struct Model: Sendable {
        var typeIdentifier: String
        /// The picture's file name, in Overrides/Models.
        var pictureName: String

        init(_ typeIdentifier: String, picture: String? = nil) {
            self.typeIdentifier = typeIdentifier
            pictureName = picture ?? typeIdentifier + ".tiff"
        }

        var iconPath: String { DisplayIcons.iconFolder + "/" + typeIdentifier + ".icns" }
    }

    /// The models each skin draws, best first. Later ones stand in on a Mac that lacks the
    /// artwork of earlier ones.
    static let models: [String: [Model]] = [
        "macBookPro": [
            Model("com.apple.macbookpro-16-2021-space-gray"), Model("com.apple.macbookpro-16-space-gray"),
            Model("com.apple.macbookpro-15-retina-display"),
        ],
        "iMac": [Model("com.apple.imac-2021-silver"), Model("com.apple.imac-2024-silver"), Model("com.apple.imac-unibody-27")],
        "studioDisplay": [Model("com.apple.studio-display")],
        "proDisplayXDR": [Model("com.apple.pro-display-xdr", picture: "com.apple.pro-display-xdr-landscape.tiff")],
    ]

    /// Each skin's models by the start of their type identifiers, to read a picture back.
    static let families: [(prefix: String, skin: String)] = [
        ("com.apple.macbookpro", "macBookPro"),
        ("com.apple.imac", "iMac"),
        ("com.apple.imacpro", "iMac"),
        ("com.apple.studio-display", "studioDisplay"),
        ("com.apple.pro-display-xdr", "proDisplayXDR"),
    ]

    /// Icons.plist's entry for each model in `models` that it lists, by type identifier.
    private let entries: [String: PropertyListDictionary]
    private let fileExists: @Sendable (String) -> Bool

    /// The artwork `appleIcons`, the contents of Apple's Icons.plist, lists; `fileExists`
    /// says which files are on this Mac.
    public init(appleIcons: [String: Any], fileExists: @escaping @Sendable (String) -> Bool) {
        var entries: [String: PropertyListDictionary] = [:]
        for model in Self.models.values.joined() {
            if let entry = Self.entry(for: model, in: appleIcons) {
                entries[model.typeIdentifier] = PropertyListDictionary(entry)
            }
        }
        self.entries = entries
        self.fileExists = fileExists
    }

    // MARK: - Skins to pictures

    /// The picture keys that make macOS draw `skin`, from the artwork on this Mac: no keys
    /// for `display`, and nil when this Mac has no artwork for it or there is no such skin.
    ///
    /// The picture is Apple's own for the first of the skin's models whose picture this Mac
    /// has, and the icon the first of their icons it has. Apple lists a larger picture only
    /// for MacBooks; for other models the same picture stands in, so a Mac's own display
    /// shows the chosen picture at both sizes rather than its own at the larger one.
    public func picture(forSkin skin: String) -> DisplayOverride.Picture? {
        if skin == Self.defaultSkin { return DisplayOverride.Picture.none }
        guard let models = Self.models[skin] else { return nil }
        let preview = models.lazy.compactMap { self.previewKeys(for: $0) }.first
        let icon = iconPath(forSkin: skin)
        guard preview != nil || icon != nil else { return nil }
        var keys = preview ?? [:]
        if let icon { keys[DisplayOverride.Picture.iconKey] = icon }
        return DisplayOverride.Picture(keys)
    }

    /// The icon file `skin` writes as `display-icon` on this Mac: nil for `display`, which
    /// writes none, and for a skin this Mac has no icon for.
    public func iconPath(forSkin skin: String) -> String? {
        Self.models[skin]?.lazy.map(\.iconPath).first { fileExists($0) }
    }

    /// Whether this Mac has artwork for `skin`.
    public func isAvailable(_ skin: String) -> Bool {
        picture(forSkin: skin) != nil
    }

    /// Apple's picture keys for `model`, leaving out pictures this Mac lacks; nil when it
    /// lacks the main one.
    func previewKeys(for model: Model) -> [String: Any]? {
        typealias Picture = DisplayOverride.Picture
        guard let entry = entries[model.typeIdentifier]?.dictionary else { return nil }
        var keys = entry.filter { Picture.isPictureKey($0.key) && $0.key != Picture.iconKey }
        // A picture that is not there would leave its rectangle behind, so both go.
        let missing = Set(keys.compactMap { key, value -> String? in
            guard key.hasPrefix(Picture.previewKey), let variant = Picture.variant(of: key) else { return nil }
            guard let path = value as? String, fileExists(path) else { return variant }
            return nil
        })
        keys = keys.filter { key, _ in Picture.variant(of: key).map { !missing.contains($0) } ?? true }
        guard keys[Picture.previewKey] != nil else { return nil }
        if keys[Picture.previewKey + "-large"] == nil {
            for base in [Picture.previewKey] + Picture.previewFrameKeys {
                keys[base + "-large"] = keys[base]
            }
        }
        return keys
    }

    /// Icons.plist's entry for `model`: the one listed under its type identifier, else the
    /// first that shows its picture, for a list that names pictures only by product.
    static func entry(for model: Model, in icons: [String: Any]) -> [String: Any]? {
        let vendors = icons["vendors"] as? [String: Any]
        let products = (vendors?[appleVendor] as? [String: Any])?["products"] as? [String: Any]
        if let entry = products?[model.typeIdentifier] as? [String: Any], entry[DisplayOverride.Picture.previewKey] != nil {
            return entry
        }
        return firstEntry(in: icons, showing: model.pictureName)
    }

    /// The first dictionary in `dictionary`, itself included, whose main picture is named
    /// `pictureName`, looking through keys in order so the answer is always the same.
    private static func firstEntry(in dictionary: [String: Any], showing pictureName: String) -> [String: Any]? {
        if let path = dictionary[DisplayOverride.Picture.previewKey] as? String,
           (path as NSString).lastPathComponent == pictureName {
            return dictionary
        }
        for (_, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            if let child = value as? [String: Any], let entry = firstEntry(in: child, showing: pictureName) {
                return entry
            }
        }
        return nil
    }

    // MARK: - Pictures to skins

    /// Which skin `picture` shows: `display` when it has no keys, the skin whose models its
    /// icon and pictures all name, or `custom` for anything else, such as a picture another
    /// tool chose, which Resolute leaves as it is.
    public static func skin(for picture: DisplayOverride.Picture) -> String {
        typealias Picture = DisplayOverride.Picture
        guard !picture.isEmpty else { return defaultSkin }
        var found: String?
        for (key, value) in picture.dictionary where key == Picture.iconKey || key.hasPrefix(Picture.previewKey) {
            guard let name = value as? String, let skin = family(of: name), found == nil || found == skin else {
                return custom
            }
            found = skin
        }
        return found ?? custom
    }

    /// Which skin an icon path names: `display` for none, the skin whose model it names, or
    /// `custom`. `skin(for:)` also reads the pictures, which are what System Settings shows.
    public static func skin(forIconPath path: String?) -> String {
        guard let path else { return defaultSkin }
        return family(of: path) ?? custom
    }

    /// The skin whose model `name` names: a file in Apple's folders named after a model's
    /// type identifier. A bare type identifier, as Icons.plist writes them, is not one:
    /// macOS draws nothing from it in an override, so it reads as `custom`, and choosing the
    /// skin writes the files.
    static func family(of name: String) -> String? {
        guard name.hasPrefix("/") else { return nil }
        let path = URL(filePath: name).standardized.path(percentEncoded: false)
        guard appleFolders.contains(where: { path.hasPrefix($0) }) else { return nil }
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return families.first { stem == $0.prefix || stem.hasPrefix($0.prefix + "-") }?.skin
    }
}
