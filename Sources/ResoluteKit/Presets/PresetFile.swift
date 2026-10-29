import Foundation

/// The presets file, `{"version": 1, "presets": [...]}`. Every key is written, with null
/// for what a preset leaves open. An entry that is not a preset this version can read is
/// kept as it was, so writing the file back never loses it.
enum PresetFile {
    /// The format this version of Resolute reads and writes.
    static let version = 1

    /// Why a file is not a presets file at all.
    struct Malformed: Error {
        var reason: String
    }

    /// Why an entry is not a preset Resolute can read, in words that follow "because".
    struct Invalid: LocalizedError {
        var reason: String

        var errorDescription: String? { reason }
    }

    /// Reads a file's contents. Empty contents hold no presets.
    static func library(from data: Data) throws -> PresetLibrary {
        let blank: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        guard !data.allSatisfy(blank.contains) else { return PresetLibrary() }
        let contents: DecodedContents
        do {
            contents = try JSONDecoder().decode(DecodedContents.self, from: data)
        } catch let error as Malformed {
            throw error
        } catch {
            throw Malformed(reason: reason(for: error, in: "the file"))
        }
        var entries: [PresetLibrary.Entry] = []
        for raw in contents.presets {
            do {
                let preset = try JSONDecoder().decode(Preset.self, from: try JSONEncoder().encode(raw))
                let readable = entries.compactMap(\.readable)
                if readable.contains(where: { $0.id == preset.id }) {
                    entries.append(.unreadable(raw, reason: "another preset has the same id"))
                } else if let twin = readable.first(where: { PresetName.same($0.name, preset.name) }) {
                    entries.append(.unreadable(raw, reason: "“\(twin.name)” already has that name"))
                } else {
                    entries.append(.preset(preset))
                }
            } catch {
                entries.append(.unreadable(raw, reason: reason(for: error, in: "the preset", isJSON: true)))
            }
        }
        return PresetLibrary(entries: entries, version: contents.version)
    }

    /// The file's contents for `library`, in the current format.
    static func data(for library: PresetLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let entries = library.entries.map { entry -> EncodedEntry in
            switch entry {
            case .preset(let preset): .preset(preset)
            case .unreadable(let raw, _): .raw(raw)
            }
        }
        return try encoder.encode(EncodedContents(version: version, presets: entries)) + Data("\n".utf8)
    }

    /// What a decoding error says, in words: "“displays.0.width” has the wrong type". An
    /// entry is known to be JSON already; Foundation also calls a number it can't hold, such
    /// as a negative serial number, invalid JSON, without saying where.
    static func reason(for error: any Error, in whole: String, isJSON: Bool = false) -> String {
        if let invalid = error as? Invalid { return invalid.reason }
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ keys: [any CodingKey]) -> String {
            keys.isEmpty ? whole : "“" + keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") + "”"
        }
        switch error {
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty && !isJSON
                ? "it is not valid JSON" : "\(path(context.codingPath)) has a value Resolute can’t read"
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])) is missing"
        case .typeMismatch(_, let context):
            return "\(path(context.codingPath)) has the wrong type"
        case .valueNotFound(_, let context):
            return "\(path(context.codingPath)) is null"
        @unknown default:
            return error.localizedDescription
        }
    }

    private enum EncodedEntry: Encodable {
        case preset(Preset)
        case raw(JSONValue)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .preset(let preset): try preset.encode(to: encoder)
            case .raw(let raw): try raw.encode(to: encoder)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, presets
    }

    private struct DecodedContents: Decodable {
        var version: Int
        /// Each entry as it is, to be read as a preset one at a time.
        var presets: [JSONValue]

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys>
            do {
                container = try decoder.container(keyedBy: CodingKeys.self)
            } catch DecodingError.typeMismatch {
                throw Malformed(reason: "it holds no presets object")
            }
            // A file written by hand may leave the version out; that is the first one.
            let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            guard version >= 1 else { throw Malformed(reason: "its version, \(version), is not one Resolute wrote") }
            self.version = version
            presets = try container.decodeIfPresent([JSONValue].self, forKey: .presets) ?? []
        }
    }

    private struct EncodedContents: Encodable {
        var version: Int
        var presets: [EncodedEntry]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(presets, forKey: .presets)
        }
    }
}

/// Any JSON value: how an entry Resolute cannot read is kept until the file is written back.
enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The entry's name, to say which preset could not be read.
    var name: String? {
        guard case .object(let object) = self, case .string(let name)? = object["name"] else { return nil }
        return name
    }
}

