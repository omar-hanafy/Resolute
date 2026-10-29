import Foundation
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the Settings pages owner.
    static var settingsScenes: [GalleryScene] {
        [
            GalleryScene(id: "settings.general", title: "Settings, General", figmaNode: "40:149", size: settingsSize(height: 680)) {
                SettingsPage(model: settingsModel(), tab: .general, commandLine: SettingsSamples.installed, about: SettingsSamples.about)
            },
            GalleryScene(
                id: "settings.command-line", title: "Settings, Command Line & Agents", figmaNode: "42:295", size: settingsSize(height: 760)
            ) {
                SettingsPage(model: settingsModel(), tab: .commandLine, commandLine: SettingsSamples.installed, about: SettingsSamples.about)
            },
            GalleryScene(
                id: "settings.command-line.not-installed", title: "Settings, the command not installed", figmaNode: "42:295",
                size: settingsSize(height: 320)
            ) {
                CommandLineRowSamples(statuses: [
                    .notInstalled,
                    .occupied(path: "/usr/local/bin/resolute"),
                    .unavailable,
                ])
            },
            GalleryScene(id: "settings.about", title: "Settings, About", figmaNode: "42:789", size: settingsSize(height: 600)) {
                SettingsPage(model: settingsModel(), tab: .about, commandLine: SettingsSamples.installed, about: SettingsSamples.about)
            },
        ]
    }

    /// The window's content area, 800 points wide as in Figma.
    private static func settingsSize(height: CGFloat) -> CGSize {
        CGSize(width: 800, height: height)
    }

    /// The gallery's app with Launch at Login on, as Figma shows it.
    @MainActor
    private static func settingsModel() -> AppModel {
        var environment = AppEnvironment.gallery()
        environment.loginItem = FixedLoginItem(state: .enabled)
        return AppModel(environment: environment)
    }
}

/// Figma's values for the Settings scenes.
@MainActor
enum SettingsSamples {
    static var installed: CommandLineToolModel {
        CommandLineToolModel(status: .installed(
            version: "0.4.0", detail: "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute"
        ))
    }

    static let about = AboutInfo(version: "0.4.0", system: "macOS 27 Golden Gate", architectures: "Apple silicon and Intel")
}

/// The command's row in each state Figma doesn't draw: not installed, another tool in its
/// place, and Resolute not running from its app.
private struct CommandLineRowSamples: View {
    var statuses: [CommandLineTool.Status]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Settings.spacing) {
            ForEach(statuses.indices, id: \.self) { index in
                FormGroup {
                    CommandLineToolRow(model: CommandLineToolModel(status: statuses[index]))
                }
            }
        }
        .padding(Metrics.TitledPage.insets)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
