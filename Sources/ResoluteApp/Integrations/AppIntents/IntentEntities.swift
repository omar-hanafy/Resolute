import AppIntents
import CoreGraphics
import Foundation
import ResoluteKit

/// A connected display, as Shortcuts names it and as Get Displays returns it.
struct DisplayEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Display" }
    static let defaultQuery = DisplayQuery()

    /// `ShortcutCatalog.identifier(of:among:)`: the same display keeps it across restarts.
    let id: String
    @Property(title: "Name") var name: String
    /// "1728 × 1117"; empty when the mode is not known.
    @Property(title: "Resolution") var resolution: String
    /// "120 Hz"; empty when the display reports none.
    @Property(title: "Refresh Rate") var refreshRate: String
    @Property(title: "Main Display") var isMain: Bool
    @Property(title: "Built-in") var isBuiltIn: Bool
    @Property(title: "Mirrored") var isMirrored: Bool

    init(id: String, name: String, resolution: String, refreshRate: String, isMain: Bool, isBuiltIn: Bool, isMirrored: Bool) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.isMirrored = isMirrored
    }

    /// "1728 × 1117 · 120 Hz", as the panel's cards say it.
    var summary: String {
        [resolution, refreshRate].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

/// One resolution a display lists, by its size in points and in pixels. It names its display,
/// so a Spotlight action can switch the display that has it without asking which one.
struct ResolutionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Resolution" }
    static let defaultQuery = ResolutionQuery()

    /// The display's `DisplayEntity` ID.
    var displayID: String
    /// Empty when the display is not connected.
    var displayName: String
    var key: ResolutionGroup.Key
    /// A 1× size on a display that also has HiDPI ones.
    var isLowResolution: Bool

    /// "<display>|1496x967|2992x1934".
    var id: String {
        "\(displayID)|\(key.width)x\(key.height)|\(key.pixelWidth)x\(key.pixelHeight)"
    }

    /// "1496 × 967".
    var sizeText: String { "\(key.width) × \(key.height)" }

    var displayRepresentation: DisplayRepresentation {
        let parts = [displayName, isLowResolution ? ResolutionSection.Kind.lowResolution.title : ""].filter { !$0.isEmpty }
        return DisplayRepresentation(title: "\(sizeText)", subtitle: "\(parts.joined(separator: " · "))")
    }
}

/// A refresh rate, such as 120 Hz.
struct RefreshRateEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Refresh Rate" }
    static let defaultQuery = RefreshRateQuery()

    var hertz: Double

    /// Hundredths of a hertz, as `RefreshRate.key` gives them: "12000".
    var id: String { String(RefreshRate.key(hertz)) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(RefreshRate.format(hertz))")
    }
}

/// A preset from the presets file.
struct PresetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Preset" }
    static let defaultQuery = PresetQuery()

    let id: UUID
    var name: String
    /// "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz".
    var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

/// Which displays Get Displays returns.
enum DisplayScope: String, AppEnum {
    case all
    case main

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Displays" }
    static var caseDisplayRepresentations: [DisplayScope: DisplayRepresentation] {
        [
            .all: "all displays",
            .main: "the main display",
        ]
    }
}

/// What Mirror Displays does.
enum MirroringChange: String, AppEnum {
    case turnOn
    case turnOff
    case toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mirroring" }
    static var caseDisplayRepresentations: [MirroringChange: DisplayRepresentation] {
        [
            .turnOn: "Turn on",
            .turnOff: "Turn off",
            .toggle: "Toggle",
        ]
    }
}

// MARK: - Queries

/// The connected displays. Each query reads them fresh from the running app.
struct DisplayQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        let model = try await IntentHost.readyModel()
        model.refresh()
        return ShortcutCatalog.displays(model.displays).filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [DisplayEntity] {
        let model = try await IntentHost.readyModel()
        model.refresh()
        return ShortcutCatalog.displays(model.displays)
    }
}

/// The resolutions the displays list: those of the display Set Resolution names, else every
/// connected display's. Hidden modes are left out.
struct ResolutionQuery: EntityQuery {
    @IntentParameterDependency<SetResolutionIntent>(\.$display) var setResolution

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ResolutionEntity] {
        let model = try await IntentHost.readyModel()
        model.refresh()
        return identifiers.compactMap { ShortcutCatalog.resolution(id: $0, displays: model.displays) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ResolutionEntity] {
        let model = try await IntentHost.readyModel()
        model.refresh()
        let display: DisplayEntity? = setResolution?.display
        return ShortcutCatalog.resolutions(of: model.displays, onlyOn: display?.id)
    }
}

/// The refresh rates the displays list at their current resolution: those of the display Set
/// Refresh Rate names, else every connected display's.
struct RefreshRateQuery: EntityQuery {
    @IntentParameterDependency<SetRefreshRateIntent>(\.$display) var setRefreshRate

    func entities(for identifiers: [String]) async throws -> [RefreshRateEntity] {
        identifiers.compactMap(ShortcutCatalog.refreshRate(id:))
    }

    @MainActor
    func suggestedEntities() async throws -> [RefreshRateEntity] {
        let model = try await IntentHost.readyModel()
        model.refresh()
        let display: DisplayEntity? = setRefreshRate?.display
        return ShortcutCatalog.refreshRates(of: model.displays, onlyOn: display?.id)
    }
}

/// The presets, as the presets file holds them now; Siri finds one by name.
struct PresetQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        try await presets().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PresetEntity] {
        ShortcutCatalog.presets(try await presets(), matching: string)
    }

    @MainActor
    func suggestedEntities() async throws -> [PresetEntity] {
        try await presets()
    }

    @MainActor
    private func presets() async throws -> [PresetEntity] {
        let model = try await IntentHost.readyModel()
        model.reloadPresets()
        return ShortcutCatalog.presets(model.presets)
    }
}

