import Foundation
import Observation
import ResoluteKit

/// A notification about one change an agent made, worded as its History row is.
struct AgentChangeNotification: Hashable, Sendable {
    /// The History entry it is about. It is also the notification's identifier, so one
    /// entry is never shown twice.
    var entryID: UUID
    /// The change: "DELL U2723QE  2560 × 1440 → 2880 × 1620".
    var title: String
    /// Who asked, and how it ended: "From Claude Code (Terminal) · “Presenting” preset".
    var body: String
    /// Notification Center stacks one agent's changes together, so a preset's several
    /// switches arrive as one stack rather than as separate alerts.
    var group: String
    /// Whether it offers Undo: the change is in place and History knows what it replaced.
    var offersUndo: Bool

    init(entryID: UUID, title: String, body: String, group: String, offersUndo: Bool) {
        self.entryID = entryID
        self.title = title
        self.body = body
        self.group = group
        self.offersUndo = offersUndo
    }

    init(entry: HistoryEntry, in timeline: HistoryTimeline) {
        self.init(
            entryID: entry.id,
            title: HistoryText.title(of: entry.change),
            body: HistoryText.detail(of: entry),
            group: "agent." + entry.source.origin.name,
            offersUndo: timeline.canUndoWithoutLaterChanges(entry)
        )
    }
}

/// Where notifications go: Notification Center in the app, a fake in tests, which must
/// never reach `UNUserNotificationCenter`.
@MainActor
protocol AgentNotificationPosting: AnyObject {
    /// Called with the entry's ID when the person clicks Undo in a notification.
    var onUndo: (@MainActor (UUID) -> Void)? { get set }
    /// Asks macOS whether Resolute may notify. macOS asks the person only the first time.
    func requestPermission()
    func post(_ notification: AgentChangeNotification)
    /// Takes notifications back from Notification Center, as when their change is undone
    /// elsewhere, so no stale Undo is left there.
    func withdraw(_ entryIDs: [UUID])
}

/// Settings › Command Line & Agents › "Notify me when an agent changes a display: A
/// notification with Undo, even when the panel is closed."
///
/// While the preference is on it watches History's file, where `resolute` records every
/// switch, and posts one notification for each change an agent made that took effect, with
/// an Undo that goes through the app model like the panel's. What History held when the
/// preference was turned on, or when the app started with it on, never notifies. A burst
/// of writes, such as a preset's switches, is read once a moment after it settles.
@MainActor
final class AgentChangeNotifier {
    let poster: any AgentNotificationPosting
    private let model: AppModel
    /// How long after the file last changed it is read, so a burst is read once.
    private let settleDelay: TimeInterval
    /// How often to look for the support folder again while it does not exist yet: the
    /// first `resolute` switch creates it.
    private let retryInterval: TimeInterval
    private var observation: ObservationLoop?
    private var watcher: HistoryFileWatcher?
    /// The preference as last seen; nil before the first look.
    private var isOn: Bool?
    /// The entries History held at the last read. Nil until it was read since notifying
    /// started: everything that read finds counts as old.
    private var seen: Set<UUID>?
    /// Changes whose notification still offers Undo.
    private var undoable: Set<UUID> = []
    private var pendingRead: Timer?
    private var retry: Timer?

    init(
        model: AppModel, poster: any AgentNotificationPosting,
        settleDelay: TimeInterval = 0.3, retryInterval: TimeInterval = 5
    ) {
        self.model = model
        self.poster = poster
        self.settleDelay = settleDelay
        self.retryInterval = retryInterval
        poster.onUndo = { [weak self] id in self?.undo(entryID: id) }
    }

    /// Follows the preference from now on. Changes already in History never notify.
    func start() {
        guard observation == nil else { return }
        observation = ObservationLoop { [weak self] in self?.follow() }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        isOn = nil
        stopWatching()
    }

    /// Whether History's file is being watched for an agent's changes.
    var isWatching: Bool { watcher != nil }

