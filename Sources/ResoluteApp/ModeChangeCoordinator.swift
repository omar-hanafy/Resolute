import AppKit
import ResoluteKit

/// Applies mode changes chosen in the menu. Hidden modes are tried for the session first
/// and only kept when the person confirms, so a mode the display cannot show reverts.
@MainActor
final class ModeChangeCoordinator {
    private let service: any DisplayControlling

    init(service: any DisplayControlling) {
        self.service = service
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool) {
        let previous = service.currentModeID(of: displayID)
        guard previous != modeID else { return }
        do {
            try service.apply(modeID: modeID, to: displayID, scope: needsConfirmation ? .session : .permanent)
        } catch {
            Alerts.show(error, title: "The display mode could not be changed")
            return
        }
        guard needsConfirmation else { return }
        if ConfirmationPanel.keepNewMode(countdown: RevertCountdown()) {
            do {
                try service.apply(modeID: modeID, to: displayID, scope: .permanent)
            } catch {
                Alerts.show(error, title: "The display mode could not be saved")
            }
        } else if let previous {
            do {
                try service.apply(modeID: previous, to: displayID, scope: .permanent)
            } catch {
                Alerts.show(error, title: "The previous display mode could not be restored")
            }
        }
    }
}
