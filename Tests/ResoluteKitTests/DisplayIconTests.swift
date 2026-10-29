import Foundation
import Testing
@testable import ResoluteKit

/// Artwork as macOS 27 lists it in Icons.plist, on a Mac that has every file it names.
enum AppleArtwork {
    static let pictures = "/System/Library/Displays/Contents/Resources/Overrides/Models/"
    static let icons = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"

    static func entry(_ picture: String, _ frame: [Int], suffix: String = "") -> [String: Any] {
        [
            "display-resolution-preview-icon" + suffix: pictures + picture,
            "resolution-preview-x" + suffix: frame[0], "resolution-preview-y" + suffix: frame[1],
            "resolution-preview-width" + suffix: frame[2], "resolution-preview-height" + suffix: frame[3],
        ]
    }

    static func merged(_ parts: [String: Any]...) -> [String: Any] {
        parts.reduce(into: [:]) { $0.merge($1) { _, new in new } }
    }

    static var studioDisplay: [String: Any] { entry("com.apple.studio-display.tiff", [5, 72, 236, 134]) }

    static var proDisplayXDR: [String: Any] {
        merged(
            entry("com.apple.pro-display-xdr-landscape.tiff", [3, 59, 244, 137]),
            entry("com.apple.pro-display-xdr-portrait.tiff", [3, 47, 100, 178], suffix: "-90"),
            entry("com.apple.pro-display-xdr-landscape.tiff", [3, 59, 244, 137], suffix: "-180"),
            entry("com.apple.pro-display-xdr-portrait.tiff", [3, 47, 100, 178], suffix: "-270")
        )
    }

    static var macBookPro16: [String: Any] {
        merged(
            entry("com.apple.macbookpro-16-2021-space-gray.tiff", [27, 42, 176, 113]),
            entry("com.apple.macbookpro-16-2021-space-gray-large.tiff", [34, 47, 220, 141], suffix: "-large")
        )
    }

