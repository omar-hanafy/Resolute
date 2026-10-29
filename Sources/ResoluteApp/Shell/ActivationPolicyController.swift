import AppKit

/// Resolute lives in the menu bar, and is in the Dock and ⌘Tab only while one of its windows
/// is open: `.accessory` normally, `.regular` from the moment a window opens until the last
/// one closes. A minimized window still counts, so its Dock tile stays.
@MainActor
final class ActivationPolicyController {
    private(set) var policy: NSApplication.ActivationPolicy = .accessory
    private var openWindows: Set<ObjectIdentifier> = []
    private var tokens: [ObjectIdentifier: NotificationToken] = [:]
    private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void

    /// `apply` sets the policy; tests record it instead.
    init(apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }) {
        self.apply = apply
    }

    /// A window is about to show: the Dock icon and ⌘Tab come first, so the window opens
    /// in front, with Resolute's menu bar.
    func windowWillOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        update()
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        update()
    }

    /// Follows a window this controller is not told about, such as the Custom Resolutions
    /// editor: it counts from now until it closes.
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if tokens[id] == nil {
            tokens[id] = NotificationToken(center: .default, name: NSWindow.willCloseNotification, object: window) {
                [weak self, weak window] in
                guard let window else { return }
                self?.windowDidClose(window)
            }
        }
        windowWillOpen(window)
    }

    private func update() {
        let wanted: NSApplication.ActivationPolicy = openWindows.isEmpty ? .accessory : .regular
        guard wanted != policy else { return }
        policy = wanted
        apply(wanted)
    }
}
