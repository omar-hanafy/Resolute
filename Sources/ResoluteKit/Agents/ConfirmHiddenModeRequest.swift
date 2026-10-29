import Foundation

/// The command asks the app for a person at the display to keep a hidden mode on trial.
/// The command has already switched; it puts the previous mode back itself unless a person
/// keeps the new one.
public struct ConfirmHiddenModeRequest: Codable, Equatable, Sendable {
    /// The display on trial: its name for the dialog, and what the app needs to find its
    /// screen and show the dialog there.
    public struct DisplayReference: Codable, Equatable, Sendable {
        public var name: String
        /// CoreGraphics' ID for the display in this login session.
        public var id: UInt32
        public var vendorID: UInt32
        public var productID: UInt32
        /// 0 when the display reports none.
        public var serialNumber: UInt32

        public init(name: String, id: UInt32, vendorID: UInt32, productID: UInt32, serialNumber: UInt32) {
            self.name = name
            self.id = id
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = serialNumber
        }

        public init(_ display: Display) {
            self.init(
                name: display.name, id: display.id, vendorID: display.vendorID, productID: display.productID,
                serialNumber: display.serialNumber
            )
        }
    }

    public var display: DisplayReference
    /// The mode on trial, as people read it: "2880 × 1620".
    public var mode: String
    public var modeID: Int32
    /// The mode that comes back unless a person keeps the trial; nil when it is unknown.
    public var previousMode: String?
    public var previousModeID: Int32?
    /// How long the dialog waits for a person before the mode reverts.
    public var trialSeconds: Int
    /// Who asked, for the dialog to name.
    public var requester: Requester

    public init(
        display: DisplayReference,
        mode: String,
        modeID: Int32,
        previousMode: String?,
        previousModeID: Int32?,
        trialSeconds: Int,
        requester: Requester
    ) {
        self.display = display
        self.mode = mode
        self.modeID = modeID
        self.previousMode = previousMode
        self.previousModeID = previousModeID
        self.trialSeconds = trialSeconds
        self.requester = requester
    }

    /// A request to try `mode` on `display`, whose current mode is `previous`, worded as the
    /// dialog shows it.
    public init(
        display: Display, trying mode: DisplayMode, previous: DisplayMode?, trialSeconds: Int, requester: Requester
    ) {
        self.init(
            display: DisplayReference(display),
            mode: Self.describe(mode, distinctFrom: previous),
            modeID: mode.modeID,
            previousMode: previous.map { Self.describe($0, distinctFrom: mode) },
            previousModeID: previous?.modeID,
            trialSeconds: trialSeconds,
            requester: requester
        )
    }

    /// "2880 × 1620". The refresh rate, then HiDPI or 1×, are added only when `other` has the
    /// same size, so a dialog never offers to go from one size back to the same size.
    public static func describe(_ mode: DisplayMode, distinctFrom other: DisplayMode?) -> String {
        guard let other, other.width == mode.width, other.height == mode.height else { return mode.sizeText }
        let rate = RefreshRate.format(mode.refreshRate)
        if mode.refreshKey != other.refreshKey, !rate.isEmpty {
            return "\(mode.sizeText) @ \(rate)"
        }
        if mode.isHiDPI != other.isHiDPI {
            return mode.sizeText + (mode.isHiDPI ? " HiDPI" : " 1×")
        }
        return mode.sizeText
    }

    /// Throws `invalidRequest` for a value no dialog should show: an empty name, text too
    /// long to read, or a trial outside `AgentChannel.trialSecondsRange`.
    public func validate() throws {
        func check(_ text: String?, _ field: String, required: Bool = false) throws {
            guard let text else { return }
            if required, text.trimmingCharacters(in: .whitespaces).isEmpty {
                throw AgentChannelError.invalidRequest("\(field) is empty")
            }
            if text.count > 200 { throw AgentChannelError.invalidRequest("\(field) is longer than 200 characters") }
        }
        try check(display.name, "the display name", required: true)
        try check(mode, "the mode", required: true)
        try check(previousMode, "the previous mode")
        try check(requester.agent, "the requester's name")
        try check(requester.app, "the requester's app")
        guard AgentChannel.trialSecondsRange.contains(trialSeconds) else {
            throw AgentChannelError.invalidRequest("a trial of \(trialSeconds) seconds is out of bounds")
        }
    }

    enum CodingKeys: String, CodingKey {
        case display, mode, modeID, previousMode, previousModeID, trialSeconds, requester
    }

    /// Every key, with null for what is unknown, so each message has the same shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(display, forKey: .display)
        try container.encode(mode, forKey: .mode)
        try container.encode(modeID, forKey: .modeID)
        try container.encode(previousMode, forKey: .previousMode)
        try container.encode(previousModeID, forKey: .previousModeID)
        try container.encode(trialSeconds, forKey: .trialSeconds)
        try container.encode(requester, forKey: .requester)
    }
}

/// The app's answer to a `ConfirmHiddenModeRequest`. Made only through the factories below,
/// so a keep is always a person's: a dialog that runs out or goes away reverts.
public struct ConfirmHiddenModeResponse: Codable, Equatable, Sendable {
    public enum Answer: String, Codable, Sendable {
        case keep
        case revert
    }

    /// Who answered.
    public enum Answerer: String, Codable, Sendable {
        case person
    }

    public let answer: Answer
    /// Nil when nobody answered.
    public let by: Answerer?
    /// Why the mode reverts, in words for the command to report: "reverted by person",
    /// "no answer in 15 s". Nil for a keep.
    public let reason: String?

    private init(answer: Answer, by: Answerer?, reason: String?) {
        self.answer = answer
        self.by = by
        self.reason = reason
    }

    /// A person chose Keep.
    public static let keptByPerson = Self(answer: .keep, by: .person, reason: nil)
    /// A person chose Revert, or pressed Return or Esc.
    public static let revertedByPerson = Self(answer: .revert, by: .person, reason: "reverted by person")

    /// Nobody answered before the countdown of `seconds` ran out.
    public static func noAnswer(after seconds: Int) -> Self {
        Self(answer: .revert, by: nil, reason: "no answer in \(seconds) s")
    }

    /// The app reverts for a reason of its own, such as a display it can't find.
    public static func reverted(because reason: String) -> Self {
        Self(answer: .revert, by: nil, reason: reason)
    }

    enum CodingKeys: String, CodingKey {
        case answer, by, reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let answer = try container.decode(Answer.self, forKey: .answer)
        let by = try container.decodeIfPresent(Answerer.self, forKey: .by)
        // Only a person can keep a hidden mode; anything else that says keep is not trusted.
        guard answer == .revert || by == .person else {
            throw AgentChannelError.unreadableMessage("a keep must come from a person")
        }
        self.init(answer: answer, by: by, reason: try container.decodeIfPresent(String.self, forKey: .reason))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answer, forKey: .answer)
        try container.encode(by, forKey: .by)
        try container.encode(reason, forKey: .reason)
    }
}
