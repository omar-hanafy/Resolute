import AppKit
import ResoluteKit

/// "Keep this display mode?" with an automatic revert.
@MainActor
enum ConfirmationPanel {
    /// Returns true only when the person chooses Keep before the countdown ends. Return
    /// (the default button) reverts, which is the safe choice on an unreadable screen.
    static func keepNewMode(countdown: RevertCountdown) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Keep this display mode?"
        alert.informativeText = countdown.message(at: Date())
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Keep")
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            let expired = countdown.isExpired(at: Date())
            if expired { timer.invalidate() }
            // The timer runs on the main run loop, in the modal panel's mode.
            MainActor.assumeIsolated {
                if expired {
                    NSApp.abortModal()
                } else {
                    alert.informativeText = countdown.message(at: Date())
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        NSApp.activate()
        let response = alert.runModal()
        timer.invalidate()
        return response == .alertSecondButtonReturn
    }
}
