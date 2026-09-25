import AppKit
import ResoluteKit

/// Command-line switches for checking the app without opening its menu or windows.
@MainActor
enum Diagnostics {
    static let usage = "usage: Resolute [--version | --dump-menu [--details] | --dump-menu-model [--details] | --render-editor <file.png>]"

    private static let switches: Set<String> = [
        "--version", "--dump-menu", "--dump-menu-model", "--details", "--render-editor",
    ]

    /// Handles a diagnostic switch and returns its exit status, or nil to start normally.
    static func run(_ arguments: [String]) -> Int32? {
        if isMisused(arguments) {
            FileHandle.standardError.write(Data("\(usage)\n".utf8))
            return 64
        }
        if arguments.contains("--version") {
            print(ResoluteVersion.string)
            return 0
        }
        if arguments.contains("--dump-menu") || arguments.contains("--dump-menu-model") {
            let nodes = StatusMenuController.nodes(
                service: SystemDisplayService(),
                preferences: Preferences(),
                loginItem: LoginItemController(),
                showsDetails: arguments.contains("--details")
            )
            if arguments.contains("--dump-menu-model") {
                print(MenuModel.render(nodes))
            } else {
                let menu = NSMenu()
                MenuRenderer.fill(menu, with: nodes, target: nil, action: nil)
                print(MenuRenderer.describe(menu))
            }
            return 0
        }
        if let index = arguments.firstIndex(of: "--render-editor") {
            guard arguments.indices.contains(index + 1) else {
                FileHandle.standardError.write(Data("usage: Resolute --render-editor <file.png>\n".utf8))
                return 64
            }
            return EditorSnapshot.render(to: URL(filePath: arguments[index + 1]))
        }
        return nil
    }

    /// True for a double-dash switch the app doesn't know, or `--details` without a menu
    /// dump to add to, which would otherwise start the menu-bar app. Single-dash arguments
    /// are left alone: LaunchServices and Xcode pass ones like `-NSDocumentRevisionsDebugMode YES`.
    static func isMisused(_ arguments: [String]) -> Bool {
        let given = arguments.dropFirst().filter { $0.hasPrefix("--") }
        let dumpsMenu = given.contains("--dump-menu") || given.contains("--dump-menu-model")
        return given.contains { !switches.contains($0) } || (given.contains("--details") && !dumpsMenu)
    }
}
