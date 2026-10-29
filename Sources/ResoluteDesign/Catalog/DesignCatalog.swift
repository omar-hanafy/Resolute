import SwiftUI

/// One component or screen state the gallery renders to a PNG, to compare with its Figma
/// frame: `Resolute --render-gallery <folder>` writes `<id>.light.png` and `<id>.dark.png`.
public struct CatalogScene: Identifiable {
    /// What the gallery draws behind the scene.
    public enum Backdrop: Sendable {
        /// Nothing: the window is transparent around the scene.
        case none
        /// The window background color.
        case window
        /// A desktop-picture stand-in, for glass that floats over the desktop.
        case wallpaper
    }

    /// Unique and stable: lowercase, dot-separated, owner prefix first ("ds.badge",
    /// "panel.two-displays").
    public let id: String
    public let title: String
    /// The Figma node the scene reproduces ("17:15"), if any.
    public let figmaNode: String?
    /// The window size; nil fits the content.
    public let size: CGSize?
    public let backdrop: Backdrop
    /// Padding the gallery adds around the scene, on the backdrop.
    public let padding: CGFloat
    public let make: @MainActor () -> AnyView

    public init(
        id: String,
        title: String,
        figmaNode: String? = nil,
        size: CGSize? = nil,
        backdrop: Backdrop = .window,
        padding: CGFloat = 0,
        make: @escaping @MainActor () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.figmaNode = figmaNode
        self.size = size
        self.backdrop = backdrop
        self.padding = padding
        self.make = make
    }

    /// A scene from a view builder.
    public init<Content: View>(
        id: String,
        title: String,
        figmaNode: String? = nil,
        size: CGSize? = nil,
        backdrop: Backdrop = .window,
        padding: CGFloat = 0,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.init(id: id, title: title, figmaNode: figmaNode, size: size, backdrop: backdrop, padding: padding) {
            AnyView(content())
        }
    }
}

/// Every design-system scene, so the components can be checked against Figma on their own.
/// Each owner adds scenes in its own `Catalog+….swift` file.
public enum DesignCatalog {
    @MainActor public static var scenes: [CatalogScene] {
        foundations + controls + pictures + panelComponents + windowComponents
    }
}
