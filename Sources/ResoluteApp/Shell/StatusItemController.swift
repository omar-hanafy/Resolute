import AppKit
import ResoluteDesign

/// What a click on the menu bar icon opens: the panel, or the classic menu for a right-click
/// or a Control-click. Only mouse clicks choose the menu: a shortcut that opens the panel may
/// well hold Control.
enum StatusItemClick: Equatable {
    case panel
    case classicMenu

    init(type: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) {
        switch type {
        case .rightMouseDown?, .rightMouseUp?:
            self = .classicMenu
        case .leftMouseDown?, .leftMouseUp?:
            self = modifierFlags.contains(.control) ? .classicMenu : .panel
        default:
            self = .panel
        }
    }

    init(event: NSEvent?) {
        self.init(type: event?.type, modifierFlags: event?.modifierFlags ?? [])
    }

    /// Whether the panel opens with each mode's details and the hidden modes: ⌥ held while
    /// clicking the icon. Only a mouse click counts, since the shortcut that opens the panel
    /// (⌃⌥R by default) may well hold ⌥ itself.
    static func showsDetails(type: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch type {
        case .leftMouseDown?, .leftMouseUp?: modifierFlags.contains(.option)
        default: false
        }
    }

    static func showsDetails(for event: NSEvent?) -> Bool {
        showsDetails(type: event?.type, modifierFlags: event?.modifierFlags ?? [])
    }
}

