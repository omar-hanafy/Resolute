import AppKit
import SwiftUI

/// The translucent material behind the panel, the trial dialog and the HUDs: Liquid Glass
/// (`NSGlassEffectView`) on macOS 26 and later, a visual-effect material before.
///
/// Contract (Wave 0): `GlassBackground(_:cornerRadius:)` and `.glassBackground(_:cornerRadius:)`
/// stay; the design-system foundations owner refines the drawing.
public struct GlassBackground: NSViewRepresentable {
    public enum Kind: Sendable, CaseIterable {
        /// The menu bar panel and popovers.
        case panel
        /// The trial dialog and other alerts.
        case alert
        /// The two-second notices after a revert or keep.
        case hud
    }

    /// What the material blurs. Set it with `.glassBlending(_:)`; the default is
    /// `.behindWindow`. Liquid Glass takes no such setting and also blurs what its own
    /// window draws under it, so this decides how the visual-effect material draws
    /// before macOS 26.
    public enum Blending: Sendable {
        /// The desktop and the windows behind this one. The panel, the trial dialog and
        /// the HUDs float over the desktop in transparent windows, so this is what the
        /// app uses.
        case behindWindow
        /// What this window draws under the material. The gallery draws its wallpaper
        /// stand-in inside each scene's window and captures that window on its own, below
        /// the desktop picture, so glass that looked behind the window would show nothing
        /// there; scenes with glass over the wallpaper use this.
        case withinWindow
    }

    public var kind: Kind
    public var cornerRadius: CGFloat

    public init(_ kind: Kind = .panel, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> NSView {
        let host = GlassHostView()
        update(host, environment: context.environment)
        return host
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let host = nsView as? GlassHostView { update(host, environment: context.environment) }
    }

    private func update(_ host: GlassHostView, environment: EnvironmentValues) {
        host.show(Style(kind: kind, cornerRadius: cornerRadius, blending: environment.glassBlending, material: environment.glassMaterial))
    }

    /// Whether this Mac draws Liquid Glass: macOS 26 or later, in a build whose SDK has
    /// `NSGlassEffectView`.
    nonisolated static var drawsLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    /// Everything that decides how the glass is drawn.
    struct Style: Equatable {
        var kind: Kind
        var cornerRadius: CGFloat
        var blending: Blending
        var material: Material

        /// Whether this style draws with `NSGlassEffectView` rather than `NSVisualEffectView`.
        var usesLiquidGlass: Bool {
            material == .automatic && GlassBackground.drawsLiquidGlass
        }

        /// The visual-effect material before macOS 26, by what floats on it.
        var visualEffectMaterial: NSVisualEffectView.Material {
            switch kind {
            case .panel: .popover
            case .alert, .hud: .hudWindow
            }
        }

        var blendingMode: NSVisualEffectView.BlendingMode {
            switch blending {
            case .behindWindow: .behindWindow
            case .withinWindow: .withinWindow
            }
        }
    }

    /// Which effect draws the glass. Catalog scenes force `.visualEffect` to show the look
    /// macOS 14 and 15 get on a Mac that has Liquid Glass.
    enum Material: Sendable {
        case automatic
        case visualEffect
    }
}

/// Holds the view that draws the glass, and replaces it when a style needs the other
/// kind of effect view (an `NSViewRepresentable` can't change its view's class).
final class GlassHostView: NSView {
    private(set) var style: GlassBackground.Style?
    private(set) var effectView: NSView?

    func show(_ newStyle: GlassBackground.Style) {
        guard newStyle != style else { return }
        if effectView == nil || newStyle.usesLiquidGlass != style?.usesLiquidGlass {
            effectView?.removeFromSuperview()
            let view = Self.makeEffectView(liquidGlass: newStyle.usesLiquidGlass)
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            effectView = view
        }
        style = newStyle
        if let effectView { Self.configure(effectView, for: newStyle) }
    }

    static func makeEffectView(liquidGlass: Bool) -> NSView {
        #if compiler(>=6.2)
        if liquidGlass, #available(macOS 26, *) {
            return NSGlassEffectView()
        }
        #endif
        let view = NSVisualEffectView()
        // Always active: a menu bar app is usually not the active app, and an inactive
        // material turns flat and opaque.
        view.state = .active
        view.wantsLayer = true
        return view
    }

    static func configure(_ view: NSView, for style: GlassBackground.Style) {
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.style = .regular
            glass.cornerRadius = style.cornerRadius
            return
        }
        #endif
        guard let effect = view as? NSVisualEffectView else { return }
        effect.material = style.visualEffectMaterial
        effect.blendingMode = style.blendingMode
        effect.layer?.cornerRadius = style.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
    }
}

private struct GlassBlendingKey: EnvironmentKey {
    static let defaultValue: GlassBackground.Blending = .behindWindow
}

private struct GlassMaterialKey: EnvironmentKey {
    static let defaultValue: GlassBackground.Material = .automatic
}

extension EnvironmentValues {
    /// What `GlassBackground` blurs: behind the window (the default) or within it.
    public var glassBlending: GlassBackground.Blending {
        get { self[GlassBlendingKey.self] }
        set { self[GlassBlendingKey.self] = newValue }
    }

    var glassMaterial: GlassBackground.Material {
        get { self[GlassMaterialKey.self] }
        set { self[GlassMaterialKey.self] = newValue }
    }
}

extension View {
    /// Puts `GlassBackground` behind the view, clipped to `cornerRadius` with continuous
    /// corners, and edged with a one-pixel `stroke/window-edge` hairline.
    public func glassBackground(_ kind: GlassBackground.Kind = .panel, cornerRadius: CGFloat) -> some View {
        background(GlassBackground(kind, cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(WindowEdge(cornerRadius: cornerRadius))
    }

    /// Sets what `GlassBackground` blurs in this view: `.withinWindow` for glass drawn
    /// over something in the same window, as in the gallery.
    public func glassBlending(_ blending: GlassBackground.Blending) -> some View {
        environment(\.glassBlending, blending)
    }
}

/// The `stroke/window-edge` hairline around glass: one pixel on any display, like
/// Figma's half-point edge on a Retina screen.
private struct WindowEdge: View {
    var cornerRadius: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Palette.strokeWindowEdge, lineWidth: 1 / max(displayScale, 1))
            .allowsHitTesting(false)
    }
}