    static var appleIcons: [String: Any] {
        [
            "vendors": [
                "6161706c": [
                    "products": [
                        "com.apple.studio-display": studioDisplay,
                        "com.apple.pro-display-xdr": proDisplayXDR,
                        "com.apple.macbookpro-16-2021-space-gray": macBookPro16,
                        "com.apple.macbookpro-16-space-gray": merged(
                            entry("com.apple.macbookpro-16-space-gray.tiff", [28, 42, 175, 108]),
                            entry("com.apple.macbookpro-16-space-gray-large.tiff", [34, 47, 218, 136], suffix: "-large")
                        ),
                        "com.apple.imac-2021-silver": entry("com.apple.imac-2021-silver.tiff", [7, 92, 232, 130]),
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    /// Every picture `appleIcons` names, and every icon the skins use.
    static var files: Set<String> {
        var files = Set<String>()
        func collect(_ value: Any) {
            if let path = value as? String, path.hasPrefix("/") { files.insert(path) }
            if let dictionary = value as? [String: Any] { dictionary.values.forEach(collect) }
        }
        collect(appleIcons)
        for model in DisplayIcons.models.values.joined() { files.insert(model.iconPath) }
        return files
    }

    /// The artwork above, without `missing`.
    static func library(without missing: Set<String> = [], appleIcons: [String: Any] = appleIcons) -> DisplayIcons {
        let present = files.subtracting(missing)
        return DisplayIcons(appleIcons: appleIcons, fileExists: { present.contains($0) })
    }

    /// The same keys, as `NSDictionary` compares them.
    static func same(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}

@Suite struct DisplayIconTests {
    // MARK: - Skins to pictures

    /// Apple's own picture keys for the model, the model's icon, and the same picture at
    /// the larger size, which Apple lists only for MacBooks: without it a Mac's own display
    /// would show itself there instead.
    @Test func writesApplesPictureAndTheModelsIcon() throws {
        let picture = try #require(AppleArtwork.library().picture(forSkin: "studioDisplay"))
        let expected = AppleArtwork.merged(
            AppleArtwork.studioDisplay,
            AppleArtwork.entry("com.apple.studio-display.tiff", [5, 72, 236, 134], suffix: "-large"),
            ["display-icon": AppleArtwork.icons + "com.apple.studio-display.icns"]
        )
        #expect(AppleArtwork.same(picture.dictionary, expected), "\(picture.dictionary)")
        #expect(picture.icon == AppleArtwork.icons + "com.apple.studio-display.icns")
        #expect(picture.previewImage == AppleArtwork.pictures + "com.apple.studio-display.tiff")
    }

    /// Apple's larger MacBook picture and its pictures of a rotated XDR are kept as listed.
    @Test func keepsApplesLargeAndRotatedPictures() throws {
        let library = AppleArtwork.library()
        let macBook = try #require(library.picture(forSkin: "macBookPro"))
        #expect(AppleArtwork.same(
            macBook.dictionary,
            AppleArtwork.merged(AppleArtwork.macBookPro16, ["display-icon": AppleArtwork.icons + "com.apple.macbookpro-16-2021-space-gray.icns"])
        ))
        let xdr = try #require(library.picture(forSkin: "proDisplayXDR"))
        #expect(AppleArtwork.same(xdr.dictionary, AppleArtwork.merged(
            AppleArtwork.proDisplayXDR,
            AppleArtwork.entry("com.apple.pro-display-xdr-landscape.tiff", [3, 59, 244, 137], suffix: "-large"),
            ["display-icon": AppleArtwork.icons + "com.apple.pro-display-xdr.icns"]
        )))
        let iMac = try #require(library.picture(forSkin: "iMac"))
        #expect(iMac.previewImage == AppleArtwork.pictures + "com.apple.imac-2021-silver.tiff")
        #expect(iMac.icon == AppleArtwork.icons + "com.apple.imac-2021-silver.icns")
    }

    @Test func leavesThePictureToMacOSForDisplay() throws {
        let picture = try #require(AppleArtwork.library().picture(forSkin: "display"))
        #expect(picture.isEmpty)
        #expect(picture == .none)
        #expect(AppleArtwork.library().iconPath(forSkin: "display") == nil)
    }

    /// macOS ships no picture of an ultrawide display or a TV.
    @Test(arguments: ["ultrawide", "tv", "projector", "custom", ""])
    func hasNoPictureWithoutArtwork(skin: String) {
        let library = AppleArtwork.library()
        #expect(library.picture(forSkin: skin) == nil)
        #expect(library.iconPath(forSkin: skin) == nil)
        #expect(!library.isAvailable(skin))
    }

    @Test func offersEveryOtherSkin() {
        let library = AppleArtwork.library()
        #expect(DisplayIcons.skins.filter(library.isAvailable)
            == ["macBookPro", "iMac", "studioDisplay", "proDisplayXDR", "display"])
    }

