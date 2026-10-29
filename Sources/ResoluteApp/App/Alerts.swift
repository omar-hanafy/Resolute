import AppKit
import ResoluteKit

@MainActor
enum Alerts {
    /// Shows `error`, unless the person cancelled.
    static func show(_ error: Error, title: String) {
        if let error = error as? ResoluteError, error == .cancelled { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
