import Foundation

/// What applying a preset would do to the displays connected now: the display each setting
/// is for, and the mode macOS lists that it would switch to. Hidden modes never take part,
/// so a preset needs no Keep/Revert trial.
public struct PresetPlan: Hashable, Sendable {
    /// Why a setting can't apply now.
    public enum Problem: Hashable, Sendable {
        /// None of the connected displays is the one the setting names.
        case notConnected
        /// The display lists no mode at the setting's resolution.
        case resolutionNotOffered
        /// The setting keeps the current resolution, but the display's mode is unknown.
        case currentModeUnknown
        /// The setting keeps the current resolution, but only a hidden mode has it.
        case currentResolutionHidden

        /// Why, about the display, to follow its name: "it is not connected", "it does not
        /// list 2560 × 1440 HiDPI".
        public func reason(for setting: DisplaySetting) -> String {
            switch self {
            case .notConnected:
                return "it is not connected"
            case .resolutionNotOffered:
                let size = setting.size.map(\.text) ?? "that resolution"
                let scale = setting.isHiDPI.map { $0 ? " HiDPI" : " at 1×" } ?? ""
                return "it does not list \(size)\(scale)"
            case .currentModeUnknown:
                return "its current mode is unknown, so there is no resolution to keep"
            case .currentResolutionHidden:
                return "it uses a hidden resolution, which presets don’t switch to"
            }
        }
    }

    public enum Status: Hashable, Sendable {
        /// Applying switches the display to `mode`.
        case switches
        /// The display already uses `mode`.
        case inUse
        case skipped(Problem)
    }

    /// One setting of the preset.
    public struct Step: Hashable, Sendable {
        public var setting: DisplaySetting
        /// The connected display the setting is for.
        public var display: Display?
        /// The listed mode it switches to, or the one in use; nil when it is skipped.
        public var mode: DisplayMode?
        public var status: Status

        /// The display's name for messages: the connected one's, else the saved one.
        public var displayName: String {
            display?.name ?? setting.display.displayName
        }
    }

    /// What applying does about mirroring.
    public enum Mirroring: Hashable, Sendable {
        /// The preset leaves mirroring as it is.
        case leftAlone
        /// Mirroring is already on (true) or off (false).
        case inUse(Bool)
        /// Applying turns mirroring on (true) or off (false).
        case turns(Bool)
        /// The preset turns mirroring on, but there are fewer than two displays.
        case notPossible
    }

    public var steps: [Step]
    public var mirroring: Mirroring

    public init(_ preset: Preset, displays: [Display]) {
        let matches = Self.match(preset.displays, to: displays)
        steps = zip(preset.displays, matches).map { setting, display in
            guard let display else { return Step(setting: setting, display: nil, mode: nil, status: .skipped(.notConnected)) }
            switch Self.mode(for: setting, on: display) {
            case .success(let mode):
                let current = display.currentMode
                let inUse = current.map { $0.origin == .system && Self.isEquivalent($0, mode) } ?? false
                return Step(setting: setting, display: display, mode: inUse ? current : mode, status: inUse ? .inUse : .switches)
            case .failure(let problem):
                return Step(setting: setting, display: display, mode: nil, status: .skipped(problem.problem))
            }
        }
        let mirrored = displays.contains(where: \.isInMirrorSet)
        switch preset.mirroring {
        case nil: mirroring = .leftAlone
        case let wanted? where wanted == mirrored: mirroring = .inUse(wanted)
        case true? where displays.count < 2: mirroring = .notPossible
        case let wanted?: mirroring = .turns(wanted)
        }
    }

    /// Whether the current setup matches the preset: every display it names is connected
    /// and in its mode, and mirroring is as it says, so applying it would change nothing.
    public var isActive: Bool {
        guard !steps.isEmpty || mirroring != .leftAlone else { return false }
        switch mirroring {
        case .turns, .notPossible: return false
        case .leftAlone, .inUse: return steps.allSatisfy { $0.status == .inUse }
        }
    }

    // MARK: - Which display