    /// A Mac without the first model's artwork gets the next model that it has.
    @Test func fallsBackToTheNextModelThisMacHas() throws {
        let newest = "com.apple.macbookpro-16-2021-space-gray"
        let older = try #require(AppleArtwork.library(without: [
            AppleArtwork.pictures + newest + ".tiff", AppleArtwork.icons + newest + ".icns",
        ]).picture(forSkin: "macBookPro"))
        #expect(older.previewImage == AppleArtwork.pictures + "com.apple.macbookpro-16-space-gray.tiff")
        #expect(older.icon == AppleArtwork.icons + "com.apple.macbookpro-16-space-gray.icns")
        #expect(older.dictionary["resolution-preview-width"] as? Int == 175)

        // Only the icon is missing: the picture stays the newest, the icon comes from the next.
        let mixed = try #require(AppleArtwork.library(without: [AppleArtwork.icons + newest + ".icns"]).picture(forSkin: "macBookPro"))
        #expect(mixed.previewImage == AppleArtwork.pictures + newest + ".tiff")
        #expect(mixed.icon == AppleArtwork.icons + "com.apple.macbookpro-16-space-gray.icns")
        #expect(DisplayIcons.skin(for: mixed) == "macBookPro")
    }

    /// A picture that is not on this Mac goes with its rectangle; the main one standing in
    /// for a missing larger one.
    @Test func leavesOutPicturesThisMacLacks() throws {
        let portrait = AppleArtwork.pictures + "com.apple.pro-display-xdr-portrait.tiff"
        let xdr = try #require(AppleArtwork.library(without: [portrait]).picture(forSkin: "proDisplayXDR"))
        #expect(!xdr.keys.contains { $0.hasSuffix("-90") || $0.hasSuffix("-270") })
        #expect(xdr.keys.contains("display-resolution-preview-icon-180"))
        #expect(xdr.keys.contains("resolution-preview-height-180"))

        let large = AppleArtwork.pictures + "com.apple.macbookpro-16-2021-space-gray-large.tiff"
        let macBook = try #require(AppleArtwork.library(without: [large]).picture(forSkin: "macBookPro"))
        #expect(macBook.dictionary["display-resolution-preview-icon-large"] as? String
            == AppleArtwork.pictures + "com.apple.macbookpro-16-2021-space-gray.tiff")
        #expect(macBook.dictionary["resolution-preview-width-large"] as? Int == 176)
    }

    /// Without the main picture, the model has none to offer: an icon alone is written.
    @Test func writesTheIconAloneWithoutAPicture() throws {
        let studio = try #require(AppleArtwork.library(without: [AppleArtwork.pictures + "com.apple.studio-display.tiff"])
            .picture(forSkin: "studioDisplay"))
        #expect(studio.keys == ["display-icon"])
        #expect(DisplayIcons.skin(for: studio) == "studioDisplay")

        let unlisted = try #require(AppleArtwork.library(appleIcons: [:]).picture(forSkin: "proDisplayXDR"))
        #expect(unlisted.keys == ["display-icon"])

        let nothing = AppleArtwork.library(without: [
            AppleArtwork.pictures + "com.apple.studio-display.tiff", AppleArtwork.icons + "com.apple.studio-display.icns",
        ])
        #expect(nothing.picture(forSkin: "studioDisplay") == nil)
    }

    /// Icons.plist lists some models only by product, as Apple's own displays are: the
    /// picture is found by its file, without that entry's icon type identifier.
    @Test func findsAPictureListedOnlyByProduct() throws {
        let byProduct: [String: Any] = ["vendors": [
            "610": ["products": [
                "ae3a": AppleArtwork.merged(AppleArtwork.studioDisplay, ["display-icon": "com.apple.studio-display"]),
                "ae21": AppleArtwork.merged(AppleArtwork.proDisplayXDR, ["display-icon": "com.apple.pro-display-xdr"]),
            ] as [String: Any]] as [String: Any],
        ] as [String: Any]]
        let library = AppleArtwork.library(appleIcons: byProduct)
        let studio = try #require(library.picture(forSkin: "studioDisplay"))
        #expect(studio.icon == AppleArtwork.icons + "com.apple.studio-display.icns")
        #expect(studio.dictionary["resolution-preview-y"] as? Int == 72)
        let xdr = try #require(library.picture(forSkin: "proDisplayXDR"))
        #expect(xdr.dictionary["display-resolution-preview-icon-90"] as? String
            == AppleArtwork.pictures + "com.apple.pro-display-xdr-portrait.tiff")
    }

    // MARK: - Pictures to skins

    @Test func readsEachPictureBackAsItsSkin() throws {
        let library = AppleArtwork.library()
        for skin in DisplayIcons.skins where library.isAvailable(skin) {
            let picture = try #require(library.picture(forSkin: skin))
            #expect(DisplayIcons.skin(for: picture) == skin)
            #expect(DisplayIcons.skin(forIconPath: picture.icon) == skin)
        }
    }

    /// Other models of the same kind, in Apple's icons and pictures.
    static let applesNames: [(name: String, skin: String)] = [
        (AppleArtwork.icons + "com.apple.studio-display.icns", "studioDisplay"),
        (AppleArtwork.icons + "com.apple.studio-display-xdr-2026.icns", "studioDisplay"),
        (AppleArtwork.icons + "com.apple.pro-display-xdr.icns", "proDisplayXDR"),
        (AppleArtwork.icons + "com.apple.imacpro-2017.icns", "iMac"),
        (AppleArtwork.pictures + "com.apple.imac-unibody-21.tiff", "iMac"),
        (AppleArtwork.icons + "com.apple.imac-2021-blue.icns", "iMac"),
        (AppleArtwork.icons + "com.apple.macbookpro-14-2021-silver.icns", "macBookPro"),
        (AppleArtwork.pictures + "com.apple.macbookpro-14-late-2023-2-space-black-large.tiff", "macBookPro"),
        (AppleArtwork.pictures + "com.apple.pro-display-xdr-portrait.tiff", "proDisplayXDR"),
        (
            "/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0020.bundle/Contents/Resources/com.apple.imac-2024-blue.icns",
            "iMac"
        ),
    ]

    @Test(arguments: applesNames)
    func readsApplesNamesBack(name: String, skin: String) {
        #expect(DisplayIcons.skin(forIconPath: name) == skin)
        #expect(DisplayIcons.skin(for: DisplayOverride.Picture(["display-icon": name])) == skin)
    }

    /// Anything Resolute did not write is custom, and is kept as it is.
    static let otherNames: [String] = [
        "/Users/someone/Pictures/Monitor.icns",
        // Where macOS once kept its pictures, as the development Mac's override still names.
        "/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610/DisplayProductID-a03c-9d9da0.tiff",
        "/System/Library/Displays/Contents/Resources/Overrides/../../../../../tmp/com.apple.studio-display.icns",
        AppleArtwork.icons + "com.apple.macbookair-15-2023-midnight.icns",
        AppleArtwork.icons + "com.apple.imacintosh.icns",
        // Type identifiers, as Icons.plist names models: macOS draws nothing from them in
        // an override, so showing the skin as chosen would mislead.
        "com.apple.studio-display",
        "com.apple.pro-display-xdr",
        "public.generic-lcd",
        "Models/com.apple.studio-display.tiff",
    ]

    @Test(arguments: otherNames)
    func callsOtherPicturesCustom(name: String) {
        #expect(DisplayIcons.skin(forIconPath: name) == DisplayIcons.custom)
        #expect(DisplayIcons.skin(for: DisplayOverride.Picture(["display-icon": name])) == DisplayIcons.custom)
    }

    @Test func callsAMixedOrIncompletePictureCustom() {
        let mixed = DisplayOverride.Picture([
            "display-icon": AppleArtwork.icons + "com.apple.studio-display.icns",
            "display-resolution-preview-icon": AppleArtwork.pictures + "com.apple.pro-display-xdr-landscape.tiff",
        ])
        #expect(DisplayIcons.skin(for: mixed) == DisplayIcons.custom)
        let largeElsewhere = DisplayOverride.Picture([
            "display-resolution-preview-icon": AppleArtwork.pictures + "com.apple.studio-display.tiff",
            "display-resolution-preview-icon-large": "/Users/someone/large.tiff",
        ])
        #expect(DisplayIcons.skin(for: largeElsewhere) == DisplayIcons.custom)
        #expect(DisplayIcons.skin(for: DisplayOverride.Picture(["display-icon": Data([1, 2])])) == DisplayIcons.custom)
        #expect(DisplayIcons.skin(for: DisplayOverride.Picture(["resolution-preview-x": 4])) == DisplayIcons.custom)
        #expect(DisplayIcons.skin(for: .none) == DisplayIcons.defaultSkin)
        #expect(DisplayIcons.skin(forIconPath: nil) == DisplayIcons.defaultSkin)
    }

    // MARK: - This Mac

    /// What this Mac offers names files that are on it, reads back as its skin, and covers
    /// each model whose picture is here and listed in Icons.plist.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: DisplayIcons.iconsFile.path(percentEncoded: false)), "no Icons.plist on this system"))
    func offersOnlyArtworkThisMacHas() throws {
        var listed = Set<String>()
        func collect(_ value: Any) {
            if let path = value as? String { listed.insert((path as NSString).lastPathComponent) }
            if let dictionary = value as? [String: Any] { dictionary.values.forEach(collect) }
        }
        collect(try PropertyListSerialization.propertyList(from: Data(contentsOf: DisplayIcons.iconsFile), format: nil))
        for skin in DisplayIcons.skins {
            guard let picture = DisplayIcons.system.picture(forSkin: skin) else { continue }
            #expect(DisplayIcons.skin(for: picture) == skin)
            for case let path as String in picture.dictionary.values {
                #expect(FileManager.default.fileExists(atPath: path), "\(skin): \(path)")
            }
        }
        for (skin, models) in DisplayIcons.models {
            let shipped = models.contains { model in
                FileManager.default.fileExists(atPath: AppleArtwork.pictures + model.pictureName) && listed.contains(model.pictureName)
            }
            if shipped { #expect(DisplayIcons.system.picture(forSkin: skin)?.previewImage != nil, "\(skin)") }
        }
        #expect(!DisplayIcons.system.isAvailable("ultrawide"))
        #expect(!DisplayIcons.system.isAvailable("tv"))
    }
}

