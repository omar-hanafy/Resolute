import Foundation
import Testing
@testable import ResoluteKit

@Suite struct MenuModelTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    func item(_ nodes: [MenuNode], titled title: String) -> MenuItem? {
        for node in nodes {
            if case .item(let item) = node, item.title == title { return item }
        }
        return nil
    }

    func checkedCount(_ nodes: [MenuNode]) -> Int {
        nodes.filter { node in
            if case .item(let item) = node { return item.isChecked }
            return false
        }.count
    }

    @Test func startsWithTheDisplayAndItsCurrentMode() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        #expect(nodes.first == .header("Built-in Retina Display"))
        let resolution = try #require(item(nodes, titled: "1728 × 1117"))
        #expect(resolution.subtitle == "HiDPI · 3456 × 2234 pixels")
        let refresh = try #require(item(nodes, titled: "120 Hz"))
        #expect(refresh.submenu?.count == 6)
        #expect(item(refresh.submenu ?? [], titled: "60 Hz")?.action
            == .applyMode(displayID: 1, modeID: 55, needsConfirmation: false))
    }

    @Test func checksTheCurrentResolutionAndBadgesIt() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        let submenu = try #require(item(nodes, titled: "1728 × 1117")?.submenu)
        let current = try #require(item(submenu, titled: "1728 × 1117"))
        #expect(current.isChecked)
        #expect(current.badge == "Default")
        #expect(current.action == .applyMode(displayID: 1, modeID: 54, needsConfirmation: false))
        #expect(item(submenu, titled: "3456 × 2234")?.badge == "Native")
        #expect(checkedCount(submenu) == 1)
        #expect(submenu.contains(.header("HiDPI")))
        #expect(submenu.contains(.header("Low Resolution (1×)")))
        #expect(item(submenu, titled: "Custom Resolutions…")?.action == .openCustomResolutions(displayID: 1))
    }

    @Test func omitsLowResolutionModesWhenTurnedOff() throws {
        let off = MenuModel.build(displays: [display], settings: MenuSettings(showLowResolutionModes: false))
        let submenu = try #require(item(off, titled: "1728 × 1117")?.submenu)
        #expect(!submenu.contains(.header("Low Resolution (1×)")))
        #expect(item(submenu, titled: "3456 × 2234") == nil)
        #expect(item(off, titled: "Show Low-Resolution Modes")?.isChecked == false)
        #expect(item(off, titled: "Show Low-Resolution Modes")?.action == .toggleLowResolutionModes)
    }

    @Test func showsModeIDsAndHiddenModesWithDetails() throws {
        let fullHD = TestData.fullHD()
        let plain = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "1920 × 1080")?.submenu)
        // Two hidden modes, but one is a 75 Hz rate of a listed resolution: ⌥ adds one resolution.
        #expect(item(plain, titled: "Hold ⌥ to Show Hidden Resolutions (1)")?.isEnabled == false)
        #expect(!plain.contains(.header("Hidden")))

        let detailed = try #require(item(
            MenuModel.build(displays: [fullHD], settings: MenuSettings(showsDetails: true)),
            titled: "1920 × 1080  #1"
        )?.submenu)
        #expect(detailed.contains(.header("Hidden")))
        let hidden = try #require(item(detailed, titled: "2560 × 1440  #91"))
        #expect(hidden.action == .applyMode(displayID: 2, modeID: 91, needsConfirmation: true))
        #expect(hidden.symbolName == "exclamationmark.triangle")
    }

    @Test func pointsAtHiddenRefreshRatesWhenThereAreNoHiddenResolutions() throws {
        var fullHD = TestData.fullHD()
        fullHD.modes.removeAll { $0.modeID == 91 }
        let submenu = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "1920 × 1080")?.submenu)
        #expect(item(submenu, titled: "Hold ⌥ to Show Hidden Refresh Rates")?.isEnabled == false)
        fullHD.modes.removeAll { $0.origin == .hidden }
        let none = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "1920 × 1080")?.submenu)
        #expect(!none.contains { node in
            if case .item(let item) = node { return item.title.hasPrefix("Hold ⌥") }
            return false
        })
    }

    /// The menu and `resolute modes` label a resolution the same way: Default wins over Native.
    @Test func badgesAResolutionOnce() {
        let group = { (flags: UInt32) in
            ResolutionGroup(key: .init(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234), modes: [
                TestData.mode(1, 1728, 1117, scale: 2, flags: flags),
            ])
        }
        #expect(group(0x0200_0007).badge == "Default")
        #expect(group(0x0200_0003).badge == "Native")
        #expect(group(0x3).badge == nil)
    }

    @Test func explainsWhyHiddenModesAreMissing() throws {
        var untrusted = display
        untrusted.privateModes = .untrusted(reason: "record 3 has an unrecognised layout")
        let submenu = try #require(item(
            MenuModel.build(displays: [untrusted], settings: MenuSettings(showsDetails: true)),
            titled: "1728 × 1117  #54"
        )?.submenu)
        #expect(item(submenu, titled: "Hidden Modes Unavailable")?.subtitle == "record 3 has an unrecognised layout")
    }

    @Test func offersMirroringOnlyWithTwoDisplays() throws {
        #expect(item(MenuModel.build(displays: [display], settings: MenuSettings()), titled: "Mirror Displays") == nil)
        var external = TestData.uhd()
        external.isInMirrorSet = true
        external.mirrorSourceID = 1
        var builtIn = display
        builtIn.isInMirrorSet = true
        let nodes = MenuModel.build(displays: [external, builtIn], settings: MenuSettings())
        let mirror = try #require(item(nodes, titled: "Mirror Displays"))
        #expect(mirror.isChecked)
        #expect(mirror.action == .setMirroring(false))
        #expect(nodes.first == .header("Built-in Retina Display"))
        #expect(nodes.contains(.header("4K Monitor — mirroring Built-in Retina Display")))
    }

    @Test func rendersWithoutACurrentMode() throws {
        let unknown = capture.display(currentModeID: 9_999)
        let nodes = MenuModel.build(displays: [unknown], settings: MenuSettings())
        let resolution = try #require(item(nodes, titled: "Choose a Resolution"))
        #expect(checkedCount(resolution.submenu ?? []) == 0)
        #expect(item(nodes, titled: "120 Hz") == nil)
    }

    @Test func omitsRefreshRateWhenUnknown() {
        let projector = Display(id: 7, name: "Projector", currentModeID: 1, modes: [
            TestData.mode(1, 1024, 768, hz: 0),
            TestData.mode(2, 800, 600, hz: 0),
        ])
        let rendered = MenuModel.render(MenuModel.build(displays: [projector], settings: MenuSettings()))
        #expect(!rendered.contains("Hz"))
        #expect(rendered.contains("✓ 1024 × 768"))
    }

    @Test func saysSoWhenThereAreNoDisplays() {
        let nodes = MenuModel.build(displays: [], settings: MenuSettings())
        #expect(item(nodes, titled: "No Displays Found")?.isEnabled == false)
        #expect(item(nodes, titled: "Quit Resolute")?.keyEquivalent == "q")
    }

    @Test func describesLaunchAtLoginStates() {
        #expect(MenuModel.launchAtLoginItem(.enabled).isChecked)
        #expect(!MenuModel.launchAtLoginItem(.disabled).isChecked)
        #expect(MenuModel.launchAtLoginItem(.requiresApproval).subtitle == "Needs approval in System Settings")
        #expect(!MenuModel.launchAtLoginItem(.unavailable).isEnabled)
    }

    @Test func rendersAPlainTextDump() {
        let small = Display(id: 9, name: "Tiny", isMain: true, currentModeID: 1, modes: [
            TestData.mode(1, 1280, 800, scale: 2, hz: 60, flags: 0x7),
            TestData.mode(2, 1280, 800, scale: 2, hz: 30),
            TestData.mode(3, 2560, 1600, hz: 60, flags: 0x0200_0003),
        ])
        let expected = """
            # Tiny
              1280 × 800 — HiDPI · 2560 × 1600 pixels ▸
                # HiDPI
                ✓ 1280 × 800 [Default]
                # Low Resolution (1×)
                  2560 × 1600 [Native]
                ---
                  Custom Resolutions…
              60 Hz ▸
                ✓ 60 Hz
                  30 Hz
            ---
              Custom Resolutions…
            ---
            ✓ Show Low-Resolution Modes
              Launch at Login
            ---
              About Resolute
              Quit Resolute
            """
        #expect(MenuModel.render(MenuModel.build(displays: [small], settings: MenuSettings())) == expected)
    }
}

@Suite struct RevertCountdownTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countsDownAndExpires() {
        let countdown = RevertCountdown(start: start, duration: 15)
        #expect(countdown.secondsRemaining(at: start) == 15)
        #expect(countdown.secondsRemaining(at: start.addingTimeInterval(14.2)) == 1)
        #expect(!countdown.isExpired(at: start.addingTimeInterval(14.9)))
        #expect(countdown.isExpired(at: start.addingTimeInterval(15)))
        #expect(countdown.secondsRemaining(at: start.addingTimeInterval(20)) == 0)
    }

    @Test func explainsWhatHappens() {
        let countdown = RevertCountdown(start: start, duration: 15)
        #expect(countdown.message(at: start)
            == "The previous mode comes back in 15 seconds unless you keep this one.")
        #expect(countdown.message(at: start.addingTimeInterval(14.5))
            == "The previous mode comes back in 1 second unless you keep this one.")
    }
}
