import AppKit
import Observation
import ResoluteKit

/// The app's state and actions: the displays, switching modes, mirroring, Launch at Login and
/// the preferences. The panel, the window and the menus read it and call its methods; none of
/// them talks to the displays itself, so every switch goes through one coordinator and is
/// guarded the same way.
///
/// Built from an `AppEnvironment`, so tests and the gallery run it on fakes. Windows, the
/// panel and quitting go through `shell`.
@MainActor
@Observable
final class AppModel {
    /// A display that can have an override: a connected one, or one that is not connected
    /// but has an override file, which the window lists under Not Connected.
    struct OverrideTarget: Identifiable, Hashable, Sendable {
        var key: OverrideKey
        var name: String
        /// The connected display it stands for; nil when it is not connected.
        var displayID: CGDirectDisplayID?
        var hasOverride: Bool

        var id: OverrideKey { key }
        var isConnected: Bool { displayID != nil }
    }

    /// The connected displays: the main one first, then the built-in one, then by ID, the
    /// order of the panel's cards and the window's sidebar. Read again when the screens
    /// change and after every switch.
    private(set) var displays: [Display] = []
    /// Every display read since launch, as last read: a revert can be set up for one that has
    /// gone dark, which a killed command's trial leaves to the app. One per display ID and
    /// hardware, since another display can take the ID of one that is away.
    @ObservationIgnored private(set) var lastSeenDisplays: [Display] = []
    /// One per override key: the connected displays, then the displays that are not
    /// connected but have an override file.
    private(set) var overrideTargets: [OverrideTarget] = []
    private(set) var launchAtLogin: LaunchAtLoginState
    let launchKind: LaunchKind
    let preferences: Preferences
    /// Every switch goes through it. Observable: `pendingRestores` and `isChangingMode`.
    let modeChanges: ModeChangeCoordinator
    /// The Keep/Revert question while a hidden mode is on trial, with its countdown.
    let trial: TrialPrompt
    /// Sharp Scaling on the displays that can have it.
    let sharpScaling: SharpScalingModel
    /// The presets, as the presets file holds them. Read again on `refresh()` and after
    /// every change, since `resolute preset` writes the same file.
    private(set) var presetLibrary = PresetLibrary()
    /// The changes History keeps, newest first, from the app and the command line alike.
    private(set) var historyEntries: [HistoryEntry] = []
    /// Presets, History and the socket `resolute` asks through.
    let support: SupportLocations
    @ObservationIgnored let presetStore: PresetStore
    @ObservationIgnored let historyStore: HistoryStore
    /// Trials whose revert waits for the display to come back, by display, oldest first, so
    /// History can record how each ended. A trial started while an earlier one waits is
    /// undone by the same revert.
    @ObservationIgnored var trialsAwaitingRestore: [CGDirectDisplayID: [AwaitedTrial]] = [:]
    /// The picture each connected display's override file sets (a skin, "custom", or
    /// "display" for none), by override key. Read with the override targets.
    private(set) var overridePictures: [OverrideKey: String] = [:]
    /// The panel's page: nil for the cards, or the display whose All Resolutions is open.
    var panelAllResolutions: CGDirectDisplayID?
    /// Whether ⌥ was down when the panel opened: All Resolutions then also shows mode
    /// numbers and pixel sizes.
    private(set) var panelShowsDetails = false
    /// Each display's details, read once per display until the displays change.
    @ObservationIgnored var detailsByDisplay: [CGDirectDisplayID: DisplayDetails] = [:]
    @ObservationIgnored let readDetails: @MainActor (Display) -> DisplayDetails

    /// The windows, the panel and quitting. Set by the app delegate's shell controller.
    @ObservationIgnored weak var shell: (any AppShell)?
    /// Requests from `resolute` to keep a hidden mode. While its dialog is up, no trial of
    /// the app's own may start: two Keep/Revert questions at once would each hold the other.
    @ObservationIgnored weak var agentRequests: AgentRequests?
    /// The displays, for models that read them themselves, such as the Custom Resolutions
    /// editor's. Switching goes through `apply`, never straight to the service.
    let service: any DisplayControlling

