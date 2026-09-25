import Foundation

/// The two flag words stored with a HiDPI `scale-resolutions` entry.
public struct HiDPIFlags: Hashable, Sendable, CustomStringConvertible {
    public var primary: UInt32
    public var secondary: UInt32

    public init(primary: UInt32, secondary: UInt32) {
        self.primary = primary
        self.secondary = secondary
    }

    /// The combination Apple uses for most HiDPI entries in its own override files.
    public static let standard = HiDPIFlags(primary: 0x0000_0009, secondary: 0x00A0_0000)

    /// Bit 0 of the first word marks an entry as HiDPI.
    public static let hiDPIBit: UInt32 = 0x1

    /// "00000009 00a00000"
    public var description: String {
        String(format: "%08x %08x", primary, secondary)
    }

    /// Parses "00000009 00a00000", "0x9 0xa00000", "9,a00000" or "0000000900a00000".
    public init(parsing text: String) throws {
        func word(_ text: Substring) -> UInt32? {
            let digits = text.lowercased().hasPrefix("0x") ? text.dropFirst(2) : text
            guard !digits.isEmpty, digits.count <= 8 else { return nil }
            return UInt32(digits, radix: 16)
        }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        if words.count == 2, let primary = word(words[0]), let secondary = word(words[1]) {
            self.init(primary: primary, secondary: secondary)
        } else if words.count == 1, words[0].count == 16, let value = UInt64(words[0], radix: 16) {
            self.init(primary: UInt32(value >> 32), secondary: UInt32(value & 0xFFFF_FFFF))
        } else {
            throw ResoluteError.invalidFlags(text)
        }
    }
}

/// One element of a display override's `scale-resolutions` array.
public enum ScaleResolution: Hashable, Sendable {
    /// A HiDPI mode. Sizes are in points; the file stores twice as many pixels.
    case hiDPI(width: Int, height: Int, flags: HiDPIFlags)
    /// A 1× mode, in pixels.
    case standard(width: Int, height: Int)
    /// An element Resolute does not interpret; written back unchanged.
    case preserved(PreservedEntry)

    /// Reads a command-line entry: "1680x1050" (HiDPI unless `standard`), "1680x1050@2x"
    /// or "1680x1050@1x". Refresh rates and other scales are rejected.
    public init(parsing text: String, standard: Bool = false, flags: HiDPIFlags? = nil) throws {
        let query = try ModeQuery(resolution: text)
        guard let width = query.width, let height = query.height else {
            throw ResoluteError.invalidResolution(text)
        }
        if let refreshRate = query.refreshRate {
            throw ResoluteError.invalidEntry(
                "Override entries have no refresh rate; remove the @\(RefreshRate.format(refreshRate)) part."
            )
        }
        let hiDPI: Bool
        switch query.scale {
        case nil: hiDPI = !standard
        case 1: hiDPI = false
        case 2:
            guard !standard else {
                throw ResoluteError.invalidEntry("\(text) asks for HiDPI, but --standard asks for 1×.")
            }
            hiDPI = true
        default:
            throw ResoluteError.invalidEntry("Use @1x or @2x.")
        }
        if hiDPI {
            self = .hiDPI(width: width, height: height, flags: flags ?? .standard)
        } else {
            guard flags == nil else { throw ResoluteError.invalidEntry("Flags apply only to HiDPI entries.") }
            self = .standard(width: width, height: height)
        }
    }

    public var isEditable: Bool {
        if case .preserved = self { return false }
        return true
    }

    /// The mode this entry stands for: itself, or the mode a kept entry names (see
    /// `PreservedEntry.describedMode`).
    public var describedMode: ScaleResolution? {
        if case .preserved(let entry) = self { return entry.describedMode }
        return self
    }

    /// "2560 × 1080"
    public var sizeText: String {
        switch self {
        case .hiDPI(let width, let height, _), .standard(let width, let height):
            "\(width) × \(height)"
        case .preserved(let entry):
            entry.describedMode?.sizeText ?? entry.summary
        }
    }

    /// "HiDPI", "1×" or "Kept as is"
    public var kindText: String {
        switch self {
        case .hiDPI: "HiDPI"
        case .standard: "1×"
        case .preserved(let entry): entry.describedMode?.kindText ?? "Kept as is"
        }
    }

    /// The pixels macOS renders for this entry.
    public var pixelSize: (width: Int, height: Int)? {
        switch self {
        case .hiDPI(let width, let height, _): (width * 2, height * 2)
        case .standard(let width, let height): (width, height)
        case .preserved(let entry): entry.describedMode?.pixelSize
        }
    }

    /// "2560 × 1080 HiDPI (5120 × 2160 px, flags 0000000b 00a00000)"
    public var summary: String {
        switch self {
        case .hiDPI(let width, let height, let flags):
            "\(width) × \(height) HiDPI (\(width * 2) × \(height * 2) px, flags \(flags))"
        case .standard(let width, let height):
            "\(width) × \(height) 1×"
        case .preserved(let entry):
            switch entry.describedMode {
            case .hiDPI(let width, let height, _)?:
                "\(width) × \(height) HiDPI (\(width * 2) × \(height * 2) px, a 12-byte entry kept as is)"
            case .standard(let width, let height)?:
                "\(width) × \(height) 1× (a 12-byte entry kept as is)"
            default:
                "\(entry.summary), kept as is"
            }
        }
    }

