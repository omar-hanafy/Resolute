import AppKit
import ResoluteDesign
import SwiftUI

extension AppGallery {
    /// Scenes owned by the Welcome window and first-close notice owner.
    static var onboardingScenes: [GalleryScene] {
        [
            GalleryScene(id: "onboarding.welcome", figmaNode: "40:5") {
                welcomeWindow(commandLine: .notInstalled)
            },
            GalleryScene(id: "onboarding.welcome.installed", figmaNode: "40:5") {
                welcomeWindow(commandLine: .installed(
                    version: "0.4.0", detail: "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute"
                ))
            },
            // The popover's own chrome is AppKit's; the scene draws the notice on the panel's
            // glass in its place.
            GalleryScene(id: "onboarding.first-close", title: "First close notice", figmaNode: "25:2477", backdrop: .wallpaper, padding: 24) {
                FirstCloseNoticeView {}
                    .glassBackground(.panel, cornerRadius: Metrics.Panel.cornerRadius)
            },
        ]
    }

    /// Welcome as the first launch shows it, with Launch at Login on as in Figma.
    @MainActor
    private static func welcomeWindow(commandLine status: CommandLineTool.Status) -> NSWindow {
        var environment = AppEnvironment.gallery()
        environment.loginItem = FixedLoginItem(state: .enabled)
        let controller = WelcomeWindowController(
            model: AppModel(environment: environment), commandLine: CommandLineToolModel(status: status)
        )
        guard let window = controller.window else { return NSWindow() }
        window.layoutIfNeeded()
        return window
    }
}
