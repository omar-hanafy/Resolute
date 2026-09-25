import AppKit
import ResoluteKit

/// "Keep this display mode?" with an automatic revert.
@MainActor
enum ConfirmationPanel {
    /// Returns true only when the person chooses Keep before the countdown ends. Return
    /// (the default button) and Escape revert, which is the safe choice on an unreadable
    /// screen.
    static func keepNewMode(countdown: RevertCountdown) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Keep this display mode?"
        alert.informativeText = countdown.message(at: Date())
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Keep")
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            let expired = countdown.isExpired(at: Date())
            // The timer runs on the main run loop, in the modal panel's mode.
            let ended = MainActor.assumeIsolated { () -> Bool in
                if Self.shouldEnd(expired: expired, modalWindow: NSApp.modalWindow, countdownWindow: alert.window) {
                    NSApp.abortModal()
                    return true
                }
                if !expired { alert.informativeText = countdown.message(at: Date()) }
                return false
            }
            if ended { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let answer = Self.response(to: event) else { return event }
            NSApp.stopModal(withCode: answer)
            return nil
        }
        NSApp.activate()
        let response = alert.runModal()
        timer.invalidate()
        if let keys { NSEvent.removeMonitor(keys) }
        return response == .alertSecondButtonReturn
    }

    /// Whether the countdown's timer should end the modal session now. `abortModal` ends
    /// the innermost one, so while another alert is over the countdown the timer waits for
    /// it to close rather than end it in the countdown's place.
    static func shouldEnd(expired: Bool, modalWindow: NSWindow?, countdownWindow: NSWindow) -> Bool {
        expired && modalWindow === countdownWindow
    }

    /// What a key pressed in the alert answers, when the alert would not answer it
    /// itself: NSAlert gives Escape only to a button titled Cancel, and here Escape must
    /// revert (the first button), like Return.
    static func response(to event: NSEvent) -> NSApplication.ModalResponse? {
        let escape: UInt16 = 53
        return event.type == .keyDown && event.keyCode == escape ? .alertFirstButtonReturn : nil
    }
}
