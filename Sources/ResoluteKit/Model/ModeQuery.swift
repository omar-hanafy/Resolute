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
        hertz >= 1 && hertz <= 10_000
    }

    /// Whether `scale` could be a display mode's scale (1 for low resolution, 2 for HiDPI).
    public static func isPlausible(scale: Double) -> Bool {
        scale > 0 && scale <= 8
    }

    /// A plain decimal number such as "60" or "59.94": ASCII digits, with at most one point
    /// between them. `Double(_:)` alone also reads "0x3c", "6e1", "+60", "inf" and "nan".
    public static func decimal(_ text: some StringProtocol) -> Double? {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return Double(String(text))
    }

    /// Parses "1920x1080", "1920×1080", "1920x1080@2x", "1920x1080@60" and
    /// "1920x1080@2x@59.94Hz". A scale or rate given twice is an error, not a choice.
    public init(resolution text: String) throws {
        self.init()
        let normalized = text.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " ", with: "")
        var parts = normalized.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        let size = parts.removeFirst()
        let dimensions = size.split(separator: "x", omittingEmptySubsequences: false)
        guard dimensions.count == 2 else { throw ResoluteError.invalidResolution(text) }
        let width = Int(dimensions[0]), height = Int(dimensions[1])
        // Plain numbers beyond any display (Int overflow included) are too large, not malformed.
        let isNumber = { (part: Substring) in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }
        if isNumber(dimensions[0]), isNumber(dimensions[1]),
           (width ?? .max) > Self.maximumDimension || (height ?? .max) > Self.maximumDimension {
            throw ResoluteError.sizeTooLarge(text)
        }
        guard let width, let height, width > 0, height > 0 else { throw ResoluteError.invalidResolution(text) }
        self.width = width
        self.height = height
        for part in parts {
            if self.scale == nil, part.hasSuffix("x"), let scale = Self.decimal(part.dropLast()), Self.isPlausible(scale: scale) {
                self.scale = scale
            } else if self.refreshRate == nil, let hertz = Self.decimal(part.hasSuffix("hz") ? part.dropLast(2) : Substring(part)),
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
        guard !matches.isEmpty else { throw noMatch(on: display) }
        let group = Self.preferredGroup(ModeCatalog.groups(matches), current: display.currentMode)
        return ModeCatalog.preferredMode(in: group, current: display.currentMode)
    }

    /// The group at the scale the display uses now, else a HiDPI one, else the first.
    static func preferredGroup(_ groups: [ResolutionGroup], current: DisplayMode?) -> ResolutionGroup {
        let sameScale = groups.first { group in
            current.map { abs(group.modes[0].scale - $0.scale) < 0.01 } ?? false
        }
        return sameScale ?? groups.first(where: \.isHiDPI) ?? groups[0]
    }

    /// Why nothing matches, in the most useful terms.
    private func noMatch(on display: Display) -> ResoluteError {
        let described = withKeptSize(on: display).summary
        if !allowHidden, !matchingModes(on: display, includeHidden: true).isEmpty {
            return .hiddenModeNeedsConfirmation(described)
        }
        if let refreshRate {
            // The resolution exists but not at this rate: say which rates it has.
            var anyRate = self
            anyRate.refreshRate = nil
            let sameSize = anyRate.matchingModes(on: display, includeHidden: allowHidden)
            if !sameSize.isEmpty {
                let group = Self.preferredGroup(ModeCatalog.groups(sameSize), current: display.currentMode)
                let offered = group.refreshRates.filter { $0 > 0 }.map(RefreshRate.format)
                if !offered.isEmpty {
                    return .refreshRateNotOffered(
                        resolution: group.sizeText + (group.isHiDPI ? " HiDPI" : ""),
                        rate: RefreshRate.format(refreshRate),
                        offered: offered
                    )
                }
            }
        }
        return .modeNotFound(described, suggestions: suggestions(on: display))
    }

    /// This query with the size it keeps filled in: `--scale 1` keeps 1728 × 1117.
    private func withKeptSize(on display: Display) -> ModeQuery {
        guard width == nil, height == nil, !useDefault, modeID == nil, let current = display.currentMode else {
            return self
        }
        var query = self
        query.width = current.width
        query.height = current.height
        return query
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

    /// The three system resolutions closest in area to the one asked for or kept, at the
    /// scale asked for when there is one. A HiDPI resolution that renders at the size asked
    /// for comes first: sizes are in points, and that size was probably given in pixels.
    func suggestions(on display: Display) -> [String] {
        let query = withKeptSize(on: display)
        guard let width = query.width, let height = query.height else { return [] }
        let target = width * height
        func distance(_ group: ResolutionGroup) -> Int {
            abs(group.key.width * group.key.height - target)
        }
        func rendersAtTarget(_ group: ResolutionGroup) -> Bool {
            group.isHiDPI && group.key.pixelWidth == width && group.key.pixelHeight == height && (scale.map { $0 > 1 } ?? true)
        }
        return ModeCatalog.groups(display.modes.filter { $0.origin == .system })
            .filter { group in rendersAtTarget(group) || (scale.map { abs(group.modes[0].scale - $0) < 0.01 } ?? true) }
            .sorted { lhs, rhs in
                (rendersAtTarget(lhs) ? 0 : 1, distance(lhs), lhs.isHiDPI ? 0 : 1, -lhs.key.width)
                    < (rendersAtTarget(rhs) ? 0 : 1, distance(rhs), rhs.isHiDPI ? 0 : 1, -rhs.key.width)
            }
            .prefix(3)
            .map { group in
                if rendersAtTarget(group) { return "\(group.sizeText) (HiDPI, rendered at \(group.pixelSizeText) pixels)" }
                return group.sizeText + (group.isHiDPI ? " (HiDPI)" : "")
            }
    }
}