extension Preset: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, displays, mirroring, shortcut
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idText = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: idText) else {
            throw PresetFile.Invalid(reason: "its id, “\(idText)”, is not a UUID")
        }
        let name: String
        do {
            name = try PresetName.validated(try container.decode(String.self, forKey: .name))
        } catch PresetError.invalidName(_, let problem) {
            let reason = switch problem {
            case .empty: "it has no name"
            case .tooLong: "its name is longer than \(PresetName.maximumLength) characters"
            case .controlCharacters: "its name has a line break, a tab or another control character"
            }
            throw PresetFile.Invalid(reason: reason)
        }
        let displays = try container.decodeIfPresent([DisplaySetting].self, forKey: .displays) ?? []
        let mirroring = try container.decodeIfPresent(Bool.self, forKey: .mirroring)
        guard !displays.isEmpty || mirroring != nil else {
            throw PresetFile.Invalid(reason: "it sets no display and leaves mirroring as it is")
        }
        self.init(
            id: id, name: name, displays: displays, mirroring: mirroring,
            shortcut: try container.decodeIfPresent(KeyShortcut.self, forKey: .shortcut)
        )
    }

    /// Every key, with null for what the preset leaves open.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displays, forKey: .displays)
        try container.encode(mirroring, forKey: .mirroring)
        try container.encode(shortcut, forKey: .shortcut)
    }
}

extension DisplaySetting: Codable {
    enum CodingKeys: String, CodingKey {
        case name, vendorID, productID, serialNumber, isBuiltin, width, height, pixelWidth, pixelHeight, refreshRate
    }

    /// Reads a setting the way people may write one: the IDs, the serial number and being
    /// built in can be left out, and IDs may be hex strings, as `resolute displays --json`
    /// prints them, or numbers.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func id(_ key: CodingKeys) throws -> UInt32 {
            guard try container.decodeNil(forKey: key) == false else { return 0 }
            if let text = try? container.decode(String.self, forKey: key) {
                let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
                guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
                    throw PresetFile.Invalid(reason: "“\(key.stringValue)” is not a hexadecimal ID: “\(text)”")
                }
                return value
            }
            return try container.decode(UInt32.self, forKey: key)
        }
        func readSize(_ widthKey: CodingKeys, _ heightKey: CodingKeys) throws -> Size? {
            let width = try container.decodeIfPresent(Int.self, forKey: widthKey)
            let height = try container.decodeIfPresent(Int.self, forKey: heightKey)
            guard let width, let height else {
                guard width == nil, height == nil else {
                    throw PresetFile.Invalid(reason: "“\(widthKey.stringValue)” and “\(heightKey.stringValue)” go together")
                }
                return nil
            }
            guard (1...ModeQuery.maximumDimension).contains(width), (1...ModeQuery.maximumDimension).contains(height) else {
                throw PresetFile.Invalid(reason: "\(width) × \(height) is not a size a display has")
            }
            return Size(width: width, height: height)
        }

        let isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        guard isBuiltin || !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PresetFile.Invalid(reason: "a display that is not built in needs its name")
        }
        let reference = DisplayReference(
            vendorID: container.contains(.vendorID) ? try id(.vendorID) : 0,
            productID: container.contains(.productID) ? try id(.productID) : 0,
            serialNumber: try container.decodeIfPresent(UInt32.self, forKey: .serialNumber) ?? 0,
            isBuiltin: isBuiltin,
            name: name
        )
        let size = try readSize(.width, .height)
        let pixelSize = try readSize(.pixelWidth, .pixelHeight)
        guard pixelSize == nil || size != nil else {
            throw PresetFile.Invalid(reason: "a pixel size needs the size in points too")
        }
        let refreshRate = try container.decodeIfPresent(Double.self, forKey: .refreshRate)
        if let refreshRate, !ModeQuery.isPlausible(refreshRate: refreshRate) {
            throw PresetFile.Invalid(reason: "\(refreshRate) is not a refresh rate a display has")
        }
        guard size != nil || refreshRate != nil else {
            throw PresetFile.Invalid(reason: "it sets neither a resolution nor a refresh rate")
        }
        self.init(display: reference, size: size, pixelSize: pixelSize, refreshRate: refreshRate)
    }

    /// Every key, with null for what the setting leaves open. IDs are hex strings, as
    /// everywhere else in Resolute.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(display.name, forKey: .name)
        try container.encode(String(display.vendorID, radix: 16), forKey: .vendorID)
        try container.encode(String(display.productID, radix: 16), forKey: .productID)
        try container.encode(display.serialNumber, forKey: .serialNumber)
        try container.encode(display.isBuiltin, forKey: .isBuiltin)
        try container.encode(size?.width, forKey: .width)
        try container.encode(size?.height, forKey: .height)
        try container.encode(pixelSize?.width, forKey: .pixelWidth)
        try container.encode(pixelSize?.height, forKey: .pixelHeight)
        try container.encode(refreshRate, forKey: .refreshRate)
    }
}

extension KeyShortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case key, modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        let names = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        guard let modifiers = Modifiers(names: names) else {
            throw PresetFile.Invalid(
                reason: "the shortcut’s modifiers are control, option, shift and command, not \(names.joined(separator: ", "))"
            )
        }
        guard let shortcut = KeyShortcut(key: key, modifiers: modifiers) else {
            throw PresetFile.Invalid(reason: "the shortcut’s key, “\(key)”, is not a key")
        }
        self = shortcut
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.names, forKey: .modifiers)
    }
}