/// Resolute's menu bar icon. A click opens the panel; a right-click or Control-click opens the
/// classic menu, for keyboard and VoiceOver users. The icon follows the app: orange with a
/// countdown while a hidden mode is on trial, a waiting state while a revert waits for its
/// display, and the resolution next to it when Settings asks for it.
///
/// On macOS 27 the status item's expanded-interface delegate drives the panel, so it opens,
/// closes and takes the keyboard like a system menu; before, the icon's own click does.
@MainActor
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    let panel: PanelHost
    private(set) var state = StatusItemState.normal

    private let model: AppModel
    private let classicMenu: StatusMenuController
    private var appearance: ObservationLoop?
    private var countdownTimer: Timer?
    private var isShowingClassicMenu = false
    /// The click the classic menu last opened for, so a click that both fires the button
    /// and starts a macOS 27 session opens it once.
    private var lastMenuClick: TimeInterval?
    /// macOS 27's delegate and the session under way, kept loosely typed because older SDKs
    /// have neither.
    private var expandedInterface: AnyObject?
    private var expandedSession: AnyObject?

    init(model: AppModel, panel: PanelHost, classicMenu: StatusMenuController, statusBar: NSStatusBar = .system) {
        self.model = model
        self.panel = panel
        self.classicMenu = classicMenu
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "Resolute"
        installExpandedInterface()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            // With macOS 27's session, a left click is the session's to handle.
            button.sendAction(on: usesExpandedInterface ? [.rightMouseDown] : [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityHelp("Opens the Resolute panel. Control-click for the classic menu.")
            // VoiceOver has no right-click; its Actions menu offers the classic menu instead.
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Show Classic Menu") { [weak self] in
                    self?.showClassicMenu(forClickAt: nil)
                    return true
                },
            ])
        }
        panel.onVisibilityChange = { [weak self] _ in self?.update() }
        panel.onDismiss = { [weak self] in self?.endExpandedSession() }
        appearance = ObservationLoop { [weak self] in self?.update() }
    }

    /// The icon, for a popover that points at it, such as the first-close notice.
    var button: NSStatusBarButton? {
        statusItem.button
    }

    /// Opens the panel, as a click on the icon does: from a shortcut, or `AppModel.openPanel()`.
    func openPanel() {
        open(showingDetails: false)
    }

    private func open(showingDetails: Bool) {
        guard !panel.isOpen else { return }
        if usesExpandedInterface {
            // A click lets macOS 27 start a session, so the panel joins menu tracking.
            button?.performClick(nil)
            if panel.isOpen { return }
        }
        showPanel(showingDetails: showingDetails)
    }

    func closePanel() {
        guard panel.isOpen else { return }
        panel.close()
        endExpandedSession()
    }

    // MARK: - Clicks

    @objc private func buttonClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        switch StatusItemClick(event: event) {
        case .classicMenu:
            showClassicMenu(forClickAt: event?.timestamp)
        case .panel where !usesExpandedInterface || panel.isOpen:
            if panel.isOpen {
                closePanel()
            } else {
                open(showingDetails: StatusItemClick.showsDetails(for: event))
            }
        case .panel:
            // On macOS 27 a click is the session's, so this is a press from VoiceOver or a
            // shortcut, which may not start one: open the panel unless a session does.
            let showsDetails = StatusItemClick.showsDetails(for: event)
            MainRunLoop.perform { [weak self] in
                guard let self, !self.panel.isOpen else { return }
                self.showPanel(showingDetails: showsDetails)
            }
        }
    }

    private func showPanel(showingDetails: Bool) {
        // The Keep/Revert dialog must not end up under the panel.
        guard !model.modeChanges.isChangingMode else { return }
        model.panelWillOpen(showingDetails: showingDetails)
        panel.open { [weak self] in self?.anchor() }
    }

    /// The icon's frame on screen, which the panel hangs under.
    private func anchor() -> PanelHost.Anchor? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return PanelHost.Anchor(window: window, frame: frame, screen: window.screen)
    }

    /// Shows the classic menu under the icon, the way a status item shows its own menu: it
    /// is the item's menu only while it is open.
    private func showClassicMenu(forClickAt timestamp: TimeInterval?) {
        if let timestamp {
            guard timestamp != lastMenuClick else { return }
            lastMenuClick = timestamp
        }
        guard !isShowingClassicMenu, let button = statusItem.button else { return }
        closePanel()
        isShowingClassicMenu = true
        statusItem.menu = classicMenu.menu
        button.performClick(nil)
        statusItem.menu = nil
        isShowingClassicMenu = false
    }

    // MARK: - Appearance

    /// Draws the icon for what is going on, and keeps the countdown ticking during a trial.
    private func update() {
        let secondsLeft = model.trial.secondsLeft()
        let state = StatusItemState.resolve(
            trialSecondsLeft: secondsLeft,
            isWaiting: !model.modeChanges.pendingRestores.isEmpty,
            isPanelOpen: panel.isOpen,
            resolutionText: model.preferences.showsResolutionInMenuBar ? model.menuBarResolutionText : nil
        )
        render(state)
        if secondsLeft == nil {
            countdownTimer?.invalidate()
            countdownTimer = nil
        } else {
            startCountdown()
            // The Keep/Revert question must not open under the panel.
            if panel.isOpen { MainRunLoop.perform { [weak self] in self?.closePanel() } }
        }
    }

    private func render(_ state: StatusItemState) {
        guard let button = statusItem.button else { return }
        if state != self.state || button.image == nil {
            self.state = state
            // The image carries the design's padding, so the button adds none.
            let image = state.image(height: NSStatusBar.system.thickness)
            statusItem.length = image.size.width
            button.image = image.nsImage()
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = state.toolTip
            button.setAccessibilityLabel(state.accessibilityLabel)
        }
        // macOS 27 highlights the icon for its session; before, the open panel does.
        if !usesExpandedInterface { button.highlight(panel.isOpen) }
    }

    /// Redraws a few times a second while a trial is up, also while its alert runs modally.
    private func startCountdown() {
        guard countdownTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    // MARK: - macOS 27 expanded interface

    private var usesExpandedInterface: Bool {
        expandedInterface != nil
    }

    private func installExpandedInterface() {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            let delegate = ExpandedInterfaceDelegate(owner: self)
            statusItem.expandedInterfaceDelegate = delegate
            expandedInterface = delegate
        }
        #endif
    }

    /// macOS 27 began a session: a click on the icon, or the keyboard moving to it.
    fileprivate func expandedSessionDidBegin(_ session: AnyObject) {
        let event = NSApp.currentEvent
        if isShowingClassicMenu || StatusItemClick(event: event) == .classicMenu {
            cancel(session)
            // A Control-click fires no button action, so the menu opens from here.
            if !isShowingClassicMenu {
                let timestamp = event?.timestamp
                MainRunLoop.perform { [weak self] in self?.showClassicMenu(forClickAt: timestamp) }
            }
            return
        }
        expandedSession = session
        showPanel(showingDetails: StatusItemClick.showsDetails(for: event))
        if !panel.isOpen { endExpandedSession() }
    }

    /// The session ended: the person clicked elsewhere, chose another menu, or pressed Esc.
    fileprivate func expandedSessionDidEnd(animated: Bool) {
        expandedSession = nil
        panel.close(animated: animated)
    }

    /// The panel closed on Resolute's side, so the session ends too.
    private func endExpandedSession() {
        guard let session = expandedSession else { return }
        expandedSession = nil
        cancel(session)
    }

    private func cancel(_ session: AnyObject) {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            (session as? NSStatusItemExpandedInterfaceSession)?.cancel()
        }
        #endif
    }
}

#if compiler(>=6.4)
/// Hands macOS 27's expanded-interface callbacks to the status item controller. The protocol
/// is not marked for the main actor, but AppKit calls it on the main thread.
@available(macOS 27, *)
@MainActor
private final class ExpandedInterfaceDelegate: NSObject, @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    weak var owner: StatusItemController?

    init(owner: StatusItemController) {
        self.owner = owner
    }

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        owner?.expandedSessionDidBegin(session)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        owner?.expandedSessionDidEnd(animated: animated)
    }
}
#endif
