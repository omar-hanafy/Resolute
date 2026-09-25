import AppKit
import ResoluteKit
// Xcode 16's ScreenCaptureKit content snapshots lack Sendable annotations. The
// snapshot is read-only, and capture state stays local to the main-actor operation.
@preconcurrency import ScreenCaptureKit
import SwiftUI

/// Renders the Custom Resolutions window to a PNG without showing it to anyone: the
/// window is ordered in below the desktop picture and captured by ScreenCaptureKit.
///
/// SwiftUI draws text through Core Animation, which `cacheDisplay(in:to:)` does not
/// capture, so the window server's copy is the only faithful image. The terminal that
/// runs this needs the Screen Recording permission.
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
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.setFrameOrigin(NSScreen.main?.frame.origin ?? .zero)
        window.orderFrontRegardless()

        var status: Int32?
        Task {
            // Let SwiftUI lay out and the window server composite the first frames.
            try? await Task.sleep(for: .seconds(1.5))
            status = await capture(window, to: url)
        }
        while status == nil {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        window.orderOut(nil)
        return status ?? 1
    }

    private static func capture(_ window: NSWindow, to url: URL) async -> Int32 {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                FileHandle.standardError.write(Data("The snapshot window is not capturable.\n".utf8))
                return 1
            }
            let configuration = SCStreamConfiguration()
            let scale = window.backingScaleFactor
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target),
                configuration: configuration
            )
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                return 1
            }
            try png.write(to: url)
            print("Wrote \(url.path(percentEncoded: false))")
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}

/// Refuses every command, so a snapshot can never change the system.
struct RefusingRunner: CommandRunning {
    func run(_ script: String) async throws {
        throw ResoluteError.cancelled
    }
}
