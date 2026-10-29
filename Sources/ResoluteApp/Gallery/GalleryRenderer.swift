import AppKit
import ResoluteDesign
import SwiftUI

/// A scene the gallery renders: a design-system scene, or a window the app builds the way
/// it shows it.
@MainActor
struct GalleryScene {
    enum Content {
        case view(CatalogScene)
        /// A window as the app shows it. The gallery sets its appearance before capturing.
        case window(@MainActor () -> NSWindow)
    }

    var id: String
    var figmaNode: String?
    var content: Content

    init(_ scene: CatalogScene) {
        id = scene.id
        figmaNode = scene.figmaNode
        content = .view(scene)
    }

    init(id: String, figmaNode: String? = nil, window: @escaping @MainActor () -> NSWindow) {
        self.id = id
        self.figmaNode = figmaNode
        content = .window(window)
    }

    /// An app screen drawn as a SwiftUI view, framed like a design-system scene.
    init<Content: View>(
        id: String,
        title: String,
        figmaNode: String? = nil,
        size: CGSize? = nil,
        backdrop: CatalogScene.Backdrop = .window,
        padding: CGFloat = 0,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.init(CatalogScene(
            id: id, title: title, figmaNode: figmaNode, size: size, backdrop: backdrop, padding: padding, content: content
        ))
    }
}

/// Renders gallery scenes to PNGs in Light and Dark, for comparing with their Figma frames:
///
///     Resolute --render-gallery <folder> [--only <id-prefix>,…] [--appearance light|dark|both]
///     Resolute --list-gallery
@MainActor
enum GalleryRenderer {
    enum Appearance: String, CaseIterable {
        case light
        case dark

        var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    }

    static let usage = """
        usage: Resolute --render-gallery <folder> [--only <id-prefix>[,<id-prefix>…]] [--appearance light|dark|both]
               Resolute --list-gallery
        """

    /// Handles `--render-gallery` and `--list-gallery`; nil when neither was given.
    static func run(_ arguments: [String]) -> Int32? {
        if arguments.contains("--list-gallery") {
            for scene in AppGallery.scenes {
                print(scene.id + (scene.figmaNode.map { "  (Figma \($0))" } ?? ""))
            }
            return 0
        }
        guard let index = arguments.firstIndex(of: "--render-gallery") else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            FileHandle.standardError.write(Data("\(usage)\n".utf8))
            return 64
        }
        let directory = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        let prefixes = value(after: "--only", in: arguments)?.split(separator: ",").map(String.init) ?? []
        let appearances: [Appearance]
        switch value(after: "--appearance", in: arguments) ?? "both" {
        case "light": appearances = [.light]
        case "dark": appearances = [.dark]
        case "both": appearances = Appearance.allCases
        default:
            FileHandle.standardError.write(Data("\(usage)\n".utf8))
            return 64
        }
        let scenes = AppGallery.scenes.filter { scene in
            prefixes.isEmpty || prefixes.contains { scene.id.hasPrefix($0) }
        }
        guard !scenes.isEmpty else {
            FileHandle.standardError.write(Data("No gallery scene matches \(prefixes.joined(separator: ", ")).\n".utf8))
            return 1
        }
        return render(scenes, to: directory, appearances: appearances)
    }

    static func render(_ scenes: [GalleryScene], to directory: URL, appearances: [Appearance]) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
        var failures = 0
        for scene in scenes {
            for appearance in appearances {
                let window = makeWindow(for: scene, appearance: appearance)
                let url = directory.appending(path: "\(scene.id).\(appearance.rawValue).png")
                if WindowCapture.capture(window, to: url) != 0 { failures += 1 }
                window.orderOut(nil)
            }
        }
        return failures == 0 ? 0 : 1
    }

    static func makeWindow(for scene: GalleryScene, appearance: Appearance) -> NSWindow {
        switch scene.content {
        case .window(let make):
            let window = make()
            window.appearance = NSAppearance(named: appearance.name)
            return window
        case .view(let catalog):
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.appearance = NSAppearance(named: appearance.name)
            let hosting = NSHostingView(rootView: SceneFrame(scene: catalog))
            let size = catalog.size.map {
                CGSize(width: $0.width + 2 * catalog.padding, height: $0.height + 2 * catalog.padding)
            } ?? hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            window.setContentSize(size)
            window.contentView = hosting
            return window
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("--") ? nil : value
    }
}

/// A catalog scene at its size, padded, on its backdrop.
private struct SceneFrame: View {
    let scene: CatalogScene

    var body: some View {
        scene.make()
            .frame(width: scene.size?.width, height: scene.size?.height)
            .padding(scene.padding)
            .background {
                switch scene.backdrop {
                case .none: Color.clear
                case .window: Palette.windowBackground
                case .wallpaper: WallpaperBackdrop()
                }
            }
    }
}
