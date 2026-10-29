import Foundation
import ResoluteDesign
import ResoluteKit

/// A badge under a display's name (Figma: Display Header): "Main", "Built-in", "HiDPI",
/// "Standard display", "Override installed", "Not connected", "Unsaved".
struct HeaderBadge: Equatable {
    var text: String
    var tone: Badge.Tone
}

/// What a display's page shows, worked out from the app model and the display's editor, so
/// the views only lay it out.
enum DisplayPagePresentation {
    /// The tabs a display's page offers: a display that is not connected can't switch modes.
    static func tabs(isConnected: Bool) -> [DisplayTab] {
        isConnected ? DisplayTab.allCases : [.customResolutions, .pictureAndName]
    }

    /// The tab to show for `requested`: one the page offers.
    static func tab(_ requested: DisplayTab, isConnected: Bool) -> DisplayTab {
        tabs(isConnected: isConnected).contains(requested) ? requested : .customResolutions
    }

    /// A connected display's badges: Main (when there is another display), Built-in, then
    /// Override installed, or else what kind of sizes it has, and Unsaved.
    static func badges(
        for display: Display,
        facts: DisplayFacts,
        displayCount: Int,
        hasOverride: Bool,
        hasUnsavedChanges: Bool,
        sharpScaling: String? = nil
    ) -> [HeaderBadge] {
        var badges: [HeaderBadge] = []
        if display.isMain, displayCount > 1 { badges.append(HeaderBadge(text: "Main", tone: .neutral)) }
        if display.isBuiltin { badges.append(HeaderBadge(text: "Built-in", tone: .neutral)) }
        if let sharpScaling {
            // The override is Sharp Scaling's, so its badge says what the file does
            // (Figma 67:1585, 67:2175).
            if facts.kind == .standard { badges.append(HeaderBadge(text: "Standard display", tone: .neutral)) }
            badges.append(HeaderBadge(text: sharpScaling, tone: .accent))
        } else if hasOverride {
            badges.append(HeaderBadge(text: "Override installed", tone: .accent))
        } else if facts.kind == .standard {
            badges.append(HeaderBadge(text: "Standard display", tone: .neutral))
        } else if display.currentMode?.isHiDPI == true {
            badges.append(HeaderBadge(text: "HiDPI", tone: .accent))
        }
        if hasUnsavedChanges { badges.append(HeaderBadge(text: "Unsaved", tone: .warning)) }
        return badges
    }

    /// The badges of a display that is not connected (Figma 37:1480).
    static func notConnectedBadges(hasOverride: Bool, hasUnsavedChanges: Bool) -> [HeaderBadge] {
        var badges = [HeaderBadge(text: "Not connected", tone: .neutral)]
        if hasOverride { badges.append(HeaderBadge(text: "Override installed", tone: .accent)) }
        if hasUnsavedChanges { badges.append(HeaderBadge(text: "Unsaved", tone: .warning)) }
        return badges
    }

    /// The picture to draw for a display: the one its draft shows when that is one Resolute
    /// draws, else `fallback`, the picture its saved override or its kind suggests.
    static func picture(draftSkin: String?, fallback: DisplaySkin) -> DisplayPictureModel {
        let skin = draftSkin.flatMap(DisplaySkin.init(rawValue:)).flatMap { $0 == .display ? nil : $0 } ?? fallback
        return DisplayPictureModel(rawValue: skin.rawValue) ?? .display
    }

    /// The Picture section's choices, each enabled only when this Mac can draw it.
    static func pictureChoices(canChoose: (String) -> Bool) -> [PictureChoicePicker.Choice] {
        DisplayIcons.skins.compactMap { skin in
            guard let model = DisplayPictureModel(rawValue: skin) else { return nil }
            let title = skin == DisplayIcons.defaultSkin ? "Display (default)" : model.title
            let isEnabled = canChoose(skin)
            return PictureChoicePicker.Choice(
                model, title: title, isEnabled: isEnabled,
                help: isEnabled ? nil : "macOS has no picture of \(article(for: model)) \(model.title) to show in System Settings."
            )
        }
    }

    /// Says which pictures can't be chosen, under the grid; nil when every one can.
    static func unavailablePicturesNote(_ choices: [PictureChoicePicker.Choice]) -> String? {
        let titles = choices.filter { !$0.isEnabled }.map(\.title)
        guard !titles.isEmpty else { return nil }
        let list = titles.count == 1 ? titles[0] : titles.dropLast().joined(separator: ", ") + " and " + titles[titles.count - 1]
        let verb = titles.count == 1 ? "it" : "them"
        return "This Mac has no picture for \(list), so macOS can't show \(verb) in System Settings."
    }

    private static func article(for model: DisplayPictureModel) -> String {
        model == .iMac || model == .ultrawide ? "an" : "a"
    }

    /// "Last connected 21 Oct · 5120 × 2880 pixels" for a display that is not connected,
    /// from what History recorded about it: when it last changed, and the panel's own size
    /// when a mode it recorded was the native one. Its IDs when History knows nothing.
    static func notConnectedFacts(
        for key: OverrideKey,
        history: [HistoryEntry],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var last: Date?
        var native: HistoryEntry.ModeRecord?
        for entry in history {
            guard case .mode(let change) = entry.change,
                  change.display.vendorID == key.vendorID, change.display.productID == key.productID
            else { continue }
            if last.map({ entry.date > $0 }) ?? true { last = entry.date }
            if native == nil {
                native = [change.to, change.from].compactMap { $0 }.first { $0.ioFlags & DisplayMode.Flag.native != 0 }
            }
        }
        var parts: [String] = []
        if let last {
            var calendar = calendar
            calendar.locale = locale
            let sameYear = calendar.component(.year, from: last) == calendar.component(.year, from: Date())
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
            if !sameYear { style = style.year() }
            parts.append("Last connected \(last.formatted(style))")
        }
        if let native {
            parts.append("\(native.pixelWidth) × \(native.pixelHeight) pixels")
        }
        if parts.isEmpty {
            parts.append("Vendor \(String(key.vendorID, radix: 16)) · Product \(String(key.productID, radix: 16))")
        }
        return parts.joined(separator: " · ")
    }

    /// What to call a display that is not connected: the name its override file gives it,
    /// else the name History last recorded for it, else its IDs ("Display 1e6d:5b11").
    @MainActor
    static func notConnectedName(for key: OverrideKey, listed: String?, history: [HistoryEntry]) -> String {
        let fallback = AppModel.fallbackName(for: key)
        if let listed, listed != fallback { return listed }
        let recorded = history
            .filter { entry in
                guard case .mode(let change) = entry.change else { return false }
                return change.display.vendorID == key.vendorID && change.display.productID == key.productID
            }
            .max { $0.date < $1.date }
        if case .mode(let change)? = recorded?.change, !change.display.name.isEmpty {
            return change.display.name
        }
        return fallback
    }

    /// The tone of a display's desktop pictures: the built-in display's violet wallpaper, or
    /// an external display's teal one.
    static func tone(for display: Display?) -> SpaceThumbnail.Tone {
        display?.isBuiltin == true ? .violet : .teal
    }
}