    /// Same kind and size, whatever the flags or the form the entry is written in.
    public func sameMode(as other: ScaleResolution) -> Bool {
        switch (describedMode, other.describedMode) {
        case let (.hiDPI(lhsWidth, lhsHeight, _)?, .hiDPI(rhsWidth, rhsHeight, _)?),
             let (.standard(lhsWidth, lhsHeight)?, .standard(rhsWidth, rhsHeight)?):
            lhsWidth == rhsWidth && lhsHeight == rhsHeight
        default:
            false
        }
    }
}

/// A `scale-resolutions` element kept byte for byte.
public enum PreservedEntry: Hashable, Sendable {
    case data(Data)
    /// A non-data property-list value, archived as a binary property list.
    case value(Data)

    var propertyListValue: Any {
        switch self {
        case .data(let data):
            return data
        case .value(let archive):
            return (try? PropertyListSerialization.propertyList(from: archive, format: nil)) ?? archive
        }
    }

    /// The mode a 12-byte entry names: pixel width, pixel height and a flags word whose
    /// bit 0 marks HiDPI, the form Apple's own override files use. Nil for anything else.
    public var describedMode: ScaleResolution? {
        guard case .data(let data) = self, data.count == 12 else { return nil }
        let words = ScaleResolutionCodec.words(data)
        guard words[0] > 0, words[1] > 0 else { return nil }
        guard words[2] & HiDPIFlags.hiDPIBit != 0 else {
            return .standard(width: Int(words[0]), height: Int(words[1]))
        }
        guard words[0] % 2 == 0, words[1] % 2 == 0 else { return nil }
        return .hiDPI(width: Int(words[0] / 2), height: Int(words[1] / 2), flags: HiDPIFlags(primary: words[2], secondary: 0))
    }

    public var summary: String {
        switch self {
        case .data(let data):
            let words = ScaleResolutionCodec.words(data)
            return words.count >= 2 ? "\(data.count)-byte entry \(words[0]) × \(words[1])" : "\(data.count)-byte entry"
        case .value:
            return "value \(propertyListValue)"
        }
    }
}

/// Reads and writes `scale-resolutions` arrays. What is listed is exactly what is written,
/// so an override reads back the way it was saved.
public enum ScaleResolutionCodec {
    /// Every element, once, in `canonicalOrder`.
    public static func decode(_ elements: [Any]) -> [ScaleResolution] {
        var seen = Set<ScaleResolution>()
        return canonicalOrder(elements.map(decodeElement).filter { seen.insert($0).inserted })
    }

    /// The elements for `entries`, in `canonicalOrder`.
    public static func encode(_ entries: [ScaleResolution]) -> [Any] {
        canonicalOrder(entries).map { entry -> Any in
            switch entry {
            case .standard(let width, let height):
                data([UInt32(width), UInt32(height)])
            case .hiDPI(let width, let height, let flags):
                data([UInt32(width * 2), UInt32(height * 2), flags.primary, flags.secondary])
            case .preserved(let element):
                element.propertyListValue
            }
        }
    }

    /// 1× entries, then HiDPI entries, each largest first as RDM wrote them (kept entries
    /// that name a mode sort with it), then the other elements in their original order.
    public static func canonicalOrder(_ entries: [ScaleResolution]) -> [ScaleResolution] {
        func rank(_ entry: ScaleResolution) -> Int {
            switch entry.describedMode {
            case .standard?: 0
            case .hiDPI?: 1
            case .preserved?, nil: 2
            }
        }
        return entries.enumerated().sorted { lhs, rhs in
            if rank(lhs.element) != rank(rhs.element) { return rank(lhs.element) < rank(rhs.element) }
            if let left = lhs.element.pixelSize, let right = rhs.element.pixelSize, left != right {
                return (left.width, left.height) > (right.width, right.height)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func decodeElement(_ element: Any) -> ScaleResolution {
        guard let data = element as? Data else {
            let archive = (try? PropertyListSerialization.data(fromPropertyList: element, format: .binary, options: 0)) ?? Data()
            return .preserved(.value(archive))
        }
        let words = words(data)
        switch data.count {
        case 8 where words[0] > 0 && words[1] > 0:
            return .standard(width: Int(words[0]), height: Int(words[1]))
        case 16 where words[2] & HiDPIFlags.hiDPIBit != 0
            && words[0] > 0 && words[1] > 0 && words[0] % 2 == 0 && words[1] % 2 == 0:
            return .hiDPI(
                width: Int(words[0] / 2), height: Int(words[1] / 2),
                flags: HiDPIFlags(primary: words[2], secondary: words[3])
            )
        default:
            return .preserved(.data(data))
        }
    }

    /// The big-endian 32-bit words in `data`.
    static func words(_ data: Data) -> [UInt32] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - bytes.count % 4, by: 4).map { index in
            UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16
                | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
        }
    }

    static func data(_ words: [UInt32]) -> Data {
        var bytes: [UInt8] = []
        for word in words {
            bytes += [UInt8(word >> 24), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)]
        }
        return Data(bytes)
    }
}
