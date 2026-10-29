import Foundation

/// Identifies a display model the way override files do: by vendor and product ID.
public struct OverrideKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var vendorID: UInt32
    public var productID: UInt32

    public init(vendorID: UInt32, productID: UInt32) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public init(display: Display) {
        self.init(vendorID: display.vendorID, productID: display.productID)
    }

    /// Parses "DisplayVendorID-db4" and "DisplayProductID-3401".
    public init?(vendorDirectory: String, productFile: String) {
        guard let vendor = Self.hexSuffix(of: vendorDirectory, after: "DisplayVendorID-"),
              let product = Self.hexSuffix(of: productFile, after: "DisplayProductID-")
        else { return nil }
        self.init(vendorID: vendor, productID: product)
    }

    /// "DisplayVendorID-db4"
    public var vendorDirectoryName: String { "DisplayVendorID-" + String(vendorID, radix: 16) }
    /// "DisplayProductID-3401"
    public var productFileName: String { "DisplayProductID-" + String(productID, radix: 16) }
    /// "DisplayVendorID-db4/DisplayProductID-3401"
    public var relativePath: String { "\(vendorDirectoryName)/\(productFileName)" }
    /// "vendor db4, product 3401"
    public var description: String {
        "vendor \(String(vendorID, radix: 16)), product \(String(productID, radix: 16))"
    }

    public static func < (lhs: OverrideKey, rhs: OverrideKey) -> Bool {
        (lhs.vendorID, lhs.productID) < (rhs.vendorID, rhs.productID)
    }

    private static func hexSuffix(of name: String, after prefix: String) -> UInt32? {
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(\.isHexDigit) else { return nil }
        // macOS formats IDs without leading zeros and never reads a padded name.
        guard digits == "0" || digits.first != "0" else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/// A property-list dictionary that is `Sendable` and compares by content.
public struct PropertyListDictionary: Equatable, Sendable {
    private let archive: Data

    public static let empty = PropertyListDictionary([:])

    public init(_ dictionary: [String: Any]) {
        archive = (try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)) ?? Data()
    }

    public var dictionary: [String: Any] {
        ((try? PropertyListSerialization.propertyList(from: archive, format: nil)) as? [String: Any]) ?? [:]
    }

    public var keys: [String] { dictionary.keys.sorted() }

    /// Equal bytes need no decoding: a copy that nothing changed, as an editor's working copy
    /// usually is, compares without it.
    public static func == (lhs: PropertyListDictionary, rhs: PropertyListDictionary) -> Bool {
        lhs.archive == rhs.archive || NSDictionary(dictionary: lhs.dictionary).isEqual(to: rhs.dictionary)
    }
}

/// The contents of one override file (`DisplayVendorID-xxxx/DisplayProductID-yyyy`).
public struct DisplayOverride: Equatable, Sendable {
    public static let productNameKey = "DisplayProductName"
    public static let resolutionsKey = "scale-resolutions"
    public static let targetPPMMKey = "target-default-ppmm"
    /// The value RDM gave the files it created.
    public static let defaultTargetPPMM = 10.01

    public var key: OverrideKey
    /// Replaces the display's name in macOS; nil keeps the display's own name.
    public var productName: String?
    /// How macOS draws the display: its icon, and its picture in System Settings › Displays.
    /// Its keys replace any of the same name in `otherKeys` when the file is written.
    public var picture: Picture
    public var resolutions: [ScaleResolution]
    /// Every other key in the file, written back unchanged.
    public var otherKeys: PropertyListDictionary
    /// True until the override exists as a file. Like RDM, Resolute gives a new file the
    /// target density `defaultTargetPPMM`; a file that exists, such as a copy of Apple's,
    /// keeps its own keys, because the density steers which mode macOS makes the default.
    public var isNew: Bool

    public init(
        key: OverrideKey,
        productName: String? = nil,
        picture: Picture = .none,
        resolutions: [ScaleResolution] = [],
        otherKeys: PropertyListDictionary = .empty,
        isNew: Bool = true
    ) {
        self.key = key
        self.productName = productName
        self.picture = picture
        self.resolutions = resolutions
        self.otherKeys = otherKeys
        self.isNew = isNew
    }

    /// The icon file macOS shows for the display (`display-icon`); nil leaves it to macOS.
    /// Setting it leaves the rest of `picture` as it is.
    public var displayIcon: String? {
        get { picture.icon }
        set { picture.icon = newValue }
    }

