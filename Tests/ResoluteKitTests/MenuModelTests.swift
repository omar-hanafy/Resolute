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

    @Test func startsWithTheDisplayAndItsSizesAtHand() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        #expect(nodes.first == .header("Built-in Retina Display"))
        // The panel's Larger Text ↔ More Space stops, larger first, the one in use checked.
        let sizes = nodes.dropFirst().prefix { node in
            if case .item(let item) = node { return item.submenu == nil }
            return false
        }
        #expect(sizes.compactMap { node -> String? in
            if case .item(let item) = node { return (item.isChecked ? "✓ " : "") + item.title }
            return nil
        } == ["2056 × 1329", "✓ 1728 × 1117 — Default", "1496 × 967", "1312 × 848", "1168 × 755"])
        guard case .applyMode(1, _, false)? = item(nodes, titled: "1496 × 967")?.action else {
            Issue.record("1496 × 967 does not switch the display")
            return
        }
        #expect(item(nodes, titled: "More Resolutions")?.submenu != nil)
        let refresh = try #require(item(nodes, titled: "Refresh Rate: 120 Hz"))
        #expect(refresh.submenu?.count == 6)
        #expect(item(refresh.submenu ?? [], titled: "60 Hz")?.action
            == .applyMode(displayID: 1, modeID: 55, needsConfirmation: false))
    }

    @Test func endsWithTheAppsActions() {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        #expect(item(nodes, titled: "Open Resolute")?.action == .openWindow)
        #expect(item(nodes, titled: "Settings…")?.action == .openSettings)
        #expect(item(nodes, titled: "Settings…")?.keyEquivalent == ",")
        #expect(item(nodes, titled: "Quit Resolute")?.keyEquivalent == "q")
        // macOS 27 hides menu item images, so the menu has none.
        func images(_ nodes: [MenuNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                guard case .item(let item) = node else { return [] }
                return (item.symbolName.map { [$0] } ?? []) + images(item.submenu ?? [])
            }
        }
        #expect(images(nodes).isEmpty)
    }

    @Test func offersAStandardDisplaysSizeInUseDefaultAndNative() {
        let fullHD = TestData.fullHD()
        let titles = MenuModel.build(displays: [fullHD], settings: MenuSettings()).compactMap { node -> String? in
            if case .item(let item) = node, item.submenu == nil, item.action != nil { return item.title }
            return nil
        }
        // The size in use first; the hidden 2560 × 1440 only under More Resolutions.
        #expect(titles.first?.hasPrefix("1920 × 1080") == true)
        #expect(!titles.contains { $0.hasPrefix("2560 × 1440") })
    }

    @Test func checksTheCurrentResolutionAndBadgesIt() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        let submenu = try #require(item(nodes, titled: "More Resolutions")?.submenu)
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
        let submenu = try #require(item(off, titled: "More Resolutions")?.submenu)
        #expect(!submenu.contains(.header("Low Resolution (1×)")))
        #expect(item(submenu, titled: "3456 × 2234") == nil)
    }

    @Test func showsModeIDsAndHiddenModesWithDetails() throws {
        let fullHD = TestData.fullHD()
        let plain = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "More Resolutions")?.submenu)
        // Two hidden modes, but one is a 75 Hz rate of a listed resolution: ⌥ adds one resolution.
        #expect(item(plain, titled: "Hold ⌥ to Show Hidden Resolutions (1)")?.isEnabled == false)
        #expect(!plain.contains(.header("Hidden")))

        let detailed = try #require(item(
            MenuModel.build(displays: [fullHD], settings: MenuSettings(showsDetails: true)),
            titled: "More Resolutions"
        )?.submenu)
        #expect(detailed.contains(.header("Hidden")))
        let hidden = try #require(item(detailed, titled: "2560 × 1440  #91"))
        #expect(hidden.action == .applyMode(displayID: 2, modeID: 91, needsConfirmation: true))
        #expect(hidden.badge == "Hidden")
    }

    @Test func pointsAtHiddenRefreshRatesWhenThereAreNoHiddenResolutions() throws {
        var fullHD = TestData.fullHD()
        fullHD.modes.removeAll { $0.modeID == 91 }
        let submenu = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "More Resolutions")?.submenu)
        #expect(item(submenu, titled: "Hold ⌥ to Show Hidden Refresh Rates")?.isEnabled == false)
        fullHD.modes.removeAll { $0.origin == .hidden }
        let none = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "More Resolutions")?.submenu)
        #expect(!none.contains { node in
            if case .item(let item) = node { return item.title.hasPrefix("Hold ⌥") }
            return false
        })
    }

    /// A hidden resolution in use is listed without ⌥, so the hint leaves it out, and says
    /// nothing when ⌥ would add nothing.
    @Test func leavesTheResolutionInUseOutOfTheHint() {
        var fullHD = TestData.fullHD(currentModeID: 91)
        #expect(MenuModel.hiddenModesHint(for: fullHD) == "Hold ⌥ to Show Hidden Refresh Rates")
        fullHD.modes.removeAll { $0.modeID == 90 }
        #expect(MenuModel.hiddenModesHint(for: fullHD) == nil)
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
            titled: "More Resolutions"
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
        let resolution = try #require(item(nodes, titled: "More Resolutions"))
        #expect(checkedCount(resolution.submenu ?? []) == 0)
        #expect(checkedCount(nodes) == 0)
        #expect(!MenuModel.render(nodes).contains("Refresh Rate"))
        // A display with no listed modes at all can still be chosen from.
        let empty = Display(id: 8, name: "Empty", currentModeID: nil, modes: [])
        #expect(item(MenuModel.build(displays: [empty], settings: MenuSettings()), titled: "Choose a Resolution") != nil)
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

    @Test func rendersAPlainTextDump() {
        let small = Display(id: 9, name: "Tiny", isMain: true, currentModeID: 1, modes: [
            TestData.mode(1, 1280, 800, scale: 2, hz: 60, flags: 0x7),
            TestData.mode(2, 1280, 800, scale: 2, hz: 30),
            TestData.mode(3, 2560, 1600, hz: 60, flags: 0x0200_0003),
        ])
        let expected = """
            # Tiny
              2560 × 1600 — Native
            ✓ 1280 × 800 — Default
              More Resolutions ▸
                # HiDPI
                ✓ 1280 × 800 [Default]
                # Low Resolution (1×)
                  2560 × 1600 [Native]
                ---
                  Custom Resolutions…
              Refresh Rate: 60 Hz ▸
                ✓ 60 Hz
                  30 Hz
            ---
              Open Resolute
              Settings…
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
