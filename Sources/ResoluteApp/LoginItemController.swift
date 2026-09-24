import Foundation
import ResoluteKit
import ServiceManagement

/// Launch at Login through `SMAppService`.
@MainActor
final class LoginItemController {
    var state: LaunchAtLoginState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func toggle() {
        do {
            switch state {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .disabled:
                try SMAppService.mainApp.register()
                if state == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            case .unavailable:
                break
            }
        } catch {
            Alerts.show(error, title: "Launch at Login could not be changed")
        }
    }
}
