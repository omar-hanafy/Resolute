import Foundation

/// History as the list and the panel show it: the entries newest first, with each change's
/// status worked out from the Undo entries that point at it. The file only grows, so an
/// undone change stays as it was written and its Undo is a later entry.
public struct HistoryTimeline: Sendable {
    /// Every entry, newest first.
    public let entries: [HistoryEntry]
    /// The Undo of each change that was undone.
    private let undos: [UUID: HistoryEntry]
    private let ids: Set<UUID>

    /// `entries` in any order; entries of the same date keep the order given.
    public init(entries: [HistoryEntry]) {
        let ordered = entries.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        self.entries = ordered
        ids = Set(ordered.map(\.id))
        var undos: [UUID: HistoryEntry] = [:]
        // Newest first, so the first Undo of a change is the one that stays.
        for entry in ordered {
            if let original = entry.outcome.undoneEntryID { undos[original] = entry }
        }
        self.undos = undos
    }

    /// The Undo that put back what `entry` replaced, if there was one.
    public func undo(of entry: HistoryEntry) -> HistoryEntry? {
        undos[entry.id]
    }

    /// What the row's badge says.
    public func status(of entry: HistoryEntry) -> HistoryStatus {
        if undos[entry.id] != nil { return .undone }
        switch entry.outcome {
        case .applied, .kept, .keptForSession, .undone: return .kept
        case .reverted: return .reverted
        case .failed: return .failed
        }
    }

    /// Whether the row offers Undo: the change is in place, and History knows what it replaced.
    public func canUndo(_ entry: HistoryEntry) -> Bool {
        guard status(of: entry) == .kept, !isShownAsStatus(entry) else { return false }
        if case .mode(let change) = entry.change { return change.from != nil }
        return true
    }

    /// Whether `entry` can be undone and nothing changed the same display (or mirroring)
    /// after it, so its Undo puts back exactly what it replaced, as the panel's activity row
    /// and a notification's Undo require.
    public func canUndoWithoutLaterChanges(_ entry: HistoryEntry) -> Bool {
        guard canUndo(entry) else { return false }
        let target = Target(entry.change)
        for later in entries {
            if later.id == entry.id { return true }
            if later.outcome.tookEffect, Target(later.change) == target { return false }
        }
        return false
    }

    /// The changes the list shows, newest first. An Undo shows as the Undone status of the
    /// change it undid rather than as a row of its own, unless that change is gone.
    public func changes(in filter: HistoryFilter = .all) -> [HistoryEntry] {
        entries.filter { !isShownAsStatus($0) && filter.includes($0) }
    }

    /// The list's rows, newest first.
    public func items(
        in filter: HistoryFilter = .all, now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current
    ) -> [HistoryItem] {
        changes(in: filter).map { HistoryItem(entry: $0, in: self, now: now, timeZone: timeZone, locale: locale) }
    }

    /// The newest change from Terminal, an agent or Shortcuts that is still in place: it took
    /// effect, was not undone, and nothing changed the same display (or mirroring) after it,
    /// so its Undo puts back exactly what it replaced.
    public var lastOutsideChange: HistoryEntry? {
        var changedLater = Set<Target>()
        for entry in entries {
            let target = Target(entry.change)
            if entry.source.category != .panel, entry.outcome.tookEffect, entry.outcome.undoneEntryID == nil,
               undos[entry.id] == nil, !changedLater.contains(target) {
                return entry
            }
            if entry.outcome.tookEffect { changedLater.insert(target) }
        }
        return nil
    }

    /// The panel's row for `lastOutsideChange`.
    public func lastOutsideActivity(now: Date = Date(), timeZone: TimeZone = .current) -> HistoryActivity? {
        lastOutsideChange.map { HistoryActivity(entry: $0, now: now, timeZone: timeZone) }
    }

    /// Whether `entry` is an Undo whose change is listed, which shows it as Undone.
    private func isShownAsStatus(_ entry: HistoryEntry) -> Bool {
        entry.outcome.undoneEntryID.map(ids.contains) ?? false
    }

    /// What a change applies to: one display, known by its hardware, or mirroring.
    private enum Target: Hashable {
        case display(vendorID: UInt32, productID: UInt32, serialNumber: UInt32, isBuiltin: Bool)
        case mirroring

        init(_ change: HistoryEntry.Change) {
            switch change {
            case .mode(let change):
                let display = change.display
                self = .display(
                    vendorID: display.vendorID, productID: display.productID, serialNumber: display.serialNumber,
                    isBuiltin: display.isBuiltin
                )
            case .mirroring:
                self = .mirroring
            }
        }
    }
}

/// A row of the History list (History Row 36:445), in Figma's words.
public struct HistoryItem: Identifiable, Hashable, Sendable {
    public var entry: HistoryEntry
    /// "9:41", "Yesterday"
    public var time: String
    /// The SF Symbol for where the change came from.
    public var symbolName: String
    /// "DELL U2723QE  2560 × 1440 → 2880 × 1620"
    public var title: String
    /// "From Claude Code (Terminal) · hidden mode · nobody answered"
    public var detail: String
    public var status: HistoryStatus
    public var canUndo: Bool
    /// The whole row for VoiceOver, with sizes read with "by".
    public var accessibilityLabel: String
    /// The Undo button's: "Undo, put DELL U2723QE back to 1920 by 1080".
    public var undoAccessibilityLabel: String

    public var id: UUID { entry.id }

    public init(
        entry: HistoryEntry, in timeline: HistoryTimeline, now: Date = Date(), timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        self.entry = entry
        time = HistoryText.time(of: entry.date, now: now, timeZone: timeZone, locale: locale)
        symbolName = entry.source.symbolName
        title = HistoryText.title(of: entry.change)
        detail = HistoryText.detail(of: entry)
        status = timeline.status(of: entry)
        canUndo = timeline.canUndo(entry)
        accessibilityLabel = [time, HistoryText.spoken(title), HistoryText.spoken(detail), status.title].joined(separator: ", ")
        undoAccessibilityLabel = "Undo, " + HistoryText.spoken(HistoryText.undoDescription(of: entry.change)).lowercasedFirst
    }
}

/// The panel's row for the last change made outside it (Activity Row 17:63).
public struct HistoryActivity: Identifiable, Hashable, Sendable {
    public var entry: HistoryEntry
    /// The SF Symbol for where the change came from.
    public var symbolName: String
    /// "DELL U2723QE → 2560 × 1440"
    public var title: String
    /// "From Terminal · 2 min ago"
    public var detail: String
    /// The row for VoiceOver, with sizes read with "by".
    public var accessibilityLabel: String
    /// The Undo button's: "Undo, put DELL U2723QE back to 1920 by 1080".
    public var undoAccessibilityLabel: String

    public var id: UUID { entry.id }

    public init(entry: HistoryEntry, now: Date = Date(), timeZone: TimeZone = .current) {
        self.entry = entry
        symbolName = entry.source.symbolName
        title = HistoryText.activityTitle(of: entry.change)
        detail = HistoryText.activityDetail(of: entry, now: now, timeZone: timeZone)
        accessibilityLabel = HistoryText.spoken(title) + ", " + HistoryText.spoken(detail)
        undoAccessibilityLabel = "Undo, " + HistoryText.spoken(HistoryText.undoDescription(of: entry.change)).lowercasedFirst
    }
}

extension String {
    /// The text with its first letter in lower case, to follow "Undo, ".
    fileprivate var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
