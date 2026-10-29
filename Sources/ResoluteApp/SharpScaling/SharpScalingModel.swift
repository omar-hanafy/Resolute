import CoreGraphics
import Foundation
import Observation
import ResoluteDesign
import ResoluteKit

/// Sharp Scaling in the app: which displays can have it, its state on each, setting it up
/// and taking it out, and the switch to a sharp size once a display reconnects with it.
/// The app model owns one and tells it when the displays change.
///
/// Each display's state comes from its installed override, where Sharp Scaling keeps its
/// record (`SharpScalingRecord`), and from the modes macOS lists for it, read again whenever
/// the displays change. Changes go through `SharpScalingWriter`, which asks for an
/// administrator password; switching goes through the app model.
@MainActor
@Observable
final class SharpScalingModel {
    /// The app model, for the displays and for switching through its coordinator.
    @ObservationIgnored weak var app: AppModel?

    /// Each connected display's Sharp Scaling, by display.
    private(set) var states: [CGDirectDisplayID: DisplayState] = [:]
    /// The last switch Sharp Scaling made, for the panel (60:873); nil once the display
    /// moves to another mode or goes away.
    private(set) var activity: Activity?
    /// The display whose page should show the setup sheet: set by Set Up Sharp Scaling…,
    /// cleared when the sheet closes.
    var setupRequest: CGDirectDisplayID?
    /// The display whose override is being written; one change at a time.
    private(set) var working: CGDirectDisplayID?
    /// Displays whose sizes were removed while in use, with when: they stay until macOS
    /// reads the file again.
    private(set) var removedAwaitingReconnect: [OverrideKey: Date] = [:]
    /// Displays whose sizes became ready while Resolute watched, so their page says so.
    private(set) var newlyReady: Set<OverrideKey> = []

    /// Writes and removes override files. The app's asks for an administrator password;
    /// tests and the gallery write into a staged folder.
    @ObservationIgnored var installer: OverrideInstaller
    /// Whether the window's editors are writing an override, set by the shell: one
    /// administrator prompt at a time.
    @ObservationIgnored var isEditorWriting: @MainActor () -> Bool = { false }
    /// Set while the switch to sharp sizes waits for a switch under way to end.
    @ObservationIgnored private var isSwitchWaiting = false
    @ObservationIgnored let store: OverrideStore
    /// When this Mac started: every display has read its override file since.
    @ObservationIgnored var systemStart: Date? = SharpScalingStatus.systemStart()
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored let switchLog: SharpScalingSwitchLog
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let showError: @MainActor (any Error, String) -> Void
    @ObservationIgnored private var limit: DrawingLimit?
    /// The displays connected at the last change, by override file; nil before the first.
    @ObservationIgnored private var connected: Set<OverrideKey>?
    /// When each display last connected while Resolute was running.
    @ObservationIgnored private var connectedAt: [OverrideKey: Date] = [:]
    /// Each display's state at the last read, kept while it is away, so its page can say
    /// when it became ready.
    @ObservationIgnored private var lastStages: [OverrideKey: SharpScalingStatus.State?] = [:]

    init(environment: AppEnvironment) {
        store = environment.overrides
        preferences = environment.preferences
        showError = environment.showError
        let isLive = environment.overrides.locations == .standard
        installer = isLive
            ? .privileged
            : OverrideInstaller(locations: environment.overrides.locations, runner: ShellCommandRunner())
        switchLog = SharpScalingSwitchLog(defaults: isLive ? .standard : nil)
    }

    /// The largest drawing this Mac makes for an external display, read once.
    var drawingLimit: DrawingLimit {
        get {
            if let limit { return limit }
            let read = DrawingLimit.current()
            limit = read
            return read
        }
        set { limit = newValue }
    }

    // MARK: - Displays

    /// The displays were read again: a display came, went or changed mode.
    func displaysDidChange(_ displays: [Display]) {
        let keys = Set(displays.map { OverrideKey(display: $0) })
        if let connected {
            let date = now()
            for key in keys.subtracting(connected) { connectedAt[key] = date }
        }
        connected = keys
        for (key, removed) in removedAwaitingReconnect where (connectedAt[key] ?? .distantPast) >= removed {
            removedAwaitingReconnect[key] = nil
        }
        reload(displays)
        switchToSharpSizes(on: displays)
    }

    /// Reads every display's override again; `displays` defaults to the app model's.
    func reload(_ displays: [Display]? = nil) {
        let displays = displays ?? app?.displays ?? []
        var fresh: [CGDirectDisplayID: DisplayState] = [:]
        for display in displays { fresh[display.id] = readState(of: display) }
        for state in fresh.values {
            if state.stage == .ready || state.stage == .partial, lastStages[state.key] == .waiting {
                newlyReady.insert(state.key)
            }
            lastStages[state.key] = state.stage
        }
        if fresh != states { states = fresh }
        if let activity, displays.first(where: { $0.id == activity.displayID })?.currentModeID != activity.modeID {
            self.activity = nil
        }
    }