    /// Reads History and notifies of the agent's changes added since the last read.
    func readHistory() {
        guard isOn == true else { return }
        let entries: [HistoryEntry]
        do {
            entries = try model.historyStore.entries()
        } catch {
            ResoluteLog.history.error("Could not read history for notifications: \(error.localizedDescription, privacy: .public)")
            return
        }
        let timeline = HistoryTimeline(entries: entries)
        let previous = seen
        seen = Set(entries.map(\.id))
        withdrawStale(in: timeline)
        guard let previous else { return }
        // Oldest first, so the newest change of a burst ends up on top of its stack.
        for entry in timeline.entries.reversed() where !previous.contains(entry.id) && Self.notifies(of: entry) {
            let notification = AgentChangeNotification(entry: entry, in: timeline)
            poster.post(notification)
            if notification.offersUndo { undoable.insert(entry.id) }
        }
    }

    /// Undo clicked in a notification: puts back what the change replaced, as the panel's
    /// Undo does, and opens nothing. While a countdown is up it waits for it to end, since
    /// the switch would be turned away.
    func undo(entryID: UUID) {
        undoable.remove(entryID)
        model.modeChanges.afterSwitch { [weak self] in self?.undoNow(entryID: entryID) }
    }

    private func undoNow(entryID: UUID) {
        // The agent switched outside the app, so read the displays too, not only History.
        model.refresh()
        guard let entry = model.historyEntries.first(where: { $0.id == entryID }) else {
            model.showError(UndoUnavailable(reason: "This change is no longer in History."), "The change can’t be undone")
            return
        }
        // Undo would throw away whatever was chosen for the display since.
        guard model.historyTimeline.canUndoWithoutLaterChanges(entry) else {
            model.showError(
                UndoUnavailable(reason: "The display was changed again since, so Undo would undo that change too."),
                "The change can’t be undone"
            )
            return
        }
        model.undo(entry, from: .panel)
    }

    /// An agent's change that is in place: switches that were reverted or failed changed
    /// nothing to undo.
    static func notifies(of entry: HistoryEntry) -> Bool {
        guard case .agent = entry.source.origin else { return false }
        return entry.outcome.tookEffect
    }

    // MARK: - Following the preference

    /// Runs under observation: reads only the preference, so nothing else re-runs it.
    private func follow() {
        let isOn = model.preferences.notifiesAgentChanges
        let wasOn = self.isOn
        self.isOn = isOn
        guard isOn != wasOn else { return }
        if isOn {
            // Asked when the person turns it on; at launch it was asked when they did.
            if wasOn == false { poster.requestPermission() }
            startWatching()
        } else {
            stopWatching()
        }
    }

    private func startWatching() {
        seen = nil
        readHistory()
        let watcher = HistoryFileWatcher(file: model.support.historyFile) { [weak self] in
            self?.scheduleRead()
        }
        watcher.start()
        self.watcher = watcher
        if !watcher.isWatching { retryWatching() }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        pendingRead?.invalidate()
        pendingRead = nil
        retry?.invalidate()
        retry = nil
        seen = nil
    }

    /// Tries again until the support folder exists, then reads what was added meanwhile.
    private func retryWatching() {
        let timer = Timer(timeInterval: retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let watcher = self.watcher else { return }
                watcher.start()
                guard watcher.isWatching else { return }
                self.retry?.invalidate()
                self.retry = nil
                self.scheduleRead()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retry = timer
    }

    /// Reads once the burst of writes settles. On the main run loop in every mode, so a
    /// change made while a Keep/Revert question is up is still notified.
    private func scheduleRead() {
        pendingRead?.invalidate()
        let timer = Timer(timeInterval: settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pendingRead = nil
                self?.readHistory()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingRead = timer
    }

    /// Takes back the Undo of changes that are no longer in place, were changed again since,
    /// or are no longer in History.
    private func withdrawStale(in timeline: HistoryTimeline) {
        guard !undoable.isEmpty else { return }
        let byID = Dictionary(timeline.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = undoable.filter { id in byID[id].map { !timeline.canUndoWithoutLaterChanges($0) } ?? true }
        guard !stale.isEmpty else { return }
        undoable.subtract(stale)
        poster.withdraw(stale.sorted { $0.uuidString < $1.uuidString })
    }
}
