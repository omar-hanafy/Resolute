import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Settings › General (Figma 40:149): Launch at Login; the menu bar icon, the resolution
/// next to it and the panel's shortcut; the modes the panel lists and how long a hidden one
/// is tried.
struct GeneralSettings: View {
    /// Under Show Resolute in the menu bar. It says nothing of whether the item shows: macOS
    /// lets people hide it, and Resolute can't read that.
    static let menuBarItemHelp = "macOS controls this in System Settings › Menu Bar."

    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: Metrics.Settings.spacing) {
            SettingsSectionLabel("Startup")
            FormGroup {
                LaunchAtLoginRow(model: model, help: "Resolute starts quietly in the menu bar. Quitting doesn’t change this.")
            }
            SettingsSectionLabel("Menu Bar")
            FormGroup {
                // macOS 26 lets people hide any app's menu bar item in System Settings; Resolute
                // can't change that, only point at it.
                if #available(macOS 26, *) {
                    FormRow(
                        "Show Resolute in the menu bar",
                        help: GeneralSettings.menuBarItemHelp,
                        buttonTitle: "Open…"
                    ) {
                        SystemSettingsLink.menuBar.open()
                    }
                }
                FormRow(
                    "Show the resolution next to the icon",
                    help: "For example 1728 × 1117. The icon alone takes the least space.",
                    isOn: $preferences.showsResolutionInMenuBar
                )
                FormRow("Open the panel", help: "A keyboard shortcut that opens the panel from anywhere.") {
                    ShortcutRecorder(
                        shortcut: $preferences.panelShortcut,
                        conflict: { model.shortcutConflict($0, ignoring: .panel) }
                    )
                }
            }
            SettingsSectionLabel("Panel")
            FormGroup {
                FormRow(
                    "Show low-resolution (1×) modes",
                    help: "Modes that draw one pixel per point, like the panel’s full native resolution.",
                    isOn: $preferences.showLowResolutionModes
                )
                FormRow(
                    "Show hidden modes",
                    help: "Or hold ⌥ while clicking the menu bar icon to show them once.",
                    isOn: $preferences.showHiddenModes
                )
                FormRow(
                    "Hidden-mode trial",
                    help: "How long a hidden mode runs before it switches back on its own.",
                    selection: $preferences.trialLength,
                    options: TrialLength.allCases.map { FormRowPopUp.Option($0, $0.title) }
                )
            }
        }
        .onAppear { model.refresh() }
    }
}

/// Launch at Login, as Settings and Welcome show it: a switch that follows what macOS says,
/// with a line under it when macOS waits for approval or can't register the app.
struct LaunchAtLoginRow: View {
    let model: AppModel
    /// Settings and Welcome describe it in their own words.
    var help: String

    var body: some View {
        FormRow("Launch at Login", help: currentHelp) {
            FormRowSwitch(
                "Launch at Login",
                isOn: Binding(
                    get: { model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval },
                    set: { _ in model.toggleLaunchAtLogin() }
                )
            )
            .disabled(model.launchAtLogin == .unavailable)
        }
    }

    private var currentHelp: String {
        switch model.launchAtLogin {
        case .enabled, .disabled: help
        case .requiresApproval: "Waiting for your approval in System Settings › General › Login Items."
        case .unavailable: "Available when Resolute runs from its app in Applications."
        }
    }
}

/// Panes of System Settings that Settings points at.
enum SystemSettingsLink {
    /// Menu Bar (Control Center before macOS 26), where people allow an app's menu bar item.
    case menuBar

    var url: URL? {
        switch self {
        case .menuBar: URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
        }
    }

    @MainActor
    func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
