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

    public static func == (lhs: PropertyListDictionary, rhs: PropertyListDictionary) -> Bool {
        NSDictionary(dictionary: lhs.dictionary).isEqual(to: rhs.dictionary)
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
        resolutions: [ScaleResolution] = [],
        otherKeys: PropertyListDictionary = .empty,
        isNew: Bool = true
    ) {
        self.key = key
        self.productName = productName
        self.resolutions = resolutions
        self.otherKeys = otherKeys
        self.isNew = isNew
    }

    /// Reads an override file's contents.
    public init(key: OverrideKey, propertyList data: Data) throws {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard var dictionary = object as? [String: Any] else {
            throw ResoluteError.overrideUnreadable(path: key.relativePath, reason: "the file is not a dictionary")
        }
        var productName: String?
        if let name = dictionary[Self.productNameKey] as? String {
            productName = name.isEmpty ? nil : name
            dictionary.removeValue(forKey: Self.productNameKey)
        }
        var resolutions: [ScaleResolution] = []
        if let elements = dictionary[Self.resolutionsKey] as? [Any] {
            resolutions = ScaleResolutionCodec.decode(elements)
            dictionary.removeValue(forKey: Self.resolutionsKey)
        }
        self.init(
            key: key, productName: productName, resolutions: resolutions, otherKeys: PropertyListDictionary(dictionary),
            isNew: false
        )
    }

    /// The file contents, as an XML property list.
    public func propertyListData() throws -> Data {
        var dictionary = otherKeys.dictionary
        if let productName, !productName.isEmpty {
            dictionary[Self.productNameKey] = productName
        }
        let encoded = ScaleResolutionCodec.encode(resolutions)
        if !encoded.isEmpty {
            dictionary[Self.resolutionsKey] = encoded
            if isNew, dictionary[Self.targetPPMMKey] == nil {
                dictionary[Self.targetPPMMKey] = Self.defaultTargetPPMM
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
