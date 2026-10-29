import Foundation

/// The History page's filters: All, Panel, Terminal & Agents and Shortcuts.
public enum HistoryFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case panel
    case terminalAndAgents
    case shortcuts

    /// Where a change came from, as the filters group it.
    public enum Category: String, Hashable, Sendable {
        /// The panel, the classic menu, the window or the Dock menu.
        case panel
        /// `resolute`, typed by a person or run by an agent.
        case terminalAndAgents
        /// A Shortcuts action.
        case shortcuts
    }

    /// The segment's label.
    public var title: String {
        switch self {
        case .all: "All"
        case .panel: "Panel"
        case .terminalAndAgents: "Terminal & Agents"
        case .shortcuts: "Shortcuts"
        }
    }

    public func includes(_ entry: HistoryEntry) -> Bool {
        switch self {
        case .all: true
        case .panel: entry.source.category == .panel
        case .terminalAndAgents: entry.source.category == .terminalAndAgents
        case .shortcuts: entry.source.category == .shortcuts
        }
    }

    /// The filters the History page offers for `entries`. Shortcuts actions are not built
    /// yet, so its filter shows only once History has a change from one, as a later
    /// Resolute may write.
    public static func offered(for entries: [HistoryEntry]) -> [HistoryFilter] {
        let hasShortcuts = entries.contains { $0.source.category == .shortcuts }
        return allCases.filter { $0 != .shortcuts || hasShortcuts }
    }

    /// What an empty list says.
    public var emptyText: String {
        switch self {
        case .all: "No display changes in the last 7 days."
        case .panel: "No display changes from the panel in the last 7 days."
        case .terminalAndAgents: "No display changes from Terminal or agents in the last 7 days."
        case .shortcuts: "No display changes from Shortcuts in the last 7 days."
        }
    }
}

/// How a change in History ended, as its badge says.
public enum HistoryStatus: String, Hashable, Sendable {
    /// In place: saved, kept, or kept until logout.
    case kept
    /// Tried, then put back.
    case reverted
    /// Undone later from History or the panel.
    case undone
    /// The switch did not happen.
    case failed

    public var title: String {
        switch self {
        case .kept: "Kept"
        case .reverted: "Reverted"
        case .undone: "Undone"
        case .failed: "Failed"
        }
    }

    /// The badge's tone, as the design system's Badge has them.
    public var tone: Tone {
        switch self {
        case .kept: .accent
        case .reverted, .undone: .neutral
        case .failed: .warning
        }
    }

    public enum Tone: String, Hashable, Sendable {
        case neutral, accent, warning
    }
}

/// The words History uses, as Figma has them (History 37:1957, History Row 36:445,
/// Activity Row 17:63).
public enum HistoryText {
    /// The History page's description.
    public static let pageDescription = "Every switch from the panel, the menu, the resolute command and agents. "
        + "Undo puts back what was there before; a hidden mode undone after logout cannot come back."
    /// The note under the list.
    public static let footnote = "History keeps 7 days. The resolute command writes here too, so agents’ changes are always visible."

    /// A row's title: "DELL U2723QE  2560 × 1440 → 2880 × 1620", "Built-in Retina Display
    /// 120 Hz → 60 Hz" for a change of refresh rate only, "Mirroring on: Built-in + DELL
    /// U2723QE". The name and the change are two spaces apart.
    public static func title(of change: HistoryEntry.Change) -> String {
        switch change {
        case .mode(let change):
            let shown = sides(of: change)
            guard let from = shown.from else { return "\(change.display.name) → \(shown.to)" }
            return "\(change.display.name)  \(from) → \(shown.to)"
        case .mirroring(let change):
            return mirroringTitle(change)
        }
    }

    /// The panel's shorter title, which names only what the display shows now:
    /// "DELL U2723QE → 2560 × 1440".
    public static func activityTitle(of change: HistoryEntry.Change) -> String {
        switch change {
        case .mode(let change): "\(change.display.name) → \(sides(of: change).to)"
        case .mirroring(let change): mirroringTitle(change)
        }
    }

    /// A row's second line: "From Claude Code (Terminal) · hidden mode · nobody answered",
    /// "From Shortcuts · “Presenting” preset".
    public static func detail(of entry: HistoryEntry) -> String {
        var parts = basicDetail(of: entry)
        if entry.isHiddenMode { parts.append("hidden mode") }
        switch entry.outcome {
        case .applied, .kept: break
        case .keptForSession: parts.append("until you log out")
        case .reverted(let reason): if let phrase = reason.phrase { parts.append(phrase) }
        case .failed(let message): parts.append(message)
        // Shown only when the change it undid is gone from History.
        case .undone: parts.append("undo of an earlier change")
        }
        return parts.joined(separator: " · ")
    }

    /// The panel's second line: "From Terminal · 2 min ago".
    public static func activityDetail(of entry: HistoryEntry, now: Date, timeZone: TimeZone = .current) -> String {
        (basicDetail(of: entry) + [relativeTime(of: entry.date, now: now, timeZone: timeZone)]).joined(separator: " · ")
    }

    /// "From the panel", "From Claude Code (Terminal)".
    public static func sourceText(_ source: HistoryEntry.Source) -> String {
        "From \(source.name)"
    }

