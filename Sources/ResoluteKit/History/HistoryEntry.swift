import CoreGraphics
import Foundation

/// One display change in History: when it happened, where it was asked for, what changed
/// and how it ended. The app and the `resolute` command append these to one file, so a
/// change an agent makes shows up next to the person's own.
public struct HistoryEntry: Identifiable, Hashable, Sendable {
    /// The format of a stored entry. Readers skip entries written in a newer format.
    public static let formatVersion = 1

    public var id: UUID
    public var date: Date
    public var source: Source
    public var change: Change
    public var outcome: Outcome
    /// The login the change was made in (`LoginSession.current`). A hidden mode belongs to
    /// the login it was tried in, so Undo puts one back only in that login.
    public var loginSession: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        source: Source,
        change: Change,
        outcome: Outcome,
        loginSession: String? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.change = change
        self.outcome = outcome
        self.loginSession = loginSession
    }

    /// Whether the change switched to a mode macOS hides.
    public var isHiddenMode: Bool { change.isHiddenMode }

    /// Where a change was asked for.
    public enum Source: Hashable, Sendable {
        /// The menu bar panel.
        case panel
        /// The classic menu, opened with a right-click on the menu bar icon.
        case menu
        /// The Resolute window.
        case window
        /// Resolute's Dock menu.
        case dock
        /// A keyboard shortcut that works from anywhere, such as a preset's.
        case keyboard
        /// A person running `resolute` in a terminal app; nil when the app is unknown.
        case terminal(app: String?)
        /// An agent such as Claude Code running `resolute`, in an app; nil when unknown.
        case agent(name: String, app: String?)
        /// A Shortcuts action.
        case shortcuts
        /// A preset, applied from `via`. Each change the preset makes is its own entry, so
        /// each can be undone on its own.
        indirect case preset(name: String, via: Source)

        /// Where the request came from, looking past a preset.
        public var origin: Source {
            if case .preset(_, let via) = self { return via.origin }
            return self
        }

        /// The preset that made the change, if one did.
        public var presetName: String? {
            if case .preset(let name, _) = self { return name }
            return nil
        }

        /// The History filter the change belongs to.
        public var category: HistoryFilter.Category {
            switch self {
            case .panel, .menu, .window, .dock, .keyboard: .panel
            case .terminal, .agent: .terminalAndAgents
            case .shortcuts: .shortcuts
            case .preset(_, let via): via.category
            }
        }
    }

    /// What changed.
    public enum Change: Hashable, Sendable {
        /// A display switched to another mode, including another refresh rate only.
        case mode(ModeChange)
        /// Mirroring turned on or off.
        case mirroring(MirroringChange)

        /// Whether the change switched to a mode macOS hides.
        public var isHiddenMode: Bool {
            if case .mode(let change) = self { return change.to.isHidden }
            return false
        }
    }

    /// A display's switch from one mode to another.
    public struct ModeChange: Hashable, Sendable {
        public var display: DisplayRecord
        /// The mode before the switch; nil when macOS did not say which it was.
        public var from: ModeRecord?
        public var to: ModeRecord

        public init(display: DisplayRecord, from: ModeRecord?, to: ModeRecord) {
            self.display = display
            self.from = from
            self.to = to
        }

        /// `display` as it was before the switch: its current mode is the one switched from.
        public init(display: Display, to mode: DisplayMode) {
            self.init(display: DisplayRecord(display), from: display.currentMode.map(ModeRecord.init), to: ModeRecord(mode))
        }
    }

    /// Mirroring turned on or off for these displays.
    public struct MirroringChange: Hashable, Sendable {
        public var isOn: Bool
        public var displays: [DisplayRecord]

        public init(isOn: Bool, displays: [DisplayRecord]) {
            self.isOn = isOn
            self.displays = displays
        }
    }

    /// A display as it was at the time of the change: its name then, and what identifies it
    /// again after its ID changed.
    public struct DisplayRecord: Hashable, Sendable, Codable {
        public var id: CGDirectDisplayID
        public var name: String
        public var vendorID: UInt32
        public var productID: UInt32
        public var serialNumber: UInt32
        public var isBuiltin: Bool

        public init(
            id: CGDirectDisplayID, name: String, vendorID: UInt32 = 0, productID: UInt32 = 0,
            serialNumber: UInt32 = 0, isBuiltin: Bool = false
        ) {
            self.id = id
            self.name = name
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = serialNumber
            self.isBuiltin = isBuiltin
        }

        public init(_ display: Display) {
            self.init(
                id: display.id, name: display.name, vendorID: display.vendorID, productID: display.productID,
                serialNumber: display.serialNumber, isBuiltin: display.isBuiltin
            )
        }

        /// Whether `display` is the same hardware. Identical monitors without serial numbers
        /// can't be told apart this way.
        public func isSameHardware(as display: Display) -> Bool {
            vendorID == display.vendorID && productID == display.productID
                && serialNumber == display.serialNumber && isBuiltin == display.isBuiltin
        }
    }

    /// A mode as it was at the time of the change. Mode IDs can change when a display
    /// reconnects, so Undo looks for a mode of the same size, pixels and refresh rate.
    public struct ModeRecord: Hashable, Sendable {
        public var modeID: Int32
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var refreshRate: Double
        public var bitsPerSample: Int?
        public var ioFlags: UInt32
        public var isHidden: Bool

        public init(
            modeID: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double,
            bitsPerSample: Int? = nil, ioFlags: UInt32 = 0, isHidden: Bool = false
        ) {
            self.modeID = modeID
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.refreshRate = refreshRate
            self.bitsPerSample = bitsPerSample
            self.ioFlags = ioFlags
            self.isHidden = isHidden
        }

        public init(_ mode: DisplayMode) {
            self.init(
                modeID: mode.modeID, width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate, bitsPerSample: mode.bitsPerSample,
                ioFlags: mode.ioFlags, isHidden: mode.origin == .hidden
            )
        }

        /// "2560 × 1440"
        public var sizeText: String { "\(width) × \(height)" }
        public var isHiDPI: Bool { pixelWidth > width }
        /// The refresh rate in hundredths of a hertz, for comparisons.
        public var refreshKey: Int { RefreshRate.key(refreshRate) }

        /// Whether `mode` has this mode's size in points and pixels and its refresh rate.
        public func hasSameShape(as mode: DisplayMode) -> Bool {
            width == mode.width && height == mode.height && pixelWidth == mode.pixelWidth
                && pixelHeight == mode.pixelHeight && refreshKey == mode.refreshKey
        }
    }

    /// How a change ended.
    public enum Outcome: Hashable, Sendable {
        /// Saved straight away: a listed mode, or mirroring.
        case applied
        /// Tried, then kept and saved.
        case kept
        /// Kept until logout.
        case keptForSession
        /// Tried, then put back.
        case reverted(RevertReason)
        /// Undo of an earlier change, `of` its ID: what that change replaced is back.
        case undone(of: UUID)
        /// The switch did not happen, or did not finish.
        case failed(message: String)

        /// Whether the change is in place now, as far as History knows.
        public var tookEffect: Bool {
            switch self {
            case .applied, .kept, .keptForSession, .undone: true
            case .reverted, .failed: false
            }
        }

        /// The change this entry undid, for an Undo.
        public var undoneEntryID: UUID? {
            if case .undone(let id) = self { return id }
            return nil
        }
    }

    /// Why a mode on trial was put back.
    public enum RevertReason: String, Hashable, Sendable, CaseIterable {
        /// The trial ran out with nobody choosing Keep.
        case noAnswer
        /// Someone chose Revert.
        case declined
        /// The display went dark and got the previous mode back when it returned.
        case displayWentDark
        /// The display showed another mode by the time of the answer, so it was left as it was.
        case displayChanged
        /// Not known: the command line can't tell a declined trial from one nobody answered.
        case unspecified
    }
}

