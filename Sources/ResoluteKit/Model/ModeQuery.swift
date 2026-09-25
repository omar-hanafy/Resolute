import Foundation

/// A request for a display mode, as typed on the command line.
public struct ModeQuery: Hashable, Sendable {
    public var width: Int?
    public var height: Int?
    /// 2 for HiDPI, 1 for low resolution.
    public var scale: Double?
    public var refreshRate: Double?
    public var modeID: Int32?
    public var useDefault: Bool
    public var allowHidden: Bool

    public init(
        width: Int? = nil,
        height: Int? = nil,
        scale: Double? = nil,
        refreshRate: Double? = nil,
        modeID: Int32? = nil,
        useDefault: Bool = false,
        allowHidden: Bool = false
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        self.refreshRate = refreshRate
        self.modeID = modeID
        self.useDefault = useDefault
        self.allowHidden = allowHidden
    }

    /// The largest width or height a query can name. No display mode comes close, and
    /// larger numbers would overflow the arithmetic done with sizes.
    public static let maximumDimension = 65_535

    /// Whether `hertz` could be a display's refresh rate.
    public static func isPlausible(refreshRate hertz: Double) -> Bool {
        hertz > 0 && hertz <= 10_000
    }

    /// Whether `scale` could be a display mode's scale (1 for low resolution, 2 for HiDPI).
    public static func isPlausible(scale: Double) -> Bool {
        scale > 0 && scale <= 8
    }

    /// Parses "1920x1080", "1920×1080", "1920x1080@2x", "1920x1080@60" and
    /// "1920x1080@2x@59.94Hz".
    public init(resolution text: String) throws {
        self.init()
        let normalized = text.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " ", with: "")
        var parts = normalized.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        let size = parts.removeFirst()
        let dimensions = size.split(separator: "x", omittingEmptySubsequences: false)
        guard dimensions.count == 2,
              let width = Int(dimensions[0]), let height = Int(dimensions[1]),
              (1...Self.maximumDimension).contains(width), (1...Self.maximumDimension).contains(height)
        else { throw ResoluteError.invalidResolution(text) }
        self.width = width
        self.height = height
        for part in parts {
            if part.hasSuffix("x"), let scale = Double(part.dropLast()), Self.isPlausible(scale: scale) {
                self.scale = scale
            } else if let hertz = Double(part.hasSuffix("hz") ? String(part.dropLast(2)) : part),
                      Self.isPlausible(refreshRate: hertz) {
                self.refreshRate = hertz
            } else {
                throw ResoluteError.invalidResolution(text)
            }
        }
    }

    /// "1920 × 1080 @2x 60 Hz", for messages.
    public var summary: String {
        var parts: [String] = []
        if let modeID { parts.append("mode \(modeID)") }
        if useDefault { parts.append("the default mode") }
        if let width, let height { parts.append("\(width) × \(height)") }
        if let scale {
            let whole = scale.isFinite && abs(scale) < 1_000 && scale == scale.rounded()
            parts.append(whole ? "@\(Int(scale))x" : "@\(scale)x")
        }
        if let refreshRate, case let rate = RefreshRate.format(refreshRate), !rate.isEmpty { parts.append(rate) }
        return parts.isEmpty ? "the current mode" : parts.joined(separator: " ")
    }

    /// The mode this query picks on `display`.
    public func resolve(on display: Display) throws -> DisplayMode {
        if let modeID {
            guard let mode = display.modes.first(where: { $0.modeID == modeID }) else {
                throw ResoluteError.modeNotFound(summary, suggestions: [])
            }
            guard allowHidden || mode.origin == .system else {
                throw ResoluteError.hiddenModeNeedsConfirmation(summary)
            }
            return mode
        }
        if width == nil, height == nil, !useDefault, display.currentMode == nil {
            // Only a refresh rate or scale was given, but there is no current size to keep.
            throw ResoluteError.currentModeUnknown(display: display.name)
        }
        let matches = matchingModes(on: display, includeHidden: allowHidden)
        guard !matches.isEmpty else {
            if !allowHidden, !matchingModes(on: display, includeHidden: true).isEmpty {
                throw ResoluteError.hiddenModeNeedsConfirmation(summary)
            }
            throw ResoluteError.modeNotFound(summary, suggestions: suggestions(on: display))
        }
        let current = display.currentMode
        let groups = ModeCatalog.groups(matches)
        // Prefer the scale the display uses now, then HiDPI.
        let sameScale = groups.first { group in
            current.map { abs(group.modes[0].scale - $0.scale) < 0.01 } ?? false
        }
        let group = sameScale ?? groups.first(where: \.isHiDPI) ?? groups[0]
        return ModeCatalog.preferredMode(in: group, current: current)
    }

    func matchingModes(on display: Display, includeHidden: Bool) -> [DisplayMode] {
        let current = display.currentMode
        return display.modes.filter { mode in
            guard includeHidden || mode.origin == .system else { return false }
            if useDefault, !mode.isDefault { return false }
            if let width, let height {
                guard mode.width == width, mode.height == height else { return false }
            } else if !useDefault, let current {
                // Only a scale or a refresh rate was given: keep the current size.
                guard mode.width == current.width, mode.height == current.height else { return false }
            }
            if let scale, abs(mode.scale - scale) >= 0.01 { return false }
            if let refreshRate, mode.refreshKey != RefreshRate.key(refreshRate) { return false }
            return true
        }
    }

    /// The three system resolutions closest in area to the one asked for.
    func suggestions(on display: Display) -> [String] {
        guard let width, let height else { return [] }
        let target = width * height
        func distance(_ group: ResolutionGroup) -> Int {
            abs(group.key.width * group.key.height - target)
        }
        return ModeCatalog.groups(display.modes.filter { $0.origin == .system })
            .sorted { lhs, rhs in
                (distance(lhs), lhs.isHiDPI ? 0 : 1, -lhs.key.width) < (distance(rhs), rhs.isHiDPI ? 0 : 1, -rhs.key.width)
            }
            .prefix(3)
            .map { $0.sizeText + ($0.isHiDPI ? " (HiDPI)" : "") }
    }
}