@Suite struct DisplayOverridePictureTests {
    let key = OverrideKey(vendorID: 0x10AC, productID: 0x42A3)

    /// A file another tool wrote, with keys Resolute does not edit.
    var file: [String: Any] {
        [
            "DisplayProductName": "DELL U2723QE",
            "DisplayVendorID": 4268,
            "IODisplayEDID": Data([0, 255, 255, 255]),
            "scale-resolutions": [hexData("00000f00 00000870 00000009 00a00000"), hexData("00000f00 00000870")],
            "target-default-ppmm": 10.01,
        ]
    }

    func written(_ override: DisplayOverride) throws -> [String: Any] {
        try #require(try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any])
    }

    @Test func writesThePictureWithEveryOtherKey() throws {
        var override = try DisplayOverride(key: key, propertyList: PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0))
        #expect(override.picture == .none)
        let studio = try #require(AppleArtwork.library().picture(forSkin: "studioDisplay"))
        override.picture = studio
        let result = try written(override)
        #expect(AppleArtwork.same(result.filter { !DisplayOverride.Picture.isPictureKey($0.key) }, file))
        #expect(AppleArtwork.same(result.filter { DisplayOverride.Picture.isPictureKey($0.key) }, studio.dictionary))

        let reread = try override.readBack()
        #expect(reread.picture == studio)
        #expect(reread.displayIcon == AppleArtwork.icons + "com.apple.studio-display.icns")
        #expect(reread.productName == "DELL U2723QE")
        #expect(reread.resolutions == override.resolutions)
        #expect(!reread.otherKeys.keys.contains { DisplayOverride.Picture.isPictureKey($0) })
    }

    @Test func clearsThePictureAndKeepsTheRest() throws {
        let pictured = AppleArtwork.merged(file, try #require(AppleArtwork.library().picture(forSkin: "proDisplayXDR")).dictionary)
        var override = try DisplayOverride(key: key, propertyList: PropertyListSerialization.data(fromPropertyList: pictured, format: .xml, options: 0))
        #expect(DisplayIcons.skin(for: override.picture) == "proDisplayXDR")
        override.picture = try #require(AppleArtwork.library().picture(forSkin: "display"))
        #expect(AppleArtwork.same(try written(override), file))
    }

    /// A picture Resolute did not write goes back byte for byte, as the type of each value
    /// is part of the file: a real stays a real and data stays data.
    @Test func keepsAPictureItDoesNotKnowExactly() throws {
        let custom: [String: Any] = [
            "display-icon": "/Users/someone/Pictures/Monitor.icns",
            "display-resolution-preview-icon": "/Users/someone/Pictures/Monitor.tiff",
            "resolution-preview-x": 48.5, "resolution-preview-y": 64, "resolution-preview-width": 130, "resolution-preview-height": 81,
            "resolution-corner-radius": Data([6]),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: AppleArtwork.merged(file, custom), format: .xml, options: 0)
        var override = try DisplayOverride(key: key, propertyList: data)
        #expect(DisplayIcons.skin(for: override.picture) == DisplayIcons.custom)
        #expect(override.displayIcon == "/Users/someone/Pictures/Monitor.icns")
        override.productName = "Renamed"
        let text = try #require(String(data: try override.propertyListData(), encoding: .utf8))
        #expect(text.contains("<key>resolution-preview-x</key>\n\t<real>48.5</real>"))
        #expect(text.contains("<key>resolution-preview-y</key>\n\t<integer>64</integer>"))
        #expect(text.contains("<key>resolution-corner-radius</key>\n\t<data>\n\tBg==\n\t</data>"))
        #expect(AppleArtwork.same(try written(override), AppleArtwork.merged(file, custom, ["DisplayProductName": "Renamed"])))
    }

    @Test func setsTheIconAlone() throws {
        var override = DisplayOverride(key: key, picture: try #require(AppleArtwork.library().picture(forSkin: "iMac")))
        override.displayIcon = "/Users/someone/Pictures/Monitor.icns"
        #expect(override.picture.previewImage == AppleArtwork.pictures + "com.apple.imac-2021-silver.tiff")
        #expect(try written(override)["display-icon"] as? String == "/Users/someone/Pictures/Monitor.icns")
        override.displayIcon = nil
        #expect(!override.picture.keys.contains("display-icon"))
        #expect(override.picture.keys.contains("display-resolution-preview-icon"))
    }

    /// The density RDM gave new files comes with resolutions, not with a picture.
    @Test func writesAPictureAloneWithoutADensity() throws {
        let picture = try #require(AppleArtwork.library().picture(forSkin: "studioDisplay"))
        let result = try written(DisplayOverride(key: key, productName: "Studio", picture: picture))
        #expect(result["target-default-ppmm"] == nil)
        #expect(Set(result.keys) == Set(picture.keys + ["DisplayProductName"]))
    }

    @Test(arguments: [
        ("display-icon", true), ("display-resolution-preview-icon", true), ("display-resolution-preview-icon-large", true),
        ("display-resolution-preview-icon-90", true), ("resolution-preview-x", true), ("resolution-preview-height-270", true),
        ("resolution-corner-radius", true), ("DisplayProductName", false), ("scale-resolutions", false),
        ("target-default-ppmm", false), ("display-refresh-rate-policy", false), ("DisplayIsTV", false),
    ])
    func tellsPictureKeysFromTheOthers(key: String, isPicture: Bool) {
        #expect(DisplayOverride.Picture.isPictureKey(key) == isPicture)
        #expect(DisplayOverride.Picture([key: 1]).isEmpty == !isPicture)
    }
}

/// `#expect` cannot change what it checks, so each choice is made first and checked after.
@Suite struct OverrideDraftChangeTests {
    let key = OverrideKey(vendorID: 0x10AC, productID: 0x42A3)
    let library = AppleArtwork.library()

    @Test func describesASingleChangeByWhatChanged() {
        var draft = OverrideDraft(DisplayOverride(key: key, productName: "DELL U2723QE"))
        #expect(draft.changes.isEmpty)
        #expect(draft.changeSummary == nil)
        let chosen = draft.setPicture(skin: "studioDisplay", using: library)
        #expect(chosen)
        #expect(draft.changes == [.picture])
        #expect(draft.changeSummary == "1 unsaved change: picture")
        #expect(draft.pictureSkin == "studioDisplay")

        var renamed = OverrideDraft(DisplayOverride(key: key))
        renamed.setName("Studio")
        #expect(renamed.changeSummary == "1 unsaved change: name")
    }

    /// Adding a HiDPI entry with its 1× entry is two changes, as the Custom Resolutions page shows.
    @Test func countsEachEntryAddedOrRemoved() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        try draft.add(.hiDPI(width: 3008, height: 1692, flags: .standard))
        #expect(draft.changes == [.added(.standard(width: 6016, height: 3384)), .added(.hiDPI(width: 3008, height: 1692, flags: .standard))])
        #expect(draft.changeSummary == "2 unsaved changes")

        var paired = OverrideDraft(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)], isNew: false))
        try paired.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        #expect(paired.changeSummary == "1 unsaved change: 1280 × 720 HiDPI added")
        paired.markSaved()
        paired.remove([.standard(width: 2560, height: 1440)])
        #expect(paired.changeSummary == "1 unsaved change: 2560 × 1440 1× removed")

        let apples = ScaleResolution.preserved(.data(hexData("00000a00 00000640 00000001")))
        var copy = OverrideDraft(DisplayOverride(key: key, resolutions: [apples]))
        copy.remove([apples])
        #expect(copy.changeSummary == "1 unsaved change: 1280 × 800 HiDPI removed")
    }

    @Test func countsThePictureAndTheNameApart() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        let chosen = draft.setPicture(skin: "proDisplayXDR", using: library)
        #expect(chosen)
        draft.setName("Studio")
        try draft.add(.standard(width: 1920, height: 1080))
        #expect(draft.changes == [.picture, .name, .added(.standard(width: 1920, height: 1080))])
        #expect(draft.changeSummary == "3 unsaved changes")
    }

    @Test func revertDropsThePictureAndTheName() throws {
        let saved = DisplayOverride(key: key, productName: "Studio", picture: try #require(library.picture(forSkin: "iMac")))
        var draft = OverrideDraft(saved)
        var chosen = draft.setPicture(skin: "display", using: library)
        #expect(chosen)
        draft.setName(nil)
        #expect(draft.changeSummary == "2 unsaved changes")
        draft.revert()
        #expect(draft.working == saved)
        #expect(!draft.hasChanges)
        #expect(draft.changeSummary == nil)

        chosen = draft.setPicture(skin: "macBookPro", using: library)
        #expect(chosen)
        draft.markSaved()
        #expect(draft.changes.isEmpty)
        #expect(draft.saved.picture == library.picture(forSkin: "macBookPro"))
    }

    /// Going back to what the file shows is no change, even for a picture Resolute did not
    /// write or one written from other artwork.
    @Test func goingBackToTheSavedPictureIsNoChange() throws {
        let custom = DisplayOverride.Picture(["display-icon": "/Users/someone/Pictures/Monitor.icns"])
        var draft = OverrideDraft(DisplayOverride(key: key, picture: custom))
        #expect(draft.pictureSkin == DisplayIcons.custom)
        var chosen = draft.setPicture(skin: "studioDisplay", using: library)
        #expect(chosen && draft.hasChanges)
        chosen = draft.setPicture(skin: DisplayIcons.custom, using: library)
        #expect(chosen)
        #expect(draft.working.picture == custom)
        #expect(!draft.hasChanges)

        // Written on another macOS, where the picture's rectangle was different.
        let older = DisplayOverride.Picture(AppleArtwork.merged(
            AppleArtwork.entry("com.apple.studio-display.tiff", [4, 70, 238, 136]), ["display-icon": AppleArtwork.icons + "com.apple.studio-display.icns"]
        ))
        var studio = OverrideDraft(DisplayOverride(key: key, picture: older))
        chosen = studio.setPicture(skin: "studioDisplay", using: library)
        #expect(chosen && !studio.hasChanges)
        chosen = studio.setPicture(skin: "tv", using: library)
        #expect(!chosen)
        chosen = studio.setPicture(skin: "proDisplayXDR", using: library)
        #expect(chosen && studio.hasChanges)
        chosen = studio.setPicture(skin: "studioDisplay", using: library)
        #expect(chosen)
        #expect(studio.working.picture == older)
        #expect(!studio.hasChanges)
    }

    @Test func refusesASkinThisMacHasNoArtworkFor() {
        var draft = OverrideDraft(DisplayOverride(key: key))
        for skin in ["ultrawide", "tv"] {
            let chosen = draft.setPicture(skin: skin, using: library)
            #expect(!chosen)
        }
        #expect(!draft.hasChanges)
        #expect(draft.pictureSkin == "display")
    }

    /// An empty name is not written, so it keeps the display's own, as none does.
    @Test func treatsABlankNameAsNone() {
        var draft = OverrideDraft(DisplayOverride(key: key))
        for blank in [nil, "", "   ", "\n"] as [String?] {
            draft.setName(blank)
            #expect(draft.working.productName == nil)
            #expect(!draft.hasChanges)
        }
        draft.working.productName = ""
        #expect(!draft.hasChanges)
        draft.setName("Studio ")
        #expect(draft.working.productName == "Studio ")
        #expect(draft.changes == [.name])
    }

    /// Removing an entry from a list in Apple's order and adding it back puts it last.
    @Test func notesEntriesInAnotherOrder() throws {
        let entries: [ScaleResolution] = [
            .hiDPI(width: 1280, height: 800, flags: .standard), .standard(width: 1920, height: 1080), .standard(width: 2560, height: 1600),
        ]
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: entries))
        draft.remove([.standard(width: 1920, height: 1080)])
        try draft.add(.standard(width: 1920, height: 1080))
        #expect(draft.changes == [.reordered])
        #expect(draft.changeSummary == "1 unsaved change: order of resolutions")
    }

    @Test func notesKeysChangedOutsideTheEditors() {
        var draft = OverrideDraft(DisplayOverride(key: key))
        draft.working.otherKeys = PropertyListDictionary(["target-default-ppmm": 10.01])
        #expect(draft.changes == [.otherSettings])
        #expect(draft.changeSummary == "1 unsaved change: other settings")
    }
}