// MARK: - Stored form

// One entry per line, as a JSON object with "v" (the format) and "date" (ISO 8601 with
// milliseconds, UTC) first among equals: pruning reads only those two, so it keeps the
// entries a newer Resolute wrote until they are old.

extension HistoryEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case version = "v", id, date, source, change, outcome, loginSession = "session"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container, debugDescription: "History entries of format \(version) are not supported."
            )
        }
        id = try container.decode(UUID.self, forKey: .id)
        date = try HistoryDate.decode(container.decode(String.self, forKey: .date))
        source = try container.decode(Source.self, forKey: .source)
        change = try container.decode(Change.self, forKey: .change)
        outcome = try container.decode(Outcome.self, forKey: .outcome)
        loginSession = try container.decodeIfPresent(String.self, forKey: .loginSession)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(HistoryDate.encode(date), forKey: .date)
        try container.encode(source, forKey: .source)
        try container.encode(change, forKey: .change)
        try container.encode(outcome, forKey: .outcome)
        try container.encodeIfPresent(loginSession, forKey: .loginSession)
    }
}

extension HistoryEntry.Source: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, name, app, via
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "panel": self = .panel
        case "menu": self = .menu
        case "window": self = .window
        case "dock": self = .dock
        case "keyboard": self = .keyboard
        case "shortcuts": self = .shortcuts
        case "terminal": self = .terminal(app: try container.decodeIfPresent(String.self, forKey: .app))
        case "agent":
            self = .agent(
                name: try container.decode(String.self, forKey: .name), app: try container.decodeIfPresent(String.self, forKey: .app)
            )
        case "preset":
            self = .preset(name: try container.decode(String.self, forKey: .name), via: try container.decode(Self.self, forKey: .via))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown source “\(kind)”.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .panel: try container.encode("panel", forKey: .kind)
        case .menu: try container.encode("menu", forKey: .kind)
        case .window: try container.encode("window", forKey: .kind)
        case .dock: try container.encode("dock", forKey: .kind)
        case .keyboard: try container.encode("keyboard", forKey: .kind)
        case .shortcuts: try container.encode("shortcuts", forKey: .kind)
        case .terminal(let app):
            try container.encode("terminal", forKey: .kind)
            try container.encodeIfPresent(app, forKey: .app)
        case .agent(let name, let app):
            try container.encode("agent", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(app, forKey: .app)
        case .preset(let name, let via):
            try container.encode("preset", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(via, forKey: .via)
        }
    }
}

