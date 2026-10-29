import ArgumentParser
import Foundation
import ResoluteKit

/// `resolute history`: the changes History lists, newest first, as the app shows them.
struct HistoryCommand: ParsableCommand, ContextCommand {
    /// The History page's filters, as `--source` takes them.
    enum Source: String, ExpressibleByArgument, CaseIterable {
        case all, panel, terminal, shortcuts

        var filter: HistoryFilter {
            switch self {
            case .all: .all
            case .panel: .panel
            case .terminal: .terminalAndAgents
            case .shortcuts: .shortcuts
            }
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent display changes from the app, the command line and agents.",
        discussion: """
            Every switch from the panel, the menu, the resolute command and agents, newest first. \
            History keeps 7 days.
            """
    )

    @Flag(help: "Print JSON.")
    var json = false

    @Option(help: "Show at most this many changes.")
    var limit: Int?

    @Option(help: "all, panel (the app), terminal (the resolute command, typed or run by agents) or shortcuts.")
    var source: Source = .all

    func validate() throws {
        if let limit, limit < 1 {
            throw ValidationError("--limit takes 1 or more.")
        }
    }

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let timeline = HistoryTimeline(entries: try HistoryStore(locations: context.support).entries())
        var items = timeline.items(in: source.filter)
        if let limit { items = Array(items.prefix(limit)) }
        if json {
            context.write(try Output.json(items.map { HistoryRecord(item: $0, in: timeline) }))
            return
        }
        guard !items.isEmpty else {
            context.write(source.filter.emptyText)
            return
        }
        context.write(Self.render(items))
    }

    /// Two lines per change, like the History page's rows: the time, the status and the
    /// title, then where the change came from under the title.
    static func render(_ items: [HistoryItem]) -> String {
        let timeWidth = items.map(\.time.count).max() ?? 0
        let statusWidth = items.map(\.status.title.count).max() ?? 0
        let indent = String(repeating: " ", count: timeWidth + 2 + statusWidth + 2)
        func padded(_ text: String, to width: Int) -> String {
            text + String(repeating: " ", count: max(0, width - text.count))
        }
        return items.map { item in
            "\(padded(item.time, to: timeWidth))  \(padded(item.status.title, to: statusWidth))  \(item.title)\n\(indent)\(item.detail)"
        }.joined(separator: "\n")
    }
}

extension CommandContext {
    /// Adds this command's changes to the history the app shows, naming whoever ran it. A
    /// history that can't be written only warns: the change itself is done.
    var history: HistoryRecorder {
        let writeError = writeError
        return HistoryRecorder.commandLine(support: support, requester: requester()) { error in
            writeError("warning: The change could not be added to Resolute’s history: \(error.localizedDescription)")
        }
    }
}

/// A change as `history --json` prints it. Like every JSON object the commands print, it
/// has every key, with null for a missing value.
struct HistoryRecord: Encodable {
    /// A mode before or after a change.
    struct Mode: Encodable {
        let modeID: Int32
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Double
        let hidden: Bool

        init(_ mode: HistoryEntry.ModeRecord) {
            modeID = mode.modeID
            width = mode.width
            height = mode.height
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
            refreshRate = (mode.refreshRate * 1000).rounded() / 1000
            hidden = mode.isHidden
        }
    }

    let id: String
    let date: String
    /// panel, menu, window, dock, terminal, agent or shortcuts: where the request came from.
    let source: String
    let agent: String?
    let app: String?
    let preset: String?
    /// mode or mirroring.
    let change: String
    let display: String?
    let displayID: UInt32?
    let from: Mode?
    let to: Mode?
    /// True when mirroring was turned on, false when off; null for a mode change.
    let mirroring: Bool?
    let mirroredDisplays: [String]?
    let hiddenMode: Bool
    /// How this change ended: applied, kept, keptForSession, reverted, undone or failed.
    let outcome: String
    /// Why a reverted change was put back: noAnswer, declined, displayWentDark,
    /// displayChanged or unspecified.
    let reason: String?
    /// Why a failed change did not happen.
    let message: String?
    /// What History shows: kept, reverted, undone or failed.
    let status: String
    let canUndo: Bool
    let undoneAt: String?
    /// Where the Undo came from, as `source` says it.
    let undoneFrom: String?
    /// For an Undo whose change is no longer in History: that change's ID.
    let undoes: String?
    let title: String
    let detail: String

