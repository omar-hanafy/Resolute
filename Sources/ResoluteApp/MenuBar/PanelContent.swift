import CoreGraphics
import ResoluteDesign
import ResoluteKit

/// What the panel shows, worked out from the app model as plain values (Figma: Menu bar
/// panel 23:557, one display 23:818, waiting 24:1157, mirroring 24:1435). The panel's views
/// turn them into design-system components; tests check them without drawing.
@MainActor
enum PanelContent {
    /// One card: a display, or a mirror set sharing one.
    struct Card: Identifiable, Equatable {
        /// The display a choice switches: the mirror set's source when mirroring.
        var displayID: CGDirectDisplayID
        var name: String
        /// "1728 × 1117 · 120 Hz", "Mirroring · 1920 × 1080 · 60 Hz", or
        /// "Not responding · trying 2880 × 1620".
        var summary: String
        var skin: DisplaySkin
        var badge: Badge?
        var sizes: Sizes
        /// Empty when the display offers one rate at its resolution.
        var refreshRates: [Choice<Double>]
        var resolutionCount: Int
        /// False while the display is dark during a trial and its revert waits for it.
        var isResponding: Bool

        var id: CGDirectDisplayID { displayID }
    }

    struct Badge: Equatable {
        var text: String
        var isAccent = false
    }

    enum Sizes: Equatable {
        /// Larger Text ↔ More Space, with the caption under the stops. Built-in displays draw
        /// their thumbnails in violet, others in teal.
        case stops([Choice<DisplayMode>], caption: String, isBuiltIn: Bool)
        /// A standard display's resolutions, for its pop-up.
        case resolutions([Choice<DisplayMode>])
    }

    struct Choice<Value: Equatable>: Equatable {
        var title: String
        var accessibilityLabel: String
        var isSelected: Bool
        var value: Value
    }

    /// The banner for a display whose revert waits for it to come back.
    struct Waiting: Identifiable, Equatable {
        var displayID: CGDirectDisplayID
        var title: String
        var message: String

        var id: CGDirectDisplayID { displayID }
    }

    // MARK: - Cards

    /// A card for each display, the one in use first; a mirror set shares one card.
    static func cards(for model: AppModel) -> [Card] {
        let waiting = Set(model.pendingRestores.map(\.displayID))
        var cards: [Card] = []
        for display in model.displays {
            // A display that mirrors another is on its source's card.
            if display.mirrorSourceID != nil, model.displays.contains(where: { $0.id == display.mirrorSourceID }) { continue }
            let mirrors = model.displays.filter { $0.mirrorSourceID == display.id }
            cards.append(card(
                for: display, mirroredBy: mirrors, model: model,
                trying: waiting.contains(display.id) ? model.trialsAwaitingRestore[display.id]?.last?.mode : nil,
                isWaiting: waiting.contains(display.id)
            ))
        }
        return cards
    }

    static func card(
        for display: Display, mirroredBy mirrors: [Display], model: AppModel, trying: DisplayMode?, isWaiting: Bool
    ) -> Card {
        let facts = model.facts(for: display)
        let preferences = model.preferences
        let isMirroring = !mirrors.isEmpty
        let isSharp = model.sharpScaling.isSharp(display)
        let name = isMirroring ? ([display] + mirrors).map(shortName(of:)).joined(separator: " + ") : display.name
        let summary: String
        if isWaiting {
            summary = "Not responding" + (trying.map { " · trying \($0.sizeText)" } ?? "")
        } else if isMirroring {
            summary = ["Mirroring", facts.summary].compactMap { $0 }.joined(separator: " · ")
        } else {
            summary = facts.summary ?? "Mode unknown"
        }
        var badge: Badge?
        if isSharp {
            badge = Badge(text: "Sharp", isAccent: true)
        } else if !isMirroring, let text = facts.badge {
            badge = Badge(text: text)
        }
        let sizes: Sizes
        if let stops = model.stops(for: display) {
            var caption = stops.currentLabel ?? display.currentMode?.sizeText ?? ""
            if isSharp, !caption.isEmpty { caption += " · Sharp" }
            sizes = .stops(
                stops.stops.map { Choice(title: $0.label, accessibilityLabel: $0.accessibilityLabel, isSelected: $0.isCurrent, value: $0.mode) },
                caption: caption,
                isBuiltIn: display.isBuiltin && !isMirroring
            )
        } else {
            sizes = .resolutions(resolutions(of: display))
        }
        let rates = ModeCatalog.refreshOptions(for: display, includeHidden: false)
        return Card(
            displayID: display.id,
            name: name,
            summary: summary,
            skin: isMirroring ? .display : model.skin(for: display),
            badge: badge,
            sizes: sizes,
            refreshRates: rates.count > 1 ? rates.map { option in
                let title = RefreshRate.format(option.refreshRate)
                return Choice(title: title, accessibilityLabel: title, isSelected: option.isCurrent, value: option.refreshRate)
            } : [],
            resolutionCount: DisplayFacts.resolutionCount(
                for: display, includeLowResolution: preferences.showLowResolutionModes, includeHidden: preferences.showHiddenModes
            ),
            isResponding: !isWaiting
        )
    }

    /// A standard display's listed resolutions, larger first, each at the refresh rate in
    /// use when it has it: "2560 × 1440 · Native".
    static func resolutions(of display: Display) -> [Choice<DisplayMode>] {
        let current = ModeCatalog.currentKey(for: display)
        let sections = ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: false)
        return sections.filter { $0.kind != .hidden }.flatMap(\.groups).map { group in
            let title = group.badge.map { "\(group.sizeText) · \($0)" } ?? group.sizeText
            return Choice(
                title: title, accessibilityLabel: SpokenText.sizes(title), isSelected: group.key == current,
                value: ModeCatalog.preferredMode(in: group, current: display.currentMode)
            )
        }
    }

    /// "Built-in" for a built-in display in a mirror set's name, as the design writes it.
    static func shortName(of display: Display) -> String {
        display.isBuiltin ? "Built-in" : display.name
    }

    // MARK: - Waiting

    /// A banner for each revert that waits for its display (Figma 24:1157).
    static func waiting(for model: AppModel) -> [Waiting] {
        model.pendingRestores.map { restore in
            // The revert puts back the mode from before the first of them.
            let awaited = model.trialsAwaitingRestore[restore.displayID] ?? []
            let message: String
            if let trying = awaited.last?.mode, let previous = awaited.first?.display.currentMode {
                message = "It went dark while trying \(trying.sizeText). Resolute switches it back to "
                    + "\(previous.sizeText) as soon as it reconnects."
            } else {
                message = "It went dark during a trial. Resolute switches it back as soon as it reconnects."
            }
            return Waiting(displayID: restore.displayID, title: "Waiting for \(restore.displayName)", message: message)
        }
    }
}