    /// When a row's change happened: the time today ("9:41", or "9:41 AM" where clocks use
    /// 12 hours), "Yesterday", the weekday within the week, then the date ("19 Oct").
    public static func time(of date: Date, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let calendar = Self.calendar(timeZone)
        // Resolute's words are English; times and dates keep the person's own conventions.
        let english = Locale(languageCode: .english, languageRegion: locale.region)
        switch days(from: date, to: now, in: calendar) {
        case ...0:
            let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
            return date.formatted(style)
        case 1:
            return "Yesterday"
        case 2...6:
            return date.formatted(Date.FormatStyle(locale: english, calendar: calendar, timeZone: timeZone).weekday(.wide))
        default:
            return date.formatted(Date.FormatStyle(locale: english, calendar: calendar, timeZone: timeZone).day().month(.abbreviated))
        }
    }

    /// How long ago, for the panel: "just now", "2 min ago", "3 hr ago", "yesterday",
    /// "3 days ago".
    public static func relativeTime(of date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 60 * 60 { return "\(Int(seconds / 60)) min ago" }
        switch days(from: date, to: now, in: calendar(timeZone)) {
        case ...0: return "\(Int(seconds / (60 * 60))) hr ago"
        case 1: return "yesterday"
        case let days: return "\(days) days ago"
        }
    }

    /// What Undo does, for its accessibility label: "Put DELL U2723QE back to 1920 × 1080",
    /// "Turn mirroring off".
    public static func undoDescription(of change: HistoryEntry.Change) -> String {
        switch change {
        case .mode(let change):
            guard let from = sides(of: change).from else { return "Put \(change.display.name) back" }
            return "Put \(change.display.name) back to \(from)"
        case .mirroring(let change):
            return change.isOn ? "Turn mirroring off" : "Turn mirroring back on"
        }
    }

    /// `text` as VoiceOver should read it: sizes with "by" ("×" is read as "multiplied
    /// by"), arrows as "to", and the separators as pauses.
    public static func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: " × ", with: " by ")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " → ", with: " to ")
            .replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: "  ", with: ", ")
    }

    /// What a mode change's title shows of each side: the sizes; the refresh rates when only
    /// the rate changed; the sizes with their scale when only the scale changed.
    static func sides(of change: HistoryEntry.ModeChange) -> (from: String?, to: String) {
        let to = change.to
        guard let from = change.from else { return (nil, to.sizeText) }
        if from.width != to.width || from.height != to.height { return (from.sizeText, to.sizeText) }
        if from.refreshKey != to.refreshKey, from.refreshKey > 0, to.refreshKey > 0 {
            return (RefreshRate.format(from.refreshRate), RefreshRate.format(to.refreshRate))
        }
        if from.isHiDPI != to.isHiDPI { return (scaled(from), scaled(to)) }
        return (from.sizeText, to.sizeText)
    }

    private static func scaled(_ mode: HistoryEntry.ModeRecord) -> String {
        mode.sizeText + (mode.isHiDPI ? " HiDPI" : " 1×")
    }

    /// "Mirroring on: Built-in + DELL U2723QE". The built-in display is "Built-in" here.
    private static func mirroringTitle(_ change: HistoryEntry.MirroringChange) -> String {
        let state = change.isOn ? "Mirroring on" : "Mirroring off"
        guard !change.displays.isEmpty else { return state }
        return state + ": " + change.displays.map { $0.isBuiltin ? "Built-in" : $0.name }.joined(separator: " + ")
    }

    /// Where the change came from and the preset that made it.
    private static func basicDetail(of entry: HistoryEntry) -> [String] {
        var parts = [sourceText(entry.source)]
        if let preset = entry.source.presetName { parts.append("“\(preset)” preset") }
        return parts
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Calendar days from `date` to `now`: 0 the same day, 1 the day before.
    private static func days(from date: Date, to now: Date, in calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }
}

extension HistoryEntry.Source {
    /// Who or what asked, as History names it: "the panel", "Terminal", "Claude Code
    /// (Terminal)", or "the resolute command" when the terminal app is unknown.
    public var name: String {
        switch self {
        case .panel: "the panel"
        case .menu: "the menu"
        case .window: "the window"
        case .dock: "the Dock"
        case .keyboard: "a keyboard shortcut"
        case .shortcuts: "Shortcuts"
        case .terminal(let app): app ?? "the resolute command"
        case .agent(let name, let app): app.map { "\(name) (\($0))" } ?? name
        case .preset(_, let via): via.name
        }
    }

    /// The SF Symbol for where the change came from, as the History rows show it. The names
    /// are `Symbol` cases in ResoluteDesign.
    public var symbolName: String {
        switch self {
        case .panel, .menu: "menubar.rectangle"
        case .window: "macwindow"
        case .dock: "dock.rectangle"
        case .keyboard: "keyboard"
        case .terminal, .agent: "terminal"
        case .shortcuts: "switch.2"
        case .preset(_, let via): via.symbolName
        }
    }
}

extension HistoryEntry.RevertReason {
    /// What a row's detail says about it; nil when there is nothing to say.
    public var phrase: String? {
        switch self {
        case .noAnswer: "nobody answered"
        case .declined: "you chose Revert"
        case .displayWentDark: "the display went dark"
        case .displayChanged: "the display changed during the trial"
        case .unspecified: nil
        }
    }
}
