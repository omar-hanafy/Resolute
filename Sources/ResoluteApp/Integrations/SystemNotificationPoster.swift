import Foundation
import ResoluteKit
import UserNotifications

/// Posts an agent's changes to Notification Center, with Undo, and hears the Undo click as
/// the notification center's delegate.
///
/// `UNUserNotificationCenter` crashes in a process without a bundle identifier, as the debug
/// binary and the gallery are, so there is none of these there: `make()` returns nil.
@MainActor
final class SystemNotificationPoster: NSObject, AgentNotificationPosting {
    nonisolated static let undoAction = "com.omarhanafy.Resolute.undo"
    nonisolated static let undoableCategory = "com.omarhanafy.Resolute.agentChange"

    var onUndo: (@MainActor (UUID) -> Void)?
    private let center: UNUserNotificationCenter

    /// The poster for this process; nil without a bundle identifier.
    static func make(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> SystemNotificationPoster? {
        guard bundleIdentifier != nil else { return nil }
        return SystemNotificationPoster(center: .current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        // Undo works in place: it does not bring Resolute forward.
        let undo = UNNotificationAction(identifier: Self.undoAction, title: "Undo", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.undoableCategory, actions: [undo], intentIdentifiers: [], options: []),
        ])
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error {
                ResoluteLog.history.error("Notifications were not allowed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func post(_ notification: AgentChangeNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.threadIdentifier = notification.group
        if notification.offersUndo { content.categoryIdentifier = Self.undoableCategory }
        let request = UNNotificationRequest(identifier: notification.entryID.uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                ResoluteLog.history.error("Could not post a notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func withdraw(_ entryIDs: [UUID]) {
        center.removeDeliveredNotifications(withIdentifiers: entryIDs.map(\.uuidString))
    }
}

extension SystemNotificationPoster: UNUserNotificationCenterDelegate {
    /// Shown while Resolute is the active app too, as when its window is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.undoAction,
              let id = UUID(uuidString: response.notification.request.identifier)
        else { return }
        await MainActor.run { onUndo?(id) }
    }
}