    private let loginItem: any LoginItemToggling
    private let overrides: OverrideStore
    let showError: @MainActor (any Error, String) -> Void
    private let showTrialOutcome: @MainActor (TrialOutcome, TrialQuestion) -> Void
    @ObservationIgnored private var screenChanges: NotificationToken?

    init(environment: AppEnvironment) {
        let preferences = environment.preferences
        let present = environment.showError
        // The trial length is read at each trial, so a change in Settings applies to the next.
        let trial = TrialPrompt(length: { preferences.trialLength.duration }, ask: environment.askToKeep)
        // The coordinator reports only once its switch is over.
        let modeChanges = ModeChangeCoordinator(
            service: environment.service,
            decide: { trial.decide() },
            report: { present($0, "The display mode could not be changed") }
        )
        // An alert over the Keep/Revert dialog would hold up its revert until closed, so one
        // asked for while a switch is under way opens once the switch is over.
        let showError: @MainActor (any Error, String) -> Void = { error, title in
            modeChanges.afterSwitch { present(error, title) }
        }
        var environment = environment
        environment.showError = showError
        self.preferences = preferences
        self.showError = showError
        showTrialOutcome = environment.showTrialOutcome
        self.trial = trial
        self.modeChanges = modeChanges
        support = environment.support
        readDetails = environment.displayDetails
        presetStore = PresetStore(locations: environment.support)
        historyStore = HistoryStore(locations: environment.support)
        sharpScaling = SharpScalingModel(environment: environment)
        service = environment.service
        loginItem = environment.loginItem
        overrides = environment.overrides
        launchKind = environment.launchKind
        launchAtLogin = environment.loginItem.state
        refresh()
        screenChanges = NotificationToken(
            center: environment.notificationCenter, name: NSApplication.didChangeScreenParametersNotification
        ) { [weak self] in
            self?.displaysDidChange()
        }
        modeChanges.onWaitEnded = { [weak self] restore, ending in
            self?.trialWaitEnded(restore, ending)
        }
        sharpScaling.app = self
        sharpScaling.displaysDidChange(displays)
    }

    // MARK: - Reading

    /// Reads the displays, the override files, Launch at Login, the presets and History
    /// again. Called when the panel or the window opens, so they never show a stale mode;
    /// values that did not change are left alone, so nothing observing them redraws.
    func refresh() {
        let fresh = Self.ordered(service.displays())
        for display in fresh {
            let identity = ModeSwitcher.DisplayIdentity(display)
            lastSeenDisplays.removeAll { $0.id == display.id && ModeSwitcher.DisplayIdentity($0) == identity }
            lastSeenDisplays.append(display)
        }
        if fresh != displays {
            displays = fresh
            // A display's ID can name another display after a reconnect.
            detailsByDisplay = [:]
        }
        let targets = Self.overrideTargets(displays: fresh, store: overrides)
        if targets != overrideTargets { overrideTargets = targets }
        let pictures = Self.pictures(of: targets, store: overrides)
        if pictures != overridePictures { overridePictures = pictures }
        let state = loginItem.state
        if state != launchAtLogin { launchAtLogin = state }
        reloadPresets()
        reloadHistory()
    }