    init(item: HistoryItem, in timeline: HistoryTimeline) {
        let entry = item.entry
        let origin = entry.source.origin
        id = entry.id.uuidString
        date = ISO8601DateFormatter().string(from: entry.date)
        source = Self.kind(of: origin)
        switch origin {
        case .agent(let name, let app):
            agent = name
            self.app = app
        case .terminal(let app):
            agent = nil
            self.app = app
        default:
            agent = nil
            app = nil
        }
        preset = entry.source.presetName
        switch entry.change {
        case .mode(let change):
            self.change = "mode"
            display = change.display.name
            displayID = change.display.id
            from = change.from.map(Mode.init)
            to = Mode(change.to)
            mirroring = nil
            mirroredDisplays = nil
        case .mirroring(let change):
            self.change = "mirroring"
            display = nil
            displayID = nil
            from = nil
            to = nil
            mirroring = change.isOn
            mirroredDisplays = change.displays.map(\.name)
        }
        hiddenMode = entry.isHiddenMode
        outcome = Self.name(of: entry.outcome)
        if case .reverted(let why) = entry.outcome { reason = why.rawValue } else { reason = nil }
        if case .failed(let why) = entry.outcome { message = why } else { message = nil }
        // Listed only when the change it undid is gone; otherwise it is that change's status.
        undoes = entry.outcome.undoneEntryID?.uuidString
        status = item.status.rawValue
        canUndo = item.canUndo
        let undo = timeline.undo(of: entry)
        undoneAt = undo.map { ISO8601DateFormatter().string(from: $0.date) }
        undoneFrom = undo.map { Self.kind(of: $0.source.origin) }
        title = item.title
        detail = item.detail
    }

    static func name(of outcome: HistoryEntry.Outcome) -> String {
        switch outcome {
        case .applied: "applied"
        case .kept: "kept"
        case .keptForSession: "keptForSession"
        case .reverted: "reverted"
        case .undone: "undone"
        case .failed: "failed"
        }
    }

    static func kind(of source: HistoryEntry.Source) -> String {
        switch source {
        case .panel: "panel"
        case .menu: "menu"
        case .window: "window"
        case .dock: "dock"
        case .keyboard: "keyboard"
        case .terminal: "terminal"
        case .agent: "agent"
        case .shortcuts: "shortcuts"
        case .preset(_, let via): kind(of: via)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, date, source, agent, app, preset, change, display, displayID, from, to, mirroring, mirroredDisplays,
             hiddenMode, outcome, reason, message, status, canUndo, undoneAt, undoneFrom, undoes, title, detail
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(source, forKey: .source)
        try container.encode(agent, forKey: .agent)
        try container.encode(app, forKey: .app)
        try container.encode(preset, forKey: .preset)
        try container.encode(change, forKey: .change)
        try container.encode(display, forKey: .display)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(mirroring, forKey: .mirroring)
        try container.encode(mirroredDisplays, forKey: .mirroredDisplays)
        try container.encode(hiddenMode, forKey: .hiddenMode)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(reason, forKey: .reason)
        try container.encode(message, forKey: .message)
        try container.encode(status, forKey: .status)
        try container.encode(canUndo, forKey: .canUndo)
        try container.encode(undoneAt, forKey: .undoneAt)
        try container.encode(undoneFrom, forKey: .undoneFrom)
        try container.encode(undoes, forKey: .undoes)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
    }
}
