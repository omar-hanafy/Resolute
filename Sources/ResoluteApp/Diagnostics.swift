import AppKit
import ResoluteKit

/// Command-line switches for checking the app without its menu.
@MainActor
enum Diagnostics {
    /// Handles a diagnostic switch and returns its exit status, or nil to start normally.
    static func run(_ arguments: [String]) -> Int32? {
        if arguments.contains("--version") {
            print(ResoluteVersion.string)
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
