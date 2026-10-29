import Foundation

/// Adds changes to History, each from one source. Recording never fails the change it
/// records: the switch has happened by then, so a history that can't be written is logged
/// and passed to `onFailure`, and the change goes on.
public struct HistoryRecorder: Sendable {
    public var store: HistoryStore
    /// Where the changes this recorder records come from.
    public var source: HistoryEntry.Source
    /// Told when a change could not be written to History.
    public var onFailure: @Sendable (any Error) -> Void
    var now: @Sendable () -> Date
    var loginSession: @Sendable () -> String?

    public init(
        store: HistoryStore = HistoryStore(), source: HistoryEntry.Source,
        onFailure: @escaping @Sendable (any Error) -> Void = { _ in }
    ) {
        self.init(store: store, source: source, onFailure: onFailure, now: { Date() }, loginSession: { LoginSession.current })
    }

    init(
        store: HistoryStore, source: HistoryEntry.Source, onFailure: @escaping @Sendable (any Error) -> Void,
        now: @escaping @Sendable () -> Date, loginSession: @escaping @Sendable () -> String?
    ) {
        self.store = store
        self.source = source
        self.onFailure = onFailure
        self.now = now
        self.loginSession = loginSession
    }

    /// The `resolute` command's recorder: changes come from whoever ran it, an agent or a
    /// person, in the app it ran in.
    public static func commandLine(
        support: SupportLocations = .standard, requester: Requester = .current(),
        onFailure: @escaping @Sendable (any Error) -> Void = { _ in }
    ) -> HistoryRecorder {
        HistoryRecorder(store: HistoryStore(locations: support), source: requester.source, onFailure: onFailure)
    }

    /// This recorder for changes from `source`.
    public func from(_ source: HistoryEntry.Source) -> HistoryRecorder {
        var recorder = self
        recorder.source = source
        return recorder
    }

    /// This recorder for the changes the preset `name` makes, one entry per change.
    public func applying(preset name: String) -> HistoryRecorder {
        from(.preset(name: name, via: source.origin))
    }

    /// Records `change`, which ended as `outcome`.
    @discardableResult
    public func record(_ change: HistoryEntry.Change, outcome: HistoryEntry.Outcome) -> HistoryEntry? {
        let entry = HistoryEntry(date: now(), source: source, change: change, outcome: outcome, loginSession: loginSession())
        do {
            try store.append(entry)
            return entry
        } catch {
            ResoluteLog.history.error("Could not add a change to history: \(error.localizedDescription, privacy: .public)")
            onFailure(error)
            return nil
        }
    }

    /// Records switching `display`, as it was before the switch, to `mode`, which ended as
    /// `ModeSwitcher` reported. Nothing is recorded when the display already showed the
    /// mode, nor while a revert still waits for its display: record how the wait ended.
    @discardableResult
    public func record(
        _ outcome: ModeSwitcher.Outcome, switching display: Display, to mode: DisplayMode,
        revertReason: HistoryEntry.RevertReason = .unspecified
    ) -> HistoryEntry? {
        let recorded: HistoryEntry.Outcome
        switch outcome {
        case .alreadyCurrent, .restorePending: return nil
        case .applied: recorded = .applied
        case .kept: recorded = .kept
        case .keptForSession: recorded = .keptForSession
        case .reverted: recorded = .reverted(revertReason)
        case .leftAlone: recorded = .reverted(.displayChanged)
        }
        return recordSwitch(of: display, to: mode, outcome: recorded)
    }

    /// Records switching `display`, as it was before the switch, to `mode`.
    @discardableResult
    public func recordSwitch(of display: Display, to mode: DisplayMode, outcome: HistoryEntry.Outcome) -> HistoryEntry? {
        record(.mode(HistoryEntry.ModeChange(display: display, to: mode)), outcome: outcome)
    }

    /// Records a switch of `display` to `mode` that ended with `error`. A request refused
    /// before anything changed (a usage error) is not a change, so it is not recorded.
    @discardableResult
    public func record(_ error: any Error, switching display: Display, to mode: DisplayMode) -> HistoryEntry? {
        switch error as? ResoluteError {
        case .usage?: return nil
        case .displayChangedDuringTrial?: return recordSwitch(of: display, to: mode, outcome: .reverted(.displayChanged))
        default: return recordSwitch(of: display, to: mode, outcome: .failed(message: error.localizedDescription))
        }
    }

