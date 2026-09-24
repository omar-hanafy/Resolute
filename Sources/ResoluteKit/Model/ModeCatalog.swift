import Foundation

/// All modes that share a size in points and in pixels: one entry in the resolution menu.
public struct ResolutionGroup: Hashable, Sendable, Identifiable {
    public struct Key: Hashable, Sendable {
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int

        public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) {
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        public init(_ mode: DisplayMode) {
            self.init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight)
        }

        /// Orders larger resolutions first.
        public static func largerFirst(_ lhs: Key, _ rhs: Key) -> Bool {
            (lhs.width, lhs.height, lhs.pixelWidth, lhs.pixelHeight)
                > (rhs.width, rhs.height, rhs.pixelWidth, rhs.pixelHeight)
        }
    }

    public var key: Key
    /// System modes first, then the fastest refresh rate first.
    public var modes: [DisplayMode]

    public var id: Key { key }
    public var isHiDPI: Bool { key.pixelWidth > key.width }
    public var isHidden: Bool { modes.allSatisfy { $0.origin == .hidden } }
    public var isDefault: Bool { modes.contains(where: \.isDefault) }
    public var isNative: Bool { modes.contains(where: \.isNative) }
    public var sizeText: String { "\(key.width) × \(key.height)" }
    public var pixelSizeText: String { "\(key.pixelWidth) × \(key.pixelHeight)" }

    /// Distinct refresh rates, highest first.
    public var refreshRates: [Double] {
        var seen = Set<Int>()
        return modes.map(\.refreshRate).sorted(by: >).filter { seen.insert(RefreshRate.key($0)).inserted }
    }
}

/// A titled run of resolutions in the menu.
public struct ResolutionSection: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case hiDPI
        case lowResolution
        case standard
        case hidden

        public var title: String {
            switch self {
            case .hiDPI: "HiDPI"
            case .lowResolution: "Low Resolution (1×)"
            case .standard: "Resolutions"
            case .hidden: "Hidden"
            }
        }
    }

    public var kind: Kind
    public var groups: [ResolutionGroup]
}

/// A refresh rate offered for the current resolution.
public struct RefreshOption: Hashable, Sendable {
    public var mode: DisplayMode
    public var isCurrent: Bool
    public var refreshRate: Double { mode.refreshRate }
}

/// Turns a display's flat mode list into what the menu and the CLI show.
public enum ModeCatalog {
    public static func groups(_ modes: [DisplayMode]) -> [ResolutionGroup] {
        Dictionary(grouping: modes, by: ResolutionGroup.Key.init)
            .map { key, modes in ResolutionGroup(key: key, modes: modes.sorted(by: systemThenFastest)) }
            .sorted { ResolutionGroup.Key.largerFirst($0.key, $1.key) }
    }

    public static func currentKey(for display: Display) -> ResolutionGroup.Key? {
        display.currentMode.map(ResolutionGroup.Key.init)
    }

    /// Resolution sections: HiDPI and low-resolution modes on displays that have HiDPI
    /// modes, one standard section otherwise, and hidden-only resolutions last.
    public static func sections(
        for display: Display,
        includeLowResolution: Bool,
        includeHidden: Bool
    ) -> [ResolutionSection] {
        let currentKey = currentKey(for: display)
        let modes = display.modes.filter {
            includeHidden || $0.origin == .system || $0.modeID == display.currentModeID
        }
        let all = groups(modes)
        let visible = all.filter { !$0.isHidden }
        let hiDPI = visible.filter(\.isHiDPI)
        let oneX = visible.filter { !$0.isHiDPI }

        var sections: [ResolutionSection] = []
        if hiDPI.isEmpty {
            if !oneX.isEmpty { sections.append(ResolutionSection(kind: .standard, groups: oneX)) }
        } else {
            sections.append(ResolutionSection(kind: .hiDPI, groups: hiDPI))
            // Keep the current resolution visible even when low-resolution modes are off.
            let lowResolution = includeLowResolution ? oneX : oneX.filter { $0.key == currentKey }
            if !lowResolution.isEmpty {
                sections.append(ResolutionSection(kind: .lowResolution, groups: lowResolution))
            }
        }
        let hidden = all.filter(\.isHidden)
        if !hidden.isEmpty { sections.append(ResolutionSection(kind: .hidden, groups: hidden)) }
        return sections
    }

    /// The mode to switch to when someone picks `group`: the current mode if it is in the
    /// group; else the current refresh rate if offered, otherwise the fastest — preferring
    /// system modes and the current bit depth.
    public static func preferredMode(in group: ResolutionGroup, current: DisplayMode?) -> DisplayMode {
        if let current, group.modes.contains(current) { return current }
        var candidates = group.modes
        if candidates.contains(where: { $0.origin == .system }) {
            candidates = candidates.filter { $0.origin == .system }
        }
        if let depth = current?.bitsPerSample, candidates.contains(where: { $0.bitsPerSample == depth }) {
            candidates = candidates.filter { $0.bitsPerSample == depth }
        }
        if let current, let sameRate = candidates.first(where: { $0.refreshKey == current.refreshKey }) {
            return sameRate
        }
        return candidates.first ?? group.modes[0]
    }

    /// Refresh rates for the display's current resolution, highest first.
    public static func refreshOptions(for display: Display, includeHidden: Bool) -> [RefreshOption] {
        guard let current = display.currentMode else { return [] }
        let key = ResolutionGroup.Key(current)
        var best: [Int: DisplayMode] = [:]
        for mode in display.modes where ResolutionGroup.Key(mode) == key {
            guard includeHidden || mode.origin == .system || mode.modeID == current.modeID else { continue }
            if let existing = best[mode.refreshKey], rank(existing, current) >= rank(mode, current) { continue }
            best[mode.refreshKey] = mode
        }
        return best.values
            .sorted { $0.refreshKey > $1.refreshKey }
            .map { RefreshOption(mode: $0, isCurrent: $0.modeID == current.modeID) }
    }

    /// For modes with the same refresh rate: the current mode, then the current bit depth,
    /// then system modes.
    private static func rank(_ mode: DisplayMode, _ current: DisplayMode) -> Int {
        (mode.modeID == current.modeID ? 4 : 0)
            + (mode.bitsPerSample == current.bitsPerSample ? 2 : 0)
            + (mode.origin == .system ? 1 : 0)
    }

    private static func systemThenFastest(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        let lhsRank = lhs.origin == .system ? 0 : 1
        let rhsRank = rhs.origin == .system ? 0 : 1
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.refreshKey != rhs.refreshKey { return lhs.refreshKey > rhs.refreshKey }
        return lhs.modeID < rhs.modeID
    }
}