    private func readState(of display: Display) -> DisplayState {
        let key = OverrideKey(display: display)
        var state = DisplayState(key: key, name: display.name)
        guard !display.isBuiltin else {
            state.unavailability = .builtIn
            return state
        }
        do {
            let installed = try store.installedOverride(for: key)
            let record = try installed.flatMap { try SharpScalingRecord(in: $0) }
            state.unavailability = SharpScalingPlan.unavailability(for: display, installed: installed)
            state.native = SharpScalingPlan.nativeSize(of: display, record: record)
            state.status = try SharpScalingStatus(
                display: display,
                installed: installed,
                reconnectedSinceSave: record.map { hasReconnected(key, since: $0.saved) } ?? false,
                systemStart: systemStart
            )
            if let installed, record != nil, case .strip? = try? SharpScalingRemoval.plan(for: installed, in: store) {
                state.restoresFileFromBefore = false
            }
        } catch {
            state.readFailure = error.localizedDescription
        }
        return state
    }

    /// Whether `key`'s display connected after `date` while Resolute was running.
    private func hasReconnected(_ key: OverrideKey, since date: Date) -> Bool {
        connectedAt[key].map { $0 > date } ?? false
    }

    // MARK: - What the panel and the page show

    /// The offer on a standard display's panel card (Figma 60:547), or nil when there is none
    /// to make: the display can't have Sharp Scaling, has it, or the person closed the offer.
    func offer(for display: Display) -> Offer? {
        guard case .off(let plan)? = stage(for: display),
              !preferences.dismissedSharpScalingOffers.contains(OverrideKey(display: display).relativePath)
        else { return nil }
        return SharpScalingText.offer(native: plan.native)
    }

    /// The offer's ×: not offered again for this display.
    func dismissOffer(for display: Display) {
        preferences.dismissedSharpScalingOffers.insert(OverrideKey(display: display).relativePath)
    }

    /// Set Up Sharp Scaling…: the display's page, with the setup sheet open.
    func startSetup(for display: Display) {
        // The window doesn't open over a countdown, and a request left behind would open the
        // sheet unasked on a later visit.
        guard let app, !app.modeChanges.isChangingMode else { return }
        setupRequest = display.id
        app.openWindow(.display(.id(display.id), tab: .resolution))
    }

    /// Whether `display` is in one of the sharp sizes Sharp Scaling added (the panel card's
    /// Sharp badge, Figma 60:873).
    func isSharp(_ display: Display) -> Bool {
        guard let status = states[display.id]?.status, status.state != .off,
              let current = display.currentMode, current.isHiDPI
        else { return false }
        return status.saved.contains(SharpSize(current))
    }

    /// Where `display` stands, for its page; nil when the page has nothing to say about Sharp
    /// Scaling: a Retina display, one with HiDPI sizes of its own, or one whose override
    /// can't be read.
    func stage(for display: Display) -> Stage? {
        guard let state = states[display.id], state.readFailure == nil else { return nil }
        if let status = state.status, status.state != .off {
            switch status.state {
            case .waiting: return .waiting(status)
            case .ready: return .ready(status)
            case .partial: return .partial(status)
            case .off: break
            }
        }
        guard state.unavailability == nil, removedAwaitingReconnect[state.key] == nil,
              let native = state.native
        else { return nil }
        let plan = SharpScalingPlan(native: native, limit: drawingLimit)
        return plan.sizes.isEmpty ? nil : .off(plan)
    }

    /// Where the page puts the Sharp Scaling section: its own section above the
    /// Resolution group before the sizes are in use (62:1020, 67:1585), a row of the group
    /// under the sizes once they are (67:2175). Nil when there is none.
    func placement(for display: Display) -> Placement? {
        switch stage(for: display) {
        case .off?, .waiting?: .section
        case .ready?, .partial?: .row
        case nil: nil
        }
    }

    /// The badge the display's page header adds: "Sharp Scaling saved" (67:1585), "Sharp
    /// Scaling" (67:2175).
    func headerBadge(for display: Display) -> String? {
        switch stage(for: display) {
        case .waiting?: "Sharp Scaling saved"
        case .ready?, .partial?: "Sharp Scaling"
        case .off?, nil: nil
        }
    }

