import AppIntents
import Foundation
import ResoluteKit

/// How intents reach the running app: the app delegate sets `appModel` once it has made the
/// model, and every intent and query waits for it. Intents run in the app's own process, and
/// macOS may launch Resolute to run one, so the first may arrive before launching ends.
@MainActor
enum IntentHost {
    static var appModel: AppModel?

    /// The app model, waiting up to `limit` for the app to finish launching.
    static func readyModel(waitingUpTo limit: Duration = .seconds(10)) async throws -> AppModel {
        let deadline = ContinuousClock.now + limit
        while true {
            if let appModel { return appModel }
            guard ContinuousClock.now < deadline else { throw ShortcutError.notReady }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Why a Shortcuts action did nothing, in the words Shortcuts and Spotlight show.
enum ShortcutError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    /// A Keep/Revert countdown is up, the app's own or one an agent asked for.
    case busy
    case notReady
    case notConnected(display: String)
    case notListed(size: String, display: String)
    case rateNotOffered(rate: String, display: String, size: String)
    case needsTwoDisplays
    /// The change failed, as its alert would have said.
    case failed(String)

    var message: String {
        switch self {
        case .busy:
            "Resolute is asking whether to keep a display setting. Answer that first, then try again."
        case .notReady:
            "Resolute is still starting. Try again in a moment."
        case .notConnected(let display):
            display.isEmpty ? "That display isn’t connected." : "\(display) isn’t connected."
        case .notListed(let size, let display):
            "\(display) doesn’t list \(size). Shortcuts can switch only to resolutions a display lists."
        case .rateNotOffered(let rate, let display, let size):
            "\(display) doesn’t offer \(rate) at \(size)."
        case .needsTwoDisplays:
            "Mirroring needs two displays."
        case .failed(let message):
            message
        }
    }

    var errorDescription: String? { message }

    var localizedStringResource: LocalizedStringResource { "\(message)" }

    /// A model failure as the alert would have said it.
    init(_ error: any Error) {
        self = (error as? ShortcutError) ?? .failed(error.localizedDescription)
    }
}

/// What the intents do, through the app model, so every change is guarded and recorded as the
/// panel's are, with Shortcuts as History's source. Listed modes only: nobody may be watching
/// the display, so nothing is tried that would need Keep or Revert. While a countdown is up,
/// the app's or an agent's, every change is refused with `ShortcutError.busy` rather than
/// done later or dropped. Failures are thrown, never shown as alerts.
@MainActor
struct ShortcutActions {
    let model: AppModel

    /// The actions of the running app, once it has finished launching.
    static func current() async throws -> ShortcutActions {
        ShortcutActions(model: try await IntentHost.readyModel())
    }

    /// Applies the preset, as the file holds it now. Returns its name.
    @discardableResult
    func applyPreset(_ entity: PresetEntity) throws -> String {
        try ensureIdle()
        model.reloadPresets()
        let preset = model.presets.first { $0.id == entity.id }
            ?? Preset(id: entity.id, name: entity.name, displays: [])
        do {
            guard let applied = try model.runPreset(preset, from: .shortcuts) else { throw ShortcutError.busy }
            return applied.name
        } catch {
            throw ShortcutError(error)
        }
    }

    /// Switches `display`, or the display the resolution names when none is given, to that
    /// resolution, or to its size on another display. Returns the display as it is now.
    @discardableResult
    func setResolution(_ resolution: ResolutionEntity, on display: DisplayEntity?) throws -> DisplayEntity {
        try ensureIdle()
        model.refresh()
        let target = try connected(display?.id ?? resolution.displayID, name: display?.name ?? resolution.displayName)
        let groups = ShortcutCatalog.listedGroups(of: target)
        // The same size in points and pixels, else the same size in points: groups come
        // larger first, so HiDPI before 1×.
        guard let group = groups.first(where: { $0.key == resolution.key })
            ?? groups.first(where: { $0.key.width == resolution.key.width && $0.key.height == resolution.key.height })
        else {
            throw ShortcutError.notListed(size: resolution.sizeText, display: target.name)
        }
        let mode = ModeCatalog.preferredMode(in: group, current: target.currentMode)
        try switchListed(mode, of: target)
        return try entity(for: target)
    }

    /// Switches `display` to `rate` at its current resolution. Returns the display as it is now.
    @discardableResult
    func setRefreshRate(_ rate: RefreshRateEntity, on display: DisplayEntity) throws -> DisplayEntity {
        try ensureIdle()
        model.refresh()
        let target = try connected(display.id, name: display.name)
        guard let option = AppModel.refreshOption(rate.hertz, of: target, includeHidden: false) else {
            throw ShortcutError.rateNotOffered(
                rate: RefreshRate.format(rate.hertz), display: target.name, size: target.currentMode?.sizeText ?? "this resolution"
            )
        }
        if !option.isCurrent {
            try switchListed(option.mode, of: target)
        }
        return try entity(for: target)
    }

    /// Turns mirroring on or off, or the other way from now. Returns whether it is on.
    @discardableResult
    func mirror(_ change: MirroringChange) throws -> Bool {
        try ensureIdle()
        model.refresh()
        guard model.canMirror else { throw ShortcutError.needsTwoDisplays }
        let enabled = switch change {
        case .turnOn: true
        case .turnOff: false
        case .toggle: !model.isMirroring
        }
        do {
            guard try model.changeMirroring(enabled, from: .shortcuts) else { throw ShortcutError.busy }
        } catch {
            throw ShortcutError(error)
        }
        return model.isMirroring
    }

    /// The connected displays, main first, or only the main one.
    func displays(_ scope: DisplayScope) -> [DisplayEntity] {
        model.refresh()
        let all = ShortcutCatalog.displays(model.displays)
        switch scope {
        case .all:
            return all
        case .main:
            guard let main = model.mainDisplay else { return [] }
            return [ShortcutCatalog.entity(for: main, among: model.displays)]
        }
    }

    /// Opens the Resolute window on the main display's page.
    func openWindow() throws {
        try ensureIdle()
        model.openWindow(model.defaultRoute)
    }

    // MARK: - Helpers

    /// Refuses while a Keep/Revert countdown is up: the coordinator would turn the switch
    /// away, and an agent's question is about a display the switch may change.
    private func ensureIdle() throws {
        if model.modeChanges.isChangingMode || model.agentRequests?.isAsking == true {
            throw ShortcutError.busy
        }
    }

    private func connected(_ id: String, name: String) throws -> Display {
        guard let display = ShortcutCatalog.display(for: id, in: model.displays) else {
            throw ShortcutError.notConnected(display: name)
        }
        return display
    }

    private func switchListed(_ mode: DisplayMode, of display: Display) throws {
        do {
            guard try model.applyListedMode(mode.modeID, to: display.id, from: .shortcuts) != nil else {
                throw ShortcutError.busy
            }
        } catch {
            throw ShortcutError(error)
        }
    }

    private func entity(for display: Display) throws -> DisplayEntity {
        guard let now = model.displays.first(where: { $0.id == display.id }) else {
            throw ShortcutError.notConnected(display: display.name)
        }
        return ShortcutCatalog.entity(for: now, among: model.displays)
    }
}
