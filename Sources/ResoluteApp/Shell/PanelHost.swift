import AppKit
import ResoluteDesign
import SwiftUI

/// The panel that opens from the menu bar icon: a borderless, transparent window under the
/// icon that hosts any SwiftUI view, 340 points wide and as tall as the view wants
/// (Figma: Menu Bar Panel, page 8:6).
///
/// It floats above other windows without making Resolute the active app, takes the
/// keyboard, and closes on a click elsewhere, Esc, or a switch to another app. The view
/// draws its own glass (`.glassBackground(.panel, cornerRadius:)`); content that can grow
/// taller than the screen scrolls itself, as the panel stops at the bottom of the screen.
///
/// On macOS 27 the status item's expanded-interface session decides when it opens and
/// closes; `StatusItemController` drives it either way.
@MainActor
final class PanelHost: NSObject, NSWindowDelegate {
    /// The window the panel hangs under (the status item's) and its frame on screen.
    struct Anchor {
        var window: NSWindow?
        var frame: NSRect
        var screen: NSScreen?
    }

    let panel = StatusPanel()
    private(set) var isOpen = false
    /// Told after the panel opens or closes, however that happened.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Told when the person closed the panel, with a click elsewhere, Esc or another app, as
    /// opposed to `close()`. On macOS 27 the status item then ends its session.
    var onDismiss: (() -> Void)?

    private let hostingView: PanelHostingView
    private var anchor: (() -> Anchor?)?
    private var monitors: [Any] = []
    private var tokens: [NotificationToken] = []
    private var isRefitScheduled = false

    init<Content: View>(content: Content) {
        hostingView = PanelHostingView(rootView: AnyView(content.frame(width: Metrics.Panel.width)))
        super.init()
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: hostingView.intrinsicContentSize))
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        panel.contentView = container
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }
        hostingView.contentSizeDidChange = { [weak self] in self?.scheduleRefit() }
    }

    /// The size the content asks for: the panel's width, and the height of the content at it.
    var contentSize: NSSize {
        let size = hostingView.intrinsicContentSize
        guard size.width != NSView.noIntrinsicMetric, size.height != NSView.noIntrinsicMetric else {
            return hostingView.fittingSize
        }
        return size
    }

    /// Opens the panel under `anchor`, which is asked again whenever the screens change or
    /// the icon moves.
    func open(anchor: @escaping () -> Anchor?) {
        position(under: anchor)
        guard !isOpen else { return }
        isOpen = true
        panel.makeKeyAndOrderFront(nil)
        startWatching()
        onVisibilityChange?(true)
    }

    /// Closes the panel. `animated` false skips the fade, as macOS 27 asks when another
    /// menu takes over.
    func close(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        stopWatching()
        let behavior = panel.animationBehavior
        if !animated { panel.animationBehavior = .none }
        panel.orderOut(nil)
        panel.animationBehavior = behavior
        onVisibilityChange?(false)
    }

    /// The person closed the panel.
    func dismiss() {
        guard isOpen else { return }
        close()
        onDismiss?()
    }

    /// Sizes the panel to its content under `anchor`, without showing it.
    func position(under anchor: @escaping () -> Anchor?) {
        self.anchor = anchor
        refit()
    }

    /// Puts the panel back under the icon at the content's size.
    func refit() {
        isRefitScheduled = false
        guard let anchor = anchor?() else { return }
        let screen = anchor.screen ?? anchor.window?.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = PanelPlacement.frame(contentSize: contentSize, anchor: anchor.frame, visibleFrame: visibleFrame)
        if panel.frame != frame {
            panel.setFrame(frame, display: isOpen)
            panel.invalidateShadow()
        }
    }

    /// The content changed size; fit the panel to it once the change is over, also while a
    /// menu from the panel is open.
    private func scheduleRefit() {
        guard !isRefitScheduled else { return }
        isRefitScheduled = true
        MainRunLoop.perform { [weak self] in self?.refit() }
    }

    // MARK: - Closing on outside events

    private func startWatching() {
        // A click in another app. AppKit calls global monitors on the main thread.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        ) {
            monitors.append(monitor)
        }
        // A click in another Resolute window, and Esc. Clicks on the menu bar icon are its own.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown], handler: { [weak self] event in
                self?.handleLocal(event) ?? event
            }
        ) {
            monitors.append(monitor)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens = [
            NotificationToken(center: .default, name: NSApplication.didResignActiveNotification) { [weak self] in
                self?.dismiss()
            },
            NotificationToken(center: workspace, name: NSWorkspace.didActivateApplicationNotification) { [weak self] in
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else { return }
                self?.dismiss()
            },
            NotificationToken(center: .default, name: NSApplication.didChangeScreenParametersNotification) { [weak self] in
                self?.refit()
            },
        ]
        if let window = anchor?()?.window {
            tokens.append(NotificationToken(center: .default, name: NSWindow.didMoveNotification, object: window) {
                [weak self] in self?.refit()
            })
        }
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        tokens = []
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            guard event.window === panel, PanelKeys.closes(event) else { return event }
            dismiss()
            return nil
        }
        // A click on the icon, in any display's menu bar, opens or closes the panel itself.
        let isOnIcon = event.window === anchor?()?.window || event.window?.level == .statusBar
        if event.window !== panel, !isOnIcon {
            dismiss()
        }
        return event
    }

    // MARK: - NSWindowDelegate

    /// Another window took the keyboard: an alert, the Resolute window, another app.
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}

/// Keys that close the panel.
enum PanelKeys {
    static let escape: UInt16 = 53

    static func closes(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == escape
    }
}

/// Where the panel goes: centered under the menu bar icon, `gap` below the menu bar as in
/// Figma (6 points), kept `margin` inside the screen's visible frame, and no taller than the
/// screen leaves below the menu bar.
enum PanelPlacement {
    static func frame(
        contentSize: CGSize,
        anchor: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = Metrics.Panel.menuBarGap,
        margin: CGFloat = Metrics.Spacing.medium
    ) -> CGRect {
        let top = min(anchor.minY, visibleFrame.maxY) - gap
        let width = max(0, min(contentSize.width, visibleFrame.width - 2 * margin))
        let height = max(0, min(contentSize.height, top - visibleFrame.minY - margin))
        let centered = anchor.midX - width / 2
        let x = min(max(centered, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)
        return CGRect(x: x.rounded(), y: (top - height).rounded(), width: width, height: height.rounded())
    }
}

/// The panel's window: borderless and clear, so the content draws its own glass; above other
/// windows like a menu; non-activating, so opening it leaves the frontmost app frontmost; and
/// able to become key, so it takes the keyboard and Esc.
final class StatusPanel: NSPanel {
    /// Esc, or ⌘. (cancel), reached the panel.
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "Resolute"
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        // Hide Resolute (⌘H) hides the window; the menu bar icon must still open the panel.
        canHide = false
        isReleasedWhenClosed = false
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Hosts the panel's content and says when the content's size changes. SwiftUI takes up a
/// change to the content when it lays the view out, so the size is compared after each
/// layout.
private final class PanelHostingView: NSHostingView<AnyView> {
    var contentSizeDidChange: (() -> Void)?
    private var laidOutSize: NSSize?

    override func layout() {
        super.layout()
        let size = intrinsicContentSize
        guard size != laidOutSize else { return }
        laidOutSize = size
        contentSizeDidChange?()
    }
}