    /// The connected display each setting is for, in the settings' order; each display
    /// serves one setting at most. Every setting is tried with the strongest evidence before
    /// any with weaker evidence, so a weak match never takes a display a strong one names.
    static func match(_ settings: [DisplaySetting], to displays: [Display]) -> [Display?] {
        let passes: [(DisplayReference, Display) -> Bool] = [
            // The same unit: model and serial number.
            { $0.isSameModel(as: $1) && $0.serialNumber != 0 && $0.serialNumber == $1.serialNumber },
            // The same model with the same name, which tells identical displays without
            // serial numbers apart as `resolute displays` numbers them.
            { $0.isSameModel(as: $1) && $0.name.caseInsensitiveCompare($1.name) == .orderedSame },
            // The same model: another unit of it, or one that reports no serial number.
            { $0.isSameModel(as: $1) },
            // The built-in display, also another Mac's.
            { $0.isBuiltin && $1.isBuiltin },
            // A display known by name only, or one whose IDs changed.
            { !$0.name.isEmpty && $0.name.caseInsensitiveCompare($1.name) == .orderedSame },
        ]
        var matches = [Display?](repeating: nil, count: settings.count)
        var taken = Set<Int>()
        for pass in passes {
            for (index, setting) in settings.enumerated() where matches[index] == nil {
                guard let found = displays.indices.first(where: { !taken.contains($0) && pass(setting.display, displays[$0]) }) else {
                    continue
                }
                matches[index] = displays[found]
                taken.insert(found)
            }
        }
        return matches
    }

    // MARK: - Which mode

    private struct Unavailable: Error {
        var problem: Problem
    }

    /// The listed mode `setting` asks for on `display`: the exact size, pixel size and rate,
    /// else the same size with the closest rate. Hidden modes never count.
    private static func mode(for setting: DisplaySetting, on display: Display) -> Result<DisplayMode, Unavailable> {
        let listed = display.modes.filter { $0.origin == .system }
        let current = display.currentMode
        var candidates: [DisplayMode]
        if let size = setting.size {
            candidates = listed.filter { $0.width == size.width && $0.height == size.height }
            if let pixels = setting.pixelSize {
                candidates = candidates.filter { $0.pixelWidth == pixels.width && $0.pixelHeight == pixels.height }
            } else if !candidates.isEmpty {
                // Either scale: the one in use, else HiDPI.
                candidates = ModeQuery.preferredGroup(ModeCatalog.groups(candidates), current: current).modes
            }
            guard !candidates.isEmpty else { return .failure(Unavailable(problem: .resolutionNotOffered)) }
        } else {
            guard let current else { return .failure(Unavailable(problem: .currentModeUnknown)) }
            let key = ResolutionGroup.Key(current)
            candidates = listed.filter { ResolutionGroup.Key($0) == key }
            guard !candidates.isEmpty else { return .failure(Unavailable(problem: .currentResolutionHidden)) }
        }
        return .success(closest(to: setting.refreshRate, among: candidates, current: current))
    }

    /// The mode among `modes`, which share one resolution, at `rate` or the closest rate to
    /// it, the faster of two equally close. Without a rate, the current one when offered,
    /// else the fastest.
    private static func closest(to rate: Double?, among modes: [DisplayMode], current: DisplayMode?) -> DisplayMode {
        var chosen = modes
        if let rate {
            let target = RefreshRate.key(rate)
            let distance = { (mode: DisplayMode) in abs(mode.refreshKey - target) }
            let nearest = modes.map(distance).min() ?? 0
            chosen = modes.filter { distance($0) == nearest }
            let fastest = chosen.map(\.refreshKey).max() ?? 0
            chosen = chosen.filter { $0.refreshKey == fastest }
        }
        // Among modes alike but for bit depth, the one in use, else one at its depth.
        return ModeCatalog.preferredMode(in: ModeCatalog.groups(chosen)[0], current: current)
    }

    /// Whether two modes look the same: one resolution at one rate. Modes that differ only
    /// in bit depth count as one, so a display is not switched between them.
    static func isEquivalent(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        ResolutionGroup.Key(lhs) == ResolutionGroup.Key(rhs) && lhs.refreshKey == rhs.refreshKey
    }
}

extension Preset {
    /// What applying the preset would do to `displays`.
    public func plan(for displays: [Display]) -> PresetPlan {
        PresetPlan(self, displays: displays)
    }

    /// Whether the current setup matches the preset, for its Active badge: applying it
    /// would change nothing, and every display it names is connected.
    public func isActive(on displays: [Display]) -> Bool {
        plan(for: displays).isActive
    }
}