    /// Reads the presets file again; the command line changes it too. A file that can't be
    /// read is logged, and the presets stay as they were.
    func reloadPresets() {
        do {
            try loadPresets()
        } catch {
            ResoluteLog.presets.error("Could not read presets: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads the presets file again, throwing when it can't be read.
    func loadPresets() throws {
        let library = try presetStore.load()
        if library != presetLibrary { presetLibrary = library }
    }

    /// Reads History again; the command line adds to it too.
    func reloadHistory() {
        let entries: [HistoryEntry]
        do {
            entries = try historyStore.entries()
        } catch {
            ResoluteLog.history.error("Could not read history: \(error.localizedDescription, privacy: .public)")
            return
        }
        if entries != historyEntries { historyEntries = entries }
    }

    /// The screens changed: a display came, went, or changed mode outside Resolute.
    func displaysDidChange() {
        // A display that reconnects may have a revert waiting for it.
        modeChanges.displaysDidChange()
        refresh()
        sharpScaling.displaysDidChange(displays)
    }

    /// The display a page or a menu item names, while it is connected. An override key names
    /// a connected display only when exactly one has it: identical monitors share a key.
    func display(for target: DisplayTarget) -> Display? {
        switch target {
        case .id(let id):
            return displays.first { $0.id == id }
        case .overrideKey(let key):
            let matches = displays.filter { OverrideKey(display: $0) == key }
            return matches.count == 1 ? matches[0] : nil
        }
    }

    /// The display with the menu bar, else the first one.
    var mainDisplay: Display? {
        displays.first(where: \.isMain) ?? displays.first
    }

    /// Displays that are not connected but have an override file (the window's Not Connected).
    var notConnectedTargets: [OverrideTarget] {
        overrideTargets.filter { !$0.isConnected }
    }

    /// Whether any display mirrors another.
    var isMirroring: Bool {
        displays.contains(where: \.isInMirrorSet)
    }

    /// Mirror Displays needs two displays.
    var canMirror: Bool {
        displays.count > 1
    }

    /// Reverts waiting for their display to come back (the waiting state of the panel and
    /// the menu bar icon).
    var pendingRestores: [ModeSwitcher.PendingRestore] {
        modeChanges.pendingRestores
    }

    /// "1728 × 1117 · 120 Hz": a display's current mode, as the window's toolbar and the
    /// panel's cards say it. Nil when the mode is not known.
    static func modeSummary(of display: Display) -> String? {
        guard let mode = display.currentMode else { return nil }
        let rate = RefreshRate.format(mode.refreshRate)
        return rate.isEmpty ? mode.sizeText : "\(mode.sizeText) · \(rate)"
    }

    /// The main display's resolution, shown next to the menu bar icon when Settings › Show
    /// the resolution next to the icon is on.
    var menuBarResolutionText: String? {
        mainDisplay?.currentMode?.sizeText
    }

    /// The page the window opens on when nothing asked for one: the main display.
    var defaultRoute: AppRoute {
        mainDisplay.map { AppRoute.display(.id($0.id)) } ?? .settings()
    }

    /// The toolbar's title and subtitle for `route`.
    func windowTitle(for route: AppRoute) -> WindowTitle {
        switch route {
        case .display(let reference, _):
            if let display = display(for: reference) {
                var subtitle = Self.modeSummary(of: display) ?? ""
                if sharpScaling.isSharp(display), !subtitle.isEmpty { subtitle += " · Sharp" }
                return WindowTitle(title: display.name, subtitle: subtitle)
            }
            let name: String
            switch reference {
            case .overrideKey(let key):
                name = DisplayPagePresentation.notConnectedName(
                    for: key, listed: overrideTargets.first { $0.key == key }?.name, history: historyEntries
                )
            case .id:
                name = "Display"
            }
            return WindowTitle(title: name, subtitle: "Not connected")
        case .presets:
            return WindowTitle(title: "Presets", subtitle: "")
        case .history:
            return WindowTitle(title: "History", subtitle: "")
        case .settings:
            return WindowTitle(title: "Settings", subtitle: "")
        }
    }

    // MARK: - Mode changes

    /// Switches `display` to `mode`, asked for from `source`. A hidden mode is tried first
    /// and kept only when the person keeps it before the countdown ends. History records how
    /// the switch ended.
    func apply(_ mode: DisplayMode, to display: Display, from source: HistoryEntry.Source = .panel) {
        apply(modeID: mode.modeID, to: display.id, needsConfirmation: mode.origin == .hidden, from: source, chosenFor: display)
    }

    /// `chosenFor` is the display as the menu or panel showed it, when known: another display
    /// that took its ID since, after a reconnect, is left alone.
    func apply(
        modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool, from source: HistoryEntry.Source = .panel,
        chosenFor shown: Display? = nil
    ) {
        guard !isTrialHeldByAgentRequest(needsConfirmation) else { return }
        // As it is now, before the switch, which is how History records a change: a menu
        // reads the displays when it opens, and the display behind the ID may have changed since.
        let current = service.displays().first { $0.id == displayID }
        if let shown, let current, ModeSwitcher.DisplayIdentity(current) != ModeSwitcher.DisplayIdentity(shown) {
            ResoluteLog.modes.notice("""
                Ignored mode \(modeID) chosen for \(shown.name, privacy: .public): \
                \(current.name, privacy: .public) has its display ID now
                """)
            refresh()
            return
        }
        guard let before = current, let mode = before.modes.first(where: { $0.modeID == modeID }) else {
            modeChanges.apply(modeID: modeID, to: displayID, needsConfirmation: needsConfirmation)
            refresh()
            return
        }
        // A hidden mode is tried whatever the menu said.
        let needsConfirmation = needsConfirmation || mode.origin == .hidden
        if let result = switchMode(of: before, to: mode, needsConfirmation: needsConfirmation) {
            record(result, switching: before, to: mode, from: source)
        }
        refresh()
    }

    /// Switches through the coordinator, naming the display and mode for the trial's
    /// question first, and says on the display how a trial ended. Returns how the switch
    /// ended, or nil when it was not tried because a countdown was up.
    func switchMode(of display: Display, to mode: DisplayMode, needsConfirmation: Bool) -> Result<ModeSwitcher.Outcome, any Error>? {
        guard !isTrialHeldByAgentRequest(needsConfirmation) else { return nil }
        trial.subject = TrialPrompt.Subject(display: display, mode: mode)
        defer { trial.subject = nil }
        let result = modeChanges.apply(modeID: mode.modeID, to: display.id, needsConfirmation: needsConfirmation)
        if needsConfirmation, case .success(let outcome)? = result, let question = trial.lastQuestion, question.displayID == display.id {
            switch outcome {
            case .reverted: showTrialOutcome(.switchedBack, question)
            case .kept, .keptForSession: showTrialOutcome(.kept, question)
            case .applied, .alreadyCurrent, .leftAlone, .restorePending: break
            }
        }
        return result
    }

    /// Switches `displayID` to `rate` at its current resolution, through the mode
    /// `ModeCatalog.refreshOptions` picks for that rate, among listed modes only unless
    /// `includeHidden`. Nothing happens when the display does not offer the rate there or
    /// already uses it.
    func setRefreshRate(
        _ rate: Double, on displayID: CGDirectDisplayID, from source: HistoryEntry.Source = .panel, includeHidden: Bool = true
    ) {
        guard let display = displays.first(where: { $0.id == displayID }),
              let option = ModeCatalog.refreshOptions(for: display, includeHidden: includeHidden)
                .first(where: { RefreshRate.key($0.refreshRate) == RefreshRate.key(rate) }),
              !option.isCurrent
        else { return }
        apply(option.mode, to: display, from: source)
    }

    /// Whether a trial must wait because `resolute` is asking the person about one already.
    private func isTrialHeldByAgentRequest(_ needsConfirmation: Bool) -> Bool {
        guard needsConfirmation, agentRequests?.isAsking == true else { return false }
        ResoluteLog.modes.notice("Ignored a hidden mode chosen while a request from resolute was being answered")
        return true
    }

    /// Stops waiting to put back the previous mode of `displayID` (Stop Waiting).
    func stopWaiting(for displayID: CGDirectDisplayID) {
        modeChanges.stopWaiting(for: displayID)
    }

    /// Mirrors every display to the main one, or stops mirroring.
    func setMirroring(_ enabled: Bool, from source: HistoryEntry.Source = .panel) {
        // Mirroring changes the displays a trial must put back.
        guard !modeChanges.isChangingMode else { return }
        let before = displays
        do {
            try service.setMirroring(enabled)
            if enabled != before.contains(where: \.isInMirrorSet) {
                history(from: source).recordMirroring(enabled, displays: before)
            }
        } catch {
            history(from: source).recordMirroring(enabled, displays: before, failedWith: error)
            showError(error, "Mirroring could not be changed")
        }
        refresh()
    }

    func toggleMirroring(from source: HistoryEntry.Source = .panel) {
        setMirroring(!isMirroring, from: source)
    }

    // MARK: - Launch at Login

    /// Turns Launch at Login on or off; macOS may ask for approval in System Settings.
    func toggleLaunchAtLogin() {
        // A failure shows an alert, which would hold up a countdown's revert.
        guard !modeChanges.isChangingMode else { return }
        loginItem.toggle()
        let state = loginItem.state
        if state != launchAtLogin { launchAtLogin = state }
    }

    // MARK: - Windows, panel and quitting

    /// Shows the window on `route`. Not while a countdown is up: a page's sheet or alert
    /// would hold up its revert.
    func openWindow(_ route: AppRoute) {
        guard !modeChanges.isChangingMode else { return }
        shell?.showWindow(route)
    }

    /// Settings… (⌘,) and About Resolute.
    func openSettings(_ tab: SettingsTab = .general) {
        openWindow(.settings(tab))
    }

    /// Custom Resolutions…: the display's Custom Resolutions tab, the main display's when no
    /// display is named, or a display that is not connected when none is.
    func openCustomResolutions(for displayID: CGDirectDisplayID?) {
        if let id = displayID ?? mainDisplay?.id {
            openWindow(.display(.id(id), tab: .customResolutions))
        } else if let key = overrideTargets.first?.key {
            openWindow(.display(.overrideKey(key), tab: .customResolutions))
        }
    }

    func openPanel() {
        shell?.showPanel()
    }

    /// The panel is about to open: it starts on the cards, read fresh.
    func panelWillOpen(showingDetails: Bool) {
        panelAllResolutions = nil
        if showingDetails != panelShowsDetails { panelShowsDetails = showingDetails }
        refresh()
    }

    func closePanel() {
        shell?.closePanel()
    }

    /// Quit Resolute: quits even with the window open, after the checks that keep a switch,
    /// a revert or unsaved custom resolutions from being lost.
    func quit() {
        shell?.quit()
    }

    // MARK: - Helpers

    /// Main display first, then built-in displays, then by ID, as the classic menu orders them.
    static func ordered(_ displays: [Display]) -> [Display] {
        displays.sorted { lhs, rhs in
            (lhs.isMain ? 0 : 1, lhs.isBuiltin ? 0 : 1, lhs.id) < (rhs.isMain ? 0 : 1, rhs.isBuiltin ? 0 : 1, rhs.id)
        }
    }

    /// Connected displays, one per override key, then installed overrides of displays that
    /// are not connected, named as their file names them.
    static func overrideTargets(displays: [Display], store: OverrideStore) -> [OverrideTarget] {
        let installed = store.installedKeys()
        let hasOverride = Set(installed)
        var seen = Set<OverrideKey>()
        var targets: [OverrideTarget] = []
        for display in displays {
            let key = OverrideKey(display: display)
            guard seen.insert(key).inserted else { continue }
            targets.append(OverrideTarget(
                key: key, name: display.name, displayID: display.id, hasOverride: hasOverride.contains(key)
            ))
        }
        for key in installed where seen.insert(key).inserted {
            let name = (try? store.installedOverride(for: key))?.productName ?? fallbackName(for: key)
            targets.append(OverrideTarget(key: key, name: name, displayID: nil, hasOverride: true))
        }
        return targets
    }

    /// The picture each connected display's installed override sets, by override key.
    static func pictures(of targets: [OverrideTarget], store: OverrideStore) -> [OverrideKey: String] {
        var pictures: [OverrideKey: String] = [:]
        for target in targets where target.isConnected && target.hasOverride {
            guard let override = try? store.installedOverride(for: target.key) else { continue }
            pictures[target.key] = DisplayIcons.skin(for: override.picture)
        }
        return pictures
    }

    /// "Display 10ac:a0c4": a display that is not connected and whose override has no name.
    static func fallbackName(for key: OverrideKey) -> String {
        "Display \(String(key.vendorID, radix: 16)):\(String(key.productID, radix: 16))"
    }
}