extension HistoryEntry.Change: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, display, from, to, isOn = "on", displays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "mode":
            self = .mode(HistoryEntry.ModeChange(
                display: try container.decode(HistoryEntry.DisplayRecord.self, forKey: .display),
                from: try container.decodeIfPresent(HistoryEntry.ModeRecord.self, forKey: .from),
                to: try container.decode(HistoryEntry.ModeRecord.self, forKey: .to)
            ))
        case "mirroring":
            self = .mirroring(HistoryEntry.MirroringChange(
                isOn: try container.decode(Bool.self, forKey: .isOn),
                displays: try container.decode([HistoryEntry.DisplayRecord].self, forKey: .displays)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown change “\(kind)”.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mode(let change):
            try container.encode("mode", forKey: .kind)
            try container.encode(change.display, forKey: .display)
            try container.encodeIfPresent(change.from, forKey: .from)
            try container.encode(change.to, forKey: .to)
        case .mirroring(let change):
            try container.encode("mirroring", forKey: .kind)
            try container.encode(change.isOn, forKey: .isOn)
            try container.encode(change.displays, forKey: .displays)
        }
    }
}

extension HistoryEntry.ModeRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case modeID, width, height, pixelWidth, pixelHeight, refreshRate, bitsPerSample, ioFlags, isHidden = "hidden"
    }
}

extension HistoryEntry.Outcome: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, reason, of, message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "applied": self = .applied
        case "kept": self = .kept
        case "keptForSession": self = .keptForSession
        case "reverted":
            // A reason a newer Resolute added reads as an unknown one, not as a broken entry.
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .reverted(reason.flatMap(HistoryEntry.RevertReason.init(rawValue:)) ?? .unspecified)
        case "undone": self = .undone(of: try container.decode(UUID.self, forKey: .of))
        case "failed": self = .failed(message: try container.decode(String.self, forKey: .message))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown outcome “\(kind)”.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .applied: try container.encode("applied", forKey: .kind)
        case .kept: try container.encode("kept", forKey: .kind)
        case .keptForSession: try container.encode("keptForSession", forKey: .kind)
        case .reverted(let reason):
            try container.encode("reverted", forKey: .kind)
            try container.encode(reason.rawValue, forKey: .reason)
        case .undone(let id):
            try container.encode("undone", forKey: .kind)
            try container.encode(id, forKey: .of)
        case .failed(let message):
            try container.encode("failed", forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Dates in stored entries: ISO 8601 in UTC, with milliseconds so that changes made in the
/// same second keep their order.
enum HistoryDate {
    static func encode(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func decode(_ text: String) throws -> Date {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        return try Date.ISO8601FormatStyle().parse(text)
    }
}
