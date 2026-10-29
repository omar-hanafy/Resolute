import Foundation
import ResoluteDesign
import ResoluteKit

/// What the Resolution tab offers for a display: its Larger Text ↔ More Space sizes, its
/// refresh rates, its resolutions for a standard display, and every mode for All Modes
/// (Figma: Window › Resolution 31:5; Sharp Scaling › page off 62:1020).
enum ResolutionChoices {
    // MARK: - Larger Text ↔ More Space

    /// The stop picker's options: each size, or its pixels while ⌥ is held, captioned
    /// "Default" for the default size.
    static func stopOptions(_ stops: SpaceStops, showsPixels: Bool) -> [StopPicker.Option] {
        stops.stops.map { stop in
            StopPicker.Option(
                stop: stop.thumbnail,
                size: showsPixels ? stop.mode.pixelSizeText : stop.label,
                caption: stop.isDefault ? "Default" : nil
            )
        }
    }

    /// The mode a click on the option for `thumbnail` switches to.
    static func mode(forStop thumbnail: Int, in stops: SpaceStops) -> DisplayMode? {
        stops.stops.first { $0.thumbnail == thumbnail }?.mode
    }

    static let stopFootnote = "Clicking a size switches right away. Hold ⌥ to see the pixel size of each."

    // MARK: - Refresh rate

    /// One refresh rate the pop-up lists, by `RefreshRate.key`.
    struct Rate: Hashable {
        var key: Int
        var hertz: Double
        var title: String
    }

    /// The listed rates at the current resolution, fastest first; a ProMotion display's
    /// fastest is "ProMotion", which adapts up to it.
    static func rates(for display: Display, facts: DisplayFacts) -> [Rate] {
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: false)
        let fastest = options.map(\.mode.refreshKey).max()
        return options.map { option in
            let key = option.mode.refreshKey
            let title = facts.hasProMotion && key == fastest ? "ProMotion" : RefreshRate.format(option.refreshRate)
            return Rate(key: key, hertz: option.refreshRate, title: title)
        }
    }

    /// The rate in use, by key.
    static func currentRateKey(of display: Display) -> Int? {
        display.currentMode?.refreshKey
    }

    /// The help under Refresh Rate: what ProMotion does, on a display that has it.
    static func refreshHelp(facts: DisplayFacts) -> String? {
        guard facts.hasProMotion, let fastest = facts.maximumRefreshRate else { return nil }
        return "ProMotion adapts up to \(RefreshRate.format(fastest)). Pick a fixed rate for video."
    }

    // MARK: - A standard display's resolutions

    /// One resolution of a standard display's pop-up: "2560 × 1440 · Native".
    struct Resolution: Hashable {
        var key: ResolutionGroup.Key
        var title: String
        var mode: DisplayMode
    }

    /// A standard display's listed resolutions, largest first, and the one in use.
    static func resolutions(for display: Display) -> [Resolution] {
        let current = display.currentMode
        return ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: false)
            .filter { $0.kind != .hidden }
            .flatMap(\.groups)
            .map { group in
                Resolution(
                    key: group.key,
                    title: group.badge.map { "\(group.sizeText) · \($0)" } ?? group.sizeText,
                    mode: ModeCatalog.preferredMode(in: group, current: current)
                )
            }
    }

    /// "This display has 1× sizes only. Sizes below 2560 × 1440 are stretched to fit and look soft."
    static func standardResolutionHelp(facts: DisplayFacts) -> String {
        let below = facts.nativeSize.map { "Sizes below \($0.text)" } ?? "Sizes below its own"
        return "This display has 1× sizes only. \(below) are stretched to fit and look soft."
    }

    // MARK: - All Modes

    /// All Modes' tabs (Figma: HiDPI | Low Resolution (1×) | Hidden).
    enum ModeFilter: String, CaseIterable, Hashable {
        case hiDPI
        case lowResolution
        case hidden

        var title: String {
            switch self {
            case .hiDPI: "HiDPI"
            case .lowResolution: "Low Resolution (1×)"
            case .hidden: "Hidden"
            }
        }
    }

    /// The tabs `display` has modes for.
    static func filters(for display: Display) -> [ModeFilter] {
        ModeFilter.allCases.filter { !groups(of: display, matching: $0).isEmpty }
    }

    /// The resolutions under `filter`, largest first.
    static func groups(of display: Display, matching filter: ModeFilter) -> [ResolutionGroup] {
        ModeCatalog.groups(display.modes).filter { group in
            switch filter {
            case .hiDPI: !group.isHidden && group.isHiDPI
            case .lowResolution: !group.isHidden && !group.isHiDPI
            case .hidden: group.isHidden
            }
        }
    }

    /// All Modes' rows: "1728 × 1117", "HiDPI · Default", "3456 × 2234", "120 · 60 · 50 · 48 Hz".
    static func modeRows(for display: Display, matching filter: ModeFilter) -> [TableRowValues<ResolutionGroup.Key>] {
        groups(of: display, matching: filter).map { group in
            let kind = [group.isHiDPI ? "HiDPI" : "1×", group.badge].compactMap { $0 }.joined(separator: " · ")
            let rates = group.refreshRates.map { RefreshRate.format($0).replacingOccurrences(of: " Hz", with: "") }.filter { !$0.isEmpty }
            let ratesText = rates.isEmpty ? "" : rates.joined(separator: " · ") + " Hz"
            let spoken = [SpokenText.sizes(group.sizeText), kind, "rendered at \(SpokenText.sizes(group.pixelSizeText))", ratesText]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return TableRowValues(id: group.key, values: [group.sizeText, kind, group.pixelSizeText, ratesText], accessibilityLabel: spoken)
        }
    }

    /// The footnote under the Hidden tab: hidden modes are tried first.
    static func hiddenFootnote(trialLength: TrialLength) -> String {
        "Hidden modes are tried first: each switches back after \(trialLength.title) unless you keep it on its display."
    }
}

/// A table row as plain values, which a page turns into a `DataTable` row.
struct TableRowValues<ID: Hashable>: Identifiable, Equatable {
    var id: ID
    var values: [String]
    var accessibilityLabel: String
}