// MARK: - The catalog

/// Turns displays and presets into what Shortcuts offers, apart from the running app so tests
/// can read it. Listed modes only: nobody may be watching the display a shortcut switches.
enum ShortcutCatalog {
    /// "builtin" for the built-in display, else its vendor, product and serial number, as
    /// "10ac-41bb-0". Identical displays that report no serial number add their display ID,
    /// as "10ac-41bb-0@3", which lasts only while they stay connected.
    static func identifier(of display: Display, among displays: [Display]) -> String {
        if display.isBuiltin { return "builtin" }
        let model = modelIdentifier(of: display)
        let twins = displays.filter { !$0.isBuiltin && modelIdentifier(of: $0) == model }
        return twins.count > 1 ? "\(model)@\(display.id)" : model
    }

    private static func modelIdentifier(of display: Display) -> String {
        "\(String(display.vendorID, radix: 16))-\(String(display.productID, radix: 16))-\(display.serialNumber)"
    }

    /// The connected display `id` names. One named with its display ID that has since come
    /// back under another is still found while it is the only one of its kind.
    static func display(for id: String, in displays: [Display]) -> Display? {
        if let exact = displays.first(where: { identifier(of: $0, among: displays) == id }) { return exact }
        let model = id.split(separator: "@").first.map(String.init) ?? id
        let matches = displays.filter { !$0.isBuiltin && modelIdentifier(of: $0) == model }
        return matches.count == 1 ? matches[0] : nil
    }

    static func displays(_ displays: [Display]) -> [DisplayEntity] {
        displays.map { entity(for: $0, among: displays) }
    }

    static func entity(for display: Display, among displays: [Display]) -> DisplayEntity {
        DisplayEntity(
            id: identifier(of: display, among: displays),
            name: display.name,
            resolution: display.currentMode?.sizeText ?? "",
            refreshRate: display.currentMode.map { RefreshRate.format($0.refreshRate) } ?? "",
            isMain: display.isMain,
            isBuiltIn: display.isBuiltin,
            isMirrored: display.isInMirrorSet
        )
    }

    /// The resolutions `display` lists, larger first: its system modes, never hidden ones.
    static func listedGroups(of display: Display) -> [ResolutionGroup] {
        ModeCatalog.groups(display.modes.filter { $0.origin == .system })
    }

    /// Every listed resolution of each display, or only of the display `displayID` names.
    static func resolutions(of displays: [Display], onlyOn displayID: String?) -> [ResolutionEntity] {
        displays.flatMap { display -> [ResolutionEntity] in
            let id = identifier(of: display, among: displays)
            guard displayID == nil || displayID == id else { return [] }
            let groups = listedGroups(of: display)
            let hasHiDPI = groups.contains(where: \.isHiDPI)
            return groups.map { group in
                ResolutionEntity(
                    displayID: id, displayName: display.name, key: group.key, isLowResolution: hasHiDPI && !group.isHiDPI
                )
            }
        }
    }

    /// The resolution `id` names, with its display's name while it is connected. A
    /// resolution the display does not list now is still read, so that switching to it can
    /// say why it can't.
    static func resolution(id: String, displays: [Display]) -> ResolutionEntity? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, let size = dimensions(parts[1]), let pixels = dimensions(parts[2]) else { return nil }
        let displayID = String(parts[0])
        let key = ResolutionGroup.Key(width: size.0, height: size.1, pixelWidth: pixels.0, pixelHeight: pixels.1)
        let display = display(for: displayID, in: displays)
        let hasHiDPI = display.map { listedGroups(of: $0).contains(where: \.isHiDPI) } ?? false
        return ResolutionEntity(
            displayID: displayID, displayName: display?.name ?? "", key: key,
            isLowResolution: hasHiDPI && key.pixelWidth <= key.width
        )
    }

    private static func dimensions(_ text: Substring) -> (Int, Int)? {
        let numbers = text.split(separator: "x").compactMap { Int($0) }
        guard numbers.count == 2, numbers.allSatisfy({ $0 > 0 }) else { return nil }
        return (numbers[0], numbers[1])
    }

    /// The listed rates of each display at its current resolution, or only of the display
    /// `displayID` names; fastest first, each rate once.
    static func refreshRates(of displays: [Display], onlyOn displayID: String?) -> [RefreshRateEntity] {
        var seen = Set<Int>()
        return displays
            .filter { displayID == nil || identifier(of: $0, among: displays) == displayID }
            .flatMap { ModeCatalog.refreshOptions(for: $0, includeHidden: false).map(\.refreshRate) }
            .filter { RefreshRate.key($0) > 0 }
            .sorted(by: >)
            .filter { seen.insert(RefreshRate.key($0)).inserted }
            .map(RefreshRateEntity.init(hertz:))
    }

    /// The rate `id` names, in hundredths of a hertz.
    static func refreshRate(id: String) -> RefreshRateEntity? {
        guard let hundredths = Int(id), hundredths > 0 else { return nil }
        return RefreshRateEntity(hertz: Double(hundredths) / 100)
    }

    static func presets(_ presets: [Preset]) -> [PresetEntity] {
        presets.map { PresetEntity(id: $0.id, name: $0.name, summary: $0.summary) }
    }

    /// The presets whose name contains `string`, ignoring case.
    static func presets(_ presets: [PresetEntity], matching string: String) -> [PresetEntity] {
        let wanted = string.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return presets }
        return presets.filter { $0.name.localizedCaseInsensitiveContains(wanted) }
    }
}
