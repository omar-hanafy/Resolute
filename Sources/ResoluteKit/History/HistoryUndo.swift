import Foundation

/// What Undo does for a change in History: it puts back what the change replaced.
public enum HistoryUndo {
    /// What to do, worked out from the displays as they are now.
    public enum Plan: Hashable, Sendable {
        /// Switch `display` to `mode`. A hidden mode is tried first, as any hidden mode is.
        case switchMode(display: Display, mode: DisplayMode)
        /// Turn mirroring on or off.
        case setMirroring(Bool)
        /// The display already shows what the change replaced; only History changes.
        case alreadyCurrent(String)
        /// What the change replaced can't be put back, and why.
        case unavailable(String)

        /// Whether the mode to put back is a hidden one, which needs a Keep/Revert trial.
        public var needsTrial: Bool {
            if case .switchMode(_, let mode) = self { return mode.origin == .hidden }
            return false
        }
    }

    /// The plan for undoing `entry`, given the online `displays`. A listed mode comes back
    /// when the display lists a mode of the same size, pixels and refresh rate, also under
    /// another mode ID; a hidden mode only in the login it was used in, and only while the
    /// display still offers it.
    public static func plan(
        for entry: HistoryEntry, in timeline: HistoryTimeline, displays: [Display],
        loginSession: String? = LoginSession.current
    ) -> Plan {
        switch timeline.status(of: entry) {
        case .undone: return .unavailable("This change was already undone.")
        case .reverted: return .unavailable("This change was reverted, so there is nothing to undo.")
        case .failed: return .unavailable("This change did not happen, so there is nothing to undo.")
        case .kept: break
        }
        switch entry.change {
        case .mirroring(let change):
            let isOn = displays.contains(where: \.isInMirrorSet)
            if isOn != change.isOn { return .alreadyCurrent(isOn ? "Mirroring is already on." : "Mirroring is already off.") }
            if !change.isOn, displays.count < 2 { return .unavailable(ResoluteError.mirroringNeedsTwoDisplays.localizedDescription) }
            return .setMirroring(!change.isOn)
        case .mode(let change):
            return plan(for: change, recordedIn: entry.loginSession, displays: displays, loginSession: loginSession)
        }
    }

    private static func plan(
        for change: HistoryEntry.ModeChange, recordedIn entrySession: String?, displays: [Display], loginSession: String?
    ) -> Plan {
        let name = change.display.name
        guard let from = change.from else {
            return .unavailable("Resolute did not learn which mode \(name) used before this change, so there is nothing to put back.")
        }
        // "1920 × 1080", or "120 Hz" when only the rate changed, as the row's title has it;
        // the whole mode, "1728 × 1117 at 120 Hz", where the rate alone would be unclear.
        let wanted = HistoryText.sides(of: change).from ?? from.sizeText
        let mode = wanted.hasPrefix(from.sizeText) ? wanted : "\(from.sizeText) at \(wanted)"
        let matches = displays.filter(change.display.isSameHardware)
        let sameID = matches.first { $0.id == change.display.id }
        guard let display = sameID ?? (matches.count == 1 ? matches[0] : nil) else {
            return .unavailable(matches.isEmpty
                ? "\(name) is not connected."
                : "More than one connected display looks like \(name), so Resolute can’t tell which one changed.")
        }
        if let current = display.currentMode, from.hasSameShape(as: current) {
            return .alreadyCurrent("\(display.name) is already at \(wanted).")
        }
        if from.isHidden {
            // Hidden modes belong to the login they were tried in.
            guard let loginSession, entrySession == loginSession else {
                return .unavailable("\(mode) was a hidden mode, and a hidden mode can’t come back after you log out.")
            }
        }
        // A listed mode comes back only as a listed one; a hidden one may be listed by now.
        let candidates = display.modes.filter { from.hasSameShape(as: $0) && (from.isHidden || $0.origin == .system) }
        guard !candidates.isEmpty else {
            return .unavailable(from.isHidden
                ? "\(mode) was a hidden mode that \(display.name) no longer offers."
                : "\(display.name) no longer offers \(mode).")
        }
        let best = candidates.min { rank($0, for: from).lexicographicallyPrecedes(rank($1, for: from)) } ?? candidates[0]
        return .switchMode(display: display, mode: best)
    }

    /// Lower is closer to the recorded mode: listed before hidden, then the same mode ID,
    /// bit depth and flags, in that order.
    private static func rank(_ mode: DisplayMode, for record: HistoryEntry.ModeRecord) -> [Int] {
        [
            mode.origin == .system ? 0 : 1,
            mode.modeID == record.modeID ? 0 : 1,
            record.bitsPerSample == nil || mode.bitsPerSample == record.bitsPerSample ? 0 : 1,
            mode.ioFlags == record.ioFlags ? 0 : 1,
        ]
    }
}