    /// Reads an override file's contents.
    public init(key: OverrideKey, propertyList data: Data) throws {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard var dictionary = object as? [String: Any] else {
            if let list = object as? [[String: Any]], !list.isEmpty {
                throw ResoluteError.overrideUnreadable(
                    path: key.relativePath,
                    reason: "it holds several overrides that macOS chooses between by display properties, which Resolute can’t edit"
                )
            }
            throw ResoluteError.overrideUnreadable(path: key.relativePath, reason: "the file is not a dictionary")
        }
        var productName: String?
        if let name = dictionary[Self.productNameKey] as? String {
            productName = name.isEmpty ? nil : name
            dictionary.removeValue(forKey: Self.productNameKey)
        }
        let picture = Picture(dictionary.filter { Picture.isPictureKey($0.key) })
        dictionary = dictionary.filter { !Picture.isPictureKey($0.key) }
        var resolutions: [ScaleResolution] = []
        if let elements = dictionary[Self.resolutionsKey] as? [Any] {
            resolutions = ScaleResolutionCodec.decode(elements)
            dictionary.removeValue(forKey: Self.resolutionsKey)
        }
        self.init(
            key: key, productName: productName, picture: picture, resolutions: resolutions,
            otherKeys: PropertyListDictionary(dictionary), isNew: false
        )
    }

    /// HiDPI entries without a 1× entry at their pixel size, which Resolute and RDM add with
    /// each HiDPI entry. Apple's own files list some HiDPI entries without one.
    public var unpairedHiDPIEntries: [ScaleResolution] {
        resolutions.filter { entry in
            guard case .hiDPI? = entry.describedMode, let pixels = entry.pixelSize else { return false }
            let partner = ScaleResolution.standard(width: pixels.width, height: pixels.height)
            return !resolutions.contains { $0.sameMode(as: partner) }
        }
    }

    /// The file contents, as an XML property list.
    public func propertyListData() throws -> Data {
        var dictionary = otherKeys.dictionary
        if let productName, !productName.isEmpty {
            dictionary[Self.productNameKey] = productName
        }
        dictionary.merge(picture.dictionary) { _, picture in picture }
        let encoded = try ScaleResolutionCodec.encode(resolutions)
        if !encoded.isEmpty {
            dictionary[Self.resolutionsKey] = encoded
            if isNew, dictionary[Self.targetPPMMKey] == nil {
                dictionary[Self.targetPPMMKey] = Self.defaultTargetPPMM
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

extension DisplayOverride {
    /// How macOS draws a display, as an override file's picture keys say. They are kept
    /// exactly as the file holds them, so a picture Resolute does not recognize, such as
    /// one another tool chose, is written back unchanged.
    ///
    /// - `display-icon`: the display's icon, as the path of an icon file.
    /// - `display-resolution-preview-icon`: the picture System Settings › Displays shows, as
    ///   the path of an image, with the desktop drawn into the screen's rectangle:
    ///   `resolution-preview-x`, `-y`, `-width` and `-height`, in points from the picture's
    ///   bottom-left corner. The same keys ending in `-large` are for System Settings' larger
    ///   picture, which Apple draws only of MacBooks, and those ending in `-90`, `-180` or
    ///   `-270` for a rotated display.
    /// - `resolution-corner-radius`: how rounded the screen's corners are.
    public struct Picture: Equatable, Sendable {
        public static let iconKey = "display-icon"
        public static let previewKey = "display-resolution-preview-icon"
        /// The screen's rectangle in the picture: x, y, width and height.
        public static let previewFrameKeys = [
            "resolution-preview-x", "resolution-preview-y", "resolution-preview-width", "resolution-preview-height",
        ]
        public static let cornerRadiusKey = "resolution-corner-radius"

        /// No picture keys: macOS draws the display as it would without an override.
        public static let none = Picture([:])

        private var values: PropertyListDictionary

        /// The picture keys in `dictionary`; any other key is left out.
        public init(_ dictionary: [String: Any]) {
            values = PropertyListDictionary(dictionary.filter { Self.isPictureKey($0.key) })
        }

        /// Whether macOS reads `key` for a display's icon or its picture.
        public static func isPictureKey(_ key: String) -> Bool {
            key == iconKey || key.hasPrefix(previewKey) || key.hasPrefix("resolution-preview-")
                || key.hasPrefix(cornerRadiusKey)
        }

        /// The keys and their values, as the file holds them.
        public var dictionary: [String: Any] { values.dictionary }

        public var keys: [String] { values.keys }

        public var isEmpty: Bool { dictionary.isEmpty }

        /// `display-icon`; nil when there is none, or when it holds something other than text.
        public var icon: String? {
            get { dictionary[Self.iconKey] as? String }
            set {
                var dictionary = dictionary
                if let newValue {
                    dictionary[Self.iconKey] = newValue
                } else {
                    dictionary.removeValue(forKey: Self.iconKey)
                }
                values = PropertyListDictionary(dictionary)
            }
        }

        /// The picture System Settings › Displays shows (`display-resolution-preview-icon`).
        public var previewImage: String? { dictionary[Self.previewKey] as? String }

        /// Which picture a preview key belongs to: "" for the main one, "-large", "-90" and
        /// so on for the others. Nil for any other key.
        static func variant(of key: String) -> String? {
            for base in [previewKey] + previewFrameKeys where key.hasPrefix(base) {
                return String(key.dropFirst(base.count))
            }
            return nil
        }
    }
}
