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
        do {
            let outcome = try ModeSwitcher(service: service).apply(modeID: modeID, to: displayID, trial: needsConfirmation) {
                ConfirmationPanel.keepNewMode(countdown: RevertCountdown()) ? .keep : .revert
            }
            if case .restorePending(let pending) = outcome {
                throw ResoluteError.revertFailed(display: pending.displayName)
            }
        } catch {
            Alerts.show(error, title: "The display mode could not be changed")
        }
    }
}