    /// Records mirroring turned on or off. `displays` are the online displays before the
    /// change; turning it off records only the ones that were mirrored.
    @discardableResult
    public func recordMirroring(_ isOn: Bool, displays: [Display], outcome: HistoryEntry.Outcome = .applied) -> HistoryEntry? {
        let mirrored = displays.filter(\.isInMirrorSet)
        let involved = isOn || mirrored.isEmpty ? displays : mirrored
        let change = HistoryEntry.MirroringChange(isOn: isOn, displays: involved.map(HistoryEntry.DisplayRecord.init))
        return record(.mirroring(change), outcome: outcome)
    }

    /// Records mirroring turned on or off that failed with `error`. A request refused before
    /// anything changed, such as mirroring a single display, is not a change, so it is not
    /// recorded, as a preset that can't mirror records nothing.
    @discardableResult
    public func recordMirroring(_ isOn: Bool, displays: [Display], failedWith error: any Error) -> HistoryEntry? {
        switch error as? ResoluteError {
        case .usage?, .mirroringNeedsTwoDisplays?: return nil
        default: return recordMirroring(isOn, displays: displays, outcome: .failed(message: error.localizedDescription))
        }
    }

    /// Records what applying `preset` changed, an entry for each change so each can be undone
    /// on its own, named after the preset. `displays` are the displays before anything changed.
    @discardableResult
    public func record(_ result: PresetResult, applying preset: Preset, displays: [Display]) -> [HistoryEntry] {
        let history = applying(preset: preset.name)
        var recorded: [HistoryEntry?] = []
        switch result.mirroring {
        case .turned(let isOn):
            recorded.append(history.recordMirroring(isOn, displays: displays))
        case .failed(let isOn, let message):
            recorded.append(history.recordMirroring(isOn, displays: displays, outcome: .failed(message: message)))
        case .leftAlone, .alreadyInUse, .notPossible:
            break
        }
        for change in result.displays {
            guard let display = change.display, let mode = change.mode else { continue }
            switch change.outcome {
            case .switched, .wentAway, .showsOtherMode:
                recorded.append(history.recordSwitch(of: display, to: mode, outcome: .applied))
            case .failed(let message):
                recorded.append(history.recordSwitch(of: display, to: mode, outcome: .failed(message: message)))
            case .alreadyInUse, .skipped:
                break
            }
        }
        return recorded.compactMap { $0 }
    }

    /// Records Undo of `original` once `plan` was carried out. For a mode switch, pass how
    /// it ended, and why a trial was put back; an Undo that was tried and put back is
    /// recorded as that attempt, and the change stays in place. A plan that found nothing to
    /// switch still marks the change undone, since the display shows what it replaced.
    @discardableResult
    public func recordUndo(
        of original: HistoryEntry, plan: HistoryUndo.Plan, outcome: ModeSwitcher.Outcome = .applied,
        revertReason: HistoryEntry.RevertReason = .unspecified
    ) -> HistoryEntry? {
        let undone = HistoryEntry.Outcome.undone(of: original.id)
        switch plan {
        case .switchMode(let display, let mode):
            switch outcome {
            case .applied, .kept, .keptForSession, .alreadyCurrent:
                return recordSwitch(of: display, to: mode, outcome: undone)
            case .reverted, .leftAlone, .restorePending:
                return record(outcome, switching: display, to: mode, revertReason: revertReason)
            }
        case .setMirroring(let isOn):
            guard case .mirroring(let change) = original.change else { return nil }
            return record(.mirroring(HistoryEntry.MirroringChange(isOn: isOn, displays: change.displays)), outcome: undone)
        case .alreadyCurrent:
            return record(Self.reversed(original.change), outcome: undone)
        case .unavailable:
            return nil
        }
    }

    /// Records an Undo of `original` that failed with `error` while carrying out `plan`.
    @discardableResult
    public func recordFailedUndo(of original: HistoryEntry, plan: HistoryUndo.Plan, error: any Error) -> HistoryEntry? {
        switch plan {
        case .switchMode(let display, let mode):
            return record(error, switching: display, to: mode)
        case .setMirroring(let isOn):
            guard case .mirroring(let change) = original.change else { return nil }
            return record(
                .mirroring(HistoryEntry.MirroringChange(isOn: isOn, displays: change.displays)),
                outcome: .failed(message: error.localizedDescription)
            )
        case .alreadyCurrent, .unavailable:
            return nil
        }
    }

    /// The change that undoes `change`.
    private static func reversed(_ change: HistoryEntry.Change) -> HistoryEntry.Change {
        switch change {
        case .mode(let change):
            .mode(HistoryEntry.ModeChange(display: change.display, from: change.to, to: change.from ?? change.to))
        case .mirroring(let change):
            .mirroring(HistoryEntry.MirroringChange(isOn: !change.isOn, displays: change.displays))
        }
    }
}
