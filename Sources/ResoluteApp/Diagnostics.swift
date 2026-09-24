import AppKit
import ResoluteKit

/// Command-line switches for checking the app without opening its menu or windows.
@MainActor
enum Diagnostics {
    /// Handles a diagnostic switch and returns its exit status, or nil to start normally.
    static func run(_ arguments: [String]) -> Int32? {
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
}
