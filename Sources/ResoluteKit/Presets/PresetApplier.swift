import CoreGraphics
import Foundation

/// Applies presets. Mirroring changes first, since turning it on or off can change the
/// modes a display offers; then each display the preset names switches to its listed mode,
/// saved like a change in System Settings. A display that can't be switched does not stop
/// the others: the result says what happened to each.
public struct PresetApplier: Sendable {
    private let service: any DisplayControlling

    public init(service: any DisplayControlling) {
        self.service = service
    }

    public func apply(_ preset: Preset) -> PresetResult {
        var displays = service.displays()
        let mirroring = applyMirroring(preset.mirroring, on: displays)
        if case .turned = mirroring { displays = service.displays() }
        let plan = PresetPlan(preset, displays: displays)
        let switcher = ModeSwitcher(service: service)
        var results = plan.steps.map { step -> PresetResult.DisplayResult in
            var result = PresetResult.DisplayResult(
                setting: step.setting, display: step.display, previousMode: step.display?.currentMode, mode: step.mode,
                outcome: .alreadyInUse
            )
            switch step.status {
            case .inUse:
                break
            case .skipped(let problem):
                result.outcome = .skipped(problem)
            case .switches:
                guard let display = step.display, let mode = step.mode else { break }
                do {
                    // Listed modes only, so no trial: there is nothing to keep or revert.
                    let outcome = try switcher.apply(modeID: mode.modeID, to: display.id, trial: false) { .keep }
                    result.outcome = outcome == .alreadyCurrent ? .alreadyInUse : .switched
                } catch {
                    result.outcome = .failed(error.localizedDescription)
                }
            }
            return result
        }
        // One fresh look confirms every switch: a display can drop off, or macOS can settle
        // on another mode than the one asked for.
        if results.contains(where: { $0.outcome == .switched }) {
            let after = service.displays()
            for index in results.indices where results[index].outcome == .switched {
                guard let id = results[index].display?.id, let mode = results[index].mode else { continue }
                guard let display = after.first(where: { $0.id == id }) else {
                    results[index].outcome = .wentAway
                    continue
                }
                // The snapshot also knows a hidden mode in use, which CoreGraphics may not name.
                let shownID = display.currentModeID ?? service.currentModeID(of: id)
                let shown = display.modes.first { $0.modeID == shownID }
                guard shownID != mode.modeID, !(shown.map { PresetPlan.isEquivalent($0, mode) } ?? false) else { continue }
                results[index].outcome = .showsOtherMode(shown)
            }
        }
        return PresetResult(preset: preset, displays: results, mirroring: mirroring)
    }

    private func applyMirroring(_ wanted: Bool?, on displays: [Display]) -> PresetResult.Mirroring {
        guard let wanted else { return .leftAlone }
        guard displays.contains(where: \.isInMirrorSet) != wanted else { return .alreadyInUse(wanted) }
        guard !wanted || displays.count > 1 else { return .notPossible }
        do {
            try service.setMirroring(wanted)
            return .turned(wanted)
        } catch {
            return .failed(wanted, error.localizedDescription)
        }
    }
}

/// What applying a preset did.
public struct PresetResult: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case switched
        case alreadyInUse
        /// The setting could not apply; `Problem.reason(for:)` says why in words.
        case skipped(PresetPlan.Problem)
        /// The switch failed; the text is the error's description.
        case failed(String)
        /// macOS accepted the switch, but the display went away before it could be checked.
        case wentAway
        /// macOS accepted the switch, but the display shows another mode now: this one, or
        /// one it does not list.
        case showsOtherMode(DisplayMode?)

        /// Whether a switch was made, confirmed or not.
        public var isSwitch: Bool {
            switch self {
            case .switched, .wentAway, .showsOtherMode: true
            case .alreadyInUse, .skipped, .failed: false
            }
        }
    }

    public enum Mirroring: Hashable, Sendable {
        /// The preset leaves mirroring as it is.
        case leftAlone
        case alreadyInUse(Bool)
        case turned(Bool)
        /// The preset turns mirroring on, but there are fewer than two displays.
        case notPossible
        /// Turning mirroring on (true) or off (false) failed; the text says why.
        case failed(Bool, String)
    }

    /// What happened to one setting of the preset.
    public struct DisplayResult: Hashable, Sendable {
        public var setting: DisplaySetting
        /// The connected display the setting was for, as it was before the switch.
        public var display: Display?
        public var previousMode: DisplayMode?
        /// The listed mode it switched to, or the one already in use.
        public var mode: DisplayMode?
        public var outcome: Outcome

        /// The display's name for messages: the connected one's, else the saved one.
        public var displayName: String {
            display?.name ?? setting.display.displayName
        }
    }

    public var preset: Preset
    public var displays: [DisplayResult]
    public var mirroring: Mirroring

    /// Whether a switch, or mirroring, failed.
    public var hasFailures: Bool {
        if case .failed = mirroring { return true }
        return displays.contains { if case .failed = $0.outcome { true } else { false } }
    }

    /// Whether something changed.
    public var changedAnything: Bool {
        if case .turned = mirroring { return true }
        return displays.contains(where: \.outcome.isSwitch)
    }

    /// Whether the preset could do nothing with the displays connected now: none of its
    /// displays could be set, being not connected or not listing the mode, and mirroring
    /// did not change. Mirroring that is already right counts only in a preset that sets
    /// mirroring alone; in one that names displays, the displays are the point.
    public var appliedNothing: Bool {
        guard displays.allSatisfy({ if case .skipped = $0.outcome { true } else { false } }) else { return false }
        switch mirroring {
        case .turned, .failed: return false
        case .alreadyInUse: return !displays.isEmpty
        case .leftAlone, .notPossible: return true
        }
    }
}
