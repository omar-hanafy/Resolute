import AppKit
// Xcode 16's ScreenCaptureKit content snapshots lack Sendable annotations. The
// snapshot is read-only, and capture state stays local to the main-actor operation.
@preconcurrency import ScreenCaptureKit

/// Writes a window, as the window server composites it, to a PNG without showing it to
/// anyone: the window is ordered in below the desktop picture and captured by
/// ScreenCaptureKit.
///
/// SwiftUI draws text through Core Animation, which `cacheDisplay(in:to:)` does not
/// capture, so the window server's copy is the only faithful image. The terminal that
/// runs this needs the Screen Recording permission.
@MainActor
enum WindowCapture {
    /// Captures `window` after giving SwiftUI `settle` to lay out and the window server
    /// time to composite the first frames. Returns 0 when the PNG was written.
    static func capture(_ window: NSWindow, to url: URL, settle: Duration = .milliseconds(700)) -> Int32 {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.setFrameOrigin(NSScreen.main?.frame.origin ?? .zero)
        window.orderFrontRegardless()

        var status: Int32?
        Task {
            try? await Task.sleep(for: settle)
            status = await captureImage(of: window, to: url)
        }
        while status == nil {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        window.orderOut(nil)
        return status ?? 1
    }

    private static func captureImage(of window: NSWindow, to url: URL) async -> Int32 {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                FileHandle.standardError.write(Data("The window to capture is not capturable.\n".utf8))
                return 1
            }
            let configuration = SCStreamConfiguration()
            let scale = window.backingScaleFactor
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
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