    /// The banner above the page's tabs, if any.
    func banner(for display: Display) -> PageBanner? {
        let name = display.name
        if let key = states[display.id]?.key, removedAwaitingReconnect[key] != nil {
            return PageBanner(text: SharpScalingText.removedBanner(display: name), tone: .info, action: nil)
        }
        switch stage(for: display) {
        case .waiting(let status)?:
            return PageBanner(text: SharpScalingText.waitingBanner(display: name, sizes: status.saved.count), tone: .info, action: nil)
        case .ready(let status)?:
            guard let key = states[display.id]?.key, newlyReady.contains(key) else { return nil }
            let text = SharpScalingText.readyBanner(display: name, status: status)
            return PageBanner(text: text, tone: .info, action: text.actionTitle == nil ? nil : .useSharpVersion)
        case .partial(let status)?:
            return PageBanner(
                text: SharpScalingText.partialBanner(status: status),
                tone: .warning,
                action: status.available.isEmpty ? .remove : .removeSkippedSizes
            )
        case .off?, nil:
            return nil
        }
    }

    /// The plan for `display`'s setup sheet; nil when it can't have Sharp Scaling now.
    func plan(for display: Display) -> SharpScalingPlan? {
        guard case .off(let plan)? = stage(for: display) else { return nil }
        return plan
    }

    func isWorking(on display: Display) -> Bool {
        working == display.id
    }

    // MARK: - Changes

    /// Add N Sizes…: writes `sizes` into `display`'s override, to switch to `switchTo` once
    /// macOS offers it. Returns whether they were written; a cancelled password prompt or a
    /// failure, which is shown, leaves the sheet up.
    @discardableResult
    func turnOn(for display: Display, sizes: [SharpSize], switchTo: SharpSize?) async -> Bool {
        let written = await write(on: display, failureTitle: "Sharp Scaling could not be set up") { writer in
            try await writer.turnOn(for: display, sizes: sizes, switchTo: switchTo)
        }
        if written {
            if setupRequest == display.id { setupRequest = nil }
            afterChange()
        }
        return written
    }

    /// Undo Setup… and Remove…: puts back the file from before Sharp Scaling, or takes out
    /// its sizes when the file changed since.
    @discardableResult
    func turnOff(for display: Display) async -> Bool {
        let key = OverrideKey(display: display)
        let wasInUse: Bool
        switch stage(for: display) {
        case .ready?, .partial?: wasInUse = true
        case .off?, .waiting?, nil: wasInUse = false
        }
        let removed = await write(on: display, failureTitle: "Sharp Scaling could not be removed") { writer in
            _ = try await writer.turnOff(for: key)
        }
        if removed {
            if wasInUse { removedAwaitingReconnect[key] = now() }
            newlyReady.remove(key)
            afterChange()
        }
        return removed
    }

    /// Remove Skipped Size: saves only the sizes macOS offers, so the list matches them.
    @discardableResult
    func removeSkippedSizes(on display: Display) async -> Bool {
        guard case .partial(let status)? = stage(for: display), let record = status.record, !status.available.isEmpty else {
            return false
        }
        let key = OverrideKey(display: display)
        let written = await write(on: display, failureTitle: "The skipped sizes could not be removed") { writer in
            try await writer.turnOn(for: display, sizes: status.available, switchTo: record.switchTo)
        }
        guard written else { return false }
        reload()
        // The setup is saved anew. A switch already made for it isn't made again.
        if switchLog.hasSwitched(key, saved: record.saved), let saved = states[display.id]?.status?.record?.saved {
            switchLog.markSwitched(key, saved: saved)
        }
        if let app { switchToSharpSizes(on: app.displays) }
        return true
    }

    /// The ready banner's link: the sharp version of the size the display has.
    func useSharpVersion(on display: Display) {
        guard let mode = states[display.id]?.status?.sharpVersionOfCurrent, mode.modeID != display.currentModeID else { return }
        app?.apply(mode, to: display, from: .window)
        reload()
    }

    /// The activity's Undo: back to the mode the display had before the switch.
    func undoActivity() {
        guard let activity, let app,
              let display = app.displays.first(where: { $0.id == activity.displayID }),
              let previous = display.modes.first(where: { $0.modeID == activity.previousModeID })
        else {
            self.activity = nil
            return
        }
        self.activity = nil
        app.apply(previous, to: display, from: .panel)
        reload()
    }

    /// Runs one change through the writer, off the main thread, with `working` set; none
    /// while another change or a save in the window is being written, which is said, as the
    /// window's editors say it. The password prompt's Cancel is no error; the file changing
    /// under the change and another command holding the overrides are said in words the
    /// person can act on.
    private func write(
        on display: Display, failureTitle: String, _ change: @escaping @Sendable (SharpScalingWriter) async throws -> Void
    ) async -> Bool {
        guard working == nil, !isEditorWriting() else {
            showError(Failure("Another override is being written. Try again once it has finished."), failureTitle)
            return false
        }
        working = display.id
        defer { working = nil }
        let writer = SharpScalingWriter(store: store, installer: installer)
        do {
            try await change(writer)
            return true
        } catch ResoluteError.cancelled {
            return false
        } catch ResoluteError.overrideChanged {
            showError(Failure(
                "The override file for \(display.name) changed while Resolute was writing it, by another app or the resolute command. Nothing was written. Try again."
            ), failureTitle)
        } catch ResoluteError.overridesBusy {
            showError(Failure(
                "Another Resolute command is editing overrides, and has been for too long. Try again when it has finished."
            ), failureTitle)
        } catch {
            showError(error, failureTitle)
        }
        return false
    }

