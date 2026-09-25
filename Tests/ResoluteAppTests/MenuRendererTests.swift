import AppKit
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

@MainActor
@Suite struct MenuRendererTests {
    /// A display with a hidden mode, which only its warning sign marks.
    let display = Display(
        id: 2, name: "Studio", currentModeID: 1,
        modes: [
            DisplayMode(modeID: 1, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
            DisplayMode(modeID: 2, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 50),
            DisplayMode(modeID: 91, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60, origin: .hidden),
        ]
    )

    func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    @Test func tellsVoiceOverWhichModesAreHidden() throws {
        let menu = NSMenu()
        MenuRenderer.fill(
            menu, with: MenuModel.build(displays: [display], settings: MenuSettings(showsDetails: true)),
            target: nil, action: nil
        )
        let hidden = try #require(items(menu).first { $0.title.hasPrefix("2560 × 1440") })
        #expect(hidden.image?.accessibilityDescription == "Hidden mode")
    }

    @Test func describesOnlySymbolsThatCarryMeaning() {
        #expect(MenuRenderer.accessibilityDescription(forSymbol: "exclamationmark.triangle") == "Hidden mode")
        // The item titles already say what these stand for.
        for symbol in ["display", "arrow.triangle.2.circlepath", "rectangle.on.rectangle", "slider.horizontal.3"] {
            #expect(MenuRenderer.accessibilityDescription(forSymbol: symbol) == nil)
        }
    }
}
