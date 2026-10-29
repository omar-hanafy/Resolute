import AppKit
import ResoluteKit

/// Renders the Custom Resolutions window to a PNG without showing it to anyone, through
/// `WindowCapture`.
@MainActor
enum EditorSnapshot {
    static func render(to url: URL) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = CustomResolutionsModel(
            service: SystemDisplayService(),
            installer: OverrideInstaller(runner: RefusingRunner())
        )
        // Prefer a display that already has an override, so the table has rows.
        if let target = model.targets.first(where: \.hasOverride) {
            model.select(target.key)
        }
        // The real window, ordered in below the desktop picture: the window server
        // composites it, but nobody sees it, and it never becomes active.
        let controller = CustomResolutionsWindowController(model: model)
        guard let window = controller.window else { return 1 }
        window.setFrameAutosaveName("")
        return WindowCapture.capture(window, to: url, settle: .seconds(1.5))
    }
}

/// Refuses every command, so a snapshot can never change the system.
struct RefusingRunner: CommandRunning {
    func run(_ script: String) async throws {
        throw ResoluteError.cancelled
    }
}