    private func afterChange() {
        reload()
        if let app { switchToSharpSizes(on: app.displays) }
    }

    /// The switch setup asked for, made once per saved setup when the display offers the
    /// sizes: to the sharp version of the size it had, keeping its refresh rate. When macOS
    /// skipped that size, the nearest one it offers.
    private func switchToSharpSizes(on displays: [Display]) {
        guard let app else { return }
        // The coordinator turns switches away while a countdown is up, so this one waits for
        // the switch under way to end and then looks at the displays as they are.
        guard !app.modeChanges.isChangingMode else {
            guard !isSwitchWaiting else { return }
            isSwitchWaiting = true
            app.modeChanges.afterSwitch { [weak self] in
                guard let self, let app = self.app else { return }
                isSwitchWaiting = false
                reload(app.displays)
                switchToSharpSizes(on: app.displays)
            }
            return
        }
        var switched = false
        for display in displays {
            guard let status = states[display.id]?.status, status.state == .ready || status.state == .partial,
                  let record = status.record, let wanted = record.switchTo
            else { continue }
            let key = OverrideKey(display: display)
            guard !switchLog.hasSwitched(key, saved: record.saved) else { continue }
            switchLog.markSwitched(key, saved: record.saved)
            let size = status.available.contains(wanted)
                ? wanted
                : SharpScalingPlan.switchTarget(from: display.currentMode, among: status.available, native: nil)
            guard let size, let mode = SharpScalingStatus.sharpMode(for: size, on: display, keeping: display.currentMode),
                  mode.modeID != display.currentModeID
            else { continue }
            let previous = display.currentModeID
            app.apply(mode, to: display, from: .panel)
            switched = true
            newlyReady.insert(key)
            if let previous, app.displays.first(where: { $0.id == display.id })?.currentModeID == mode.modeID {
                activity = Activity(
                    displayID: display.id, displayName: display.name, size: size,
                    modeID: mode.modeID, previousModeID: previous, date: now()
                )
            }
        }
        if switched { reload(app.displays) }
    }

    // MARK: - Types

    /// The words of the offer.
    struct Offer: Equatable {
        var title: String
        var message: String
        var actionTitle: String
    }

    /// One display's Sharp Scaling, as last read.
    struct DisplayState: Equatable {
        var key: OverrideKey
        var name: String
        /// Why the display can't have Sharp Scaling; nil when it can.
        var unavailability: SharpScalingPlan.Unavailable?
        /// The panel's own resolution; nil when unknown.
        var native: SharpSize?
        var status: SharpScalingStatus?
        /// False when turning Sharp Scaling off keeps the rest of a file changed since.
        var restoresFileFromBefore = true
        /// Why the override couldn't be read.
        var readFailure: String?

        var stage: SharpScalingStatus.State? { status?.state }
    }

    /// Where a display stands, for its page.
    enum Stage: Equatable {
        /// Not set up; the plan setup offers.
        case off(SharpScalingPlan)
        /// Saved, waiting for the display to read the file (67:1585).
        case waiting(SharpScalingStatus)
        /// macOS offers every saved size (67:2175).
        case ready(SharpScalingStatus)
        /// macOS skipped some after reading the file (68:2089).
        case partial(SharpScalingStatus)
    }

    enum Placement: Equatable {
        case section
        case row
    }

    /// A banner above the display page's tabs.
    struct PageBanner: Equatable {
        enum Action: Equatable {
            case useSharpVersion
            case removeSkippedSizes
            case remove
        }

        var text: SharpScalingText.BannerText
        var tone: Banner.Tone
        var action: Action?
    }

    /// A switch Sharp Scaling made, for the panel's activity row (60:873).
    struct Activity: Equatable {
        var displayID: CGDirectDisplayID
        var displayName: String
        var size: SharpSize
        /// The sharp mode switched to.
        var modeID: Int32
        /// The mode before, which Undo puts back.
        var previousModeID: Int32
        var date: Date

        var symbol: Symbol { .sparkles }
        /// "ASUS PA278QV → 2560 × 1440 sharp".
        var title: String { SharpScalingText.activityTitle(display: displayName, size: size) }

        /// "Sharp Scaling is ready · just now".
        func detail(now: Date = Date()) -> String {
            SharpScalingText.activityDetail(since: date, now: now)
        }
    }

    /// A failure said in Resolute's words.
    struct Failure: LocalizedError {
        var message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }
}
