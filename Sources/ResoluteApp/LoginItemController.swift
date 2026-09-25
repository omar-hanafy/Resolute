import Foundation
import ResoluteKit
import ServiceManagement

/// Launch at Login, as the menu and the diagnostics change it. Tests use a fake, so they
/// never register or unregister the real app.
@MainActor
protocol LoginItemControlling {
    var state: LaunchAtLoginState { get }
    /// Turns Launch at Login off, without asking anything or showing any UI.
    func unregister() throws
}

/// Launch at Login through `SMAppService`.
@MainActor
final class LoginItemController: LoginItemControlling {
    var state: LaunchAtLoginState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func toggle() {
        do {
            switch state {
            case .enabled:
                try unregister()
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
