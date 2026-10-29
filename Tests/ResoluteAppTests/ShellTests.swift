import AppKit
import Observation
import ResoluteDesign
import SwiftUI
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// A window that is never ordered in.
@MainActor
func offscreenWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true
    )
    window.isReleasedWhenClosed = false
    return window
}

@MainActor
@Suite struct ActivationPolicyTests {
    @MainActor
    final class Applied {
        var policies: [NSApplication.ActivationPolicy] = []
    }

    let applied = Applied()
    let controller: ActivationPolicyController

    init() {
        let applied = applied
        controller = ActivationPolicyController { applied.policies.append($0) }
    }

    @Test func showsInTheDockWhileAWindowIsOpen() {
        let window = offscreenWindow()
        #expect(controller.policy == .accessory)
        controller.windowWillOpen(window)
        #expect(controller.policy == .regular)
        controller.windowDidClose(window)
        #expect(controller.policy == .accessory)
        #expect(applied.policies == [.regular, .accessory])
    }

    @Test func staysInTheDockUntilTheLastWindowCloses() {
        let first = offscreenWindow()
        let second = offscreenWindow()
        controller.windowWillOpen(first)
        controller.windowWillOpen(second)
        controller.windowWillOpen(first)
        controller.windowDidClose(first)
        #expect(controller.policy == .regular)
        controller.windowDidClose(second)
        #expect(controller.policy == .accessory)
        // Each change is applied once.
        #expect(applied.policies == [.regular, .accessory])
    }

    @Test func followsAWindowItIsNotToldAbout() async throws {
        let window = offscreenWindow()
        controller.track(window)
        controller.track(window)
        #expect(controller.policy == .regular)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.policy == .accessory)
        #expect(applied.policies == [.regular, .accessory])
    }

    @Test func leavesTheDockWhenTheResoluteWindowCloses() throws {
        let model = AppModel(environment: .gallery())
        let navigation = WindowNavigation(route: model.defaultRoute)
        let window = MainWindowController(
            model: model, navigation: navigation, activation: controller, frameAutosaveName: nil,
            content: Color.clear
        )
        var closes = 0
        window.onClose = { closes += 1 }
        let nsWindow = try #require(window.window)
        controller.windowWillOpen(nsWindow)
        #expect(controller.policy == .regular)
        window.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: nsWindow))
        #expect(controller.policy == .accessory)
        #expect(closes == 1)
    }
}

@Suite struct TerminationTests {
    typealias State = TerminationPolicy.State

    @Test func commandQClosesAnOpenWindowInsteadOfQuitting() {
        #expect(TerminationPolicy.decide(State(request: .commandQ, hasOpenWindow: true)) == .closeWindows)
        // Unsaved work stays with the window, which is only closed.
        #expect(TerminationPolicy.decide(State(
            request: .commandQ, hasOpenWindow: true, hasPendingRestores: true, unsavedOverrideName: "DELL U2723QE"
        )) == .closeWindows)
    }

    @Test func commandQQuitsWithNoWindowOpenOrFromThePanel() {
        #expect(TerminationPolicy.decide(State(request: .commandQ)) == .quit(asking: []))
        #expect(TerminationPolicy.decide(State(request: .commandQ, hasOpenWindow: true, isPanelKey: true)) == .quit(asking: []))
    }

    @Test(arguments: [TerminationRequest.explicit, .system])
    func quitResoluteQuitsEvenWithTheWindowOpen(_ request: TerminationRequest) {
        #expect(TerminationPolicy.decide(State(request: request, hasOpenWindow: true)) == .quit(asking: []))
    }

    @Test(arguments: [TerminationRequest.commandQ, .explicit, .system])
    func refusesDuringASwitchOrAWrite(_ request: TerminationRequest) {
        #expect(TerminationPolicy.decide(State(request: request, hasOpenWindow: true, isChangingMode: true)) == .refuse)
        #expect(TerminationPolicy.decide(State(request: request, isWritingOverride: true)) == .refuse)
    }

    @Test func asksAboutWhatQuittingWouldLoseInOrder() {
        #expect(TerminationPolicy.decide(State(request: .explicit, hasPendingRestores: true)) == .quit(asking: [.pendingRestores]))
        #expect(TerminationPolicy.decide(State(request: .explicit, unsavedOverrideName: "Studio"))
            == .quit(asking: [.unsavedCustomResolutions(displayName: "Studio")]))
        #expect(TerminationPolicy.decide(State(request: .system, hasPendingRestores: true, unsavedOverrideName: "Studio"))
            == .quit(asking: [.pendingRestores, .unsavedCustomResolutions(displayName: "Studio")]))
    }

    @Test func tellsQuitResoluteFromCommandQAndFromOtherApps() {
        let quitEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        let openEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(TerminationRequest(isExplicit: true, appleEvent: quitEvent) == .explicit)
        #expect(TerminationRequest(isExplicit: false, appleEvent: quitEvent) == .system)
        #expect(TerminationRequest(isExplicit: false, appleEvent: openEvent) == .commandQ)
        #expect(TerminationRequest(isExplicit: false, appleEvent: nil) == .commandQ)
    }
}

/// What an observation loop saw each time it ran.
@MainActor
final class SeenValues {
    var values: [Int?] = []
}

@MainActor
@Suite struct ObservationLoopTests {
    /// The Keep/Revert question runs modally, often inside main-actor work (a menu choice);
    /// the menu bar icon must still turn orange and count down while it is up.
    @Test func followsATrialWhileItsQuestionIsUp() {
        let seen = SeenValues()
        let prompt = TrialPrompt(length: { 15 }) { _ in
            // As a modal alert does, turn the run loop while the question is up.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            return false
        }
        let loop = ObservationLoop { seen.values.append(prompt.secondsLeft()) }
        #expect(prompt.decide() == .revert)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        loop.cancel()
        #expect(seen.values.first == .some(nil))
        #expect(seen.values.contains(15))
        #expect(seen.values.last == .some(nil))
    }

    @Test func stopsWhenCancelled() {
        let seen = SeenValues()
        let fixture = PanelFixture()
        let loop = ObservationLoop { seen.values.append(fixture.count) }
        loop.cancel()
        fixture.count = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(seen.values == [1])
    }
}

@MainActor
@Suite struct StatusItemTests {
    @Test func showsTheMostUrgentState() {
        func resolve(trial: Int? = nil, waiting: Bool = false, open: Bool = false, resolution: String? = nil) -> StatusItemState {
            StatusItemState.resolve(trialSecondsLeft: trial, isWaiting: waiting, isPanelOpen: open, resolutionText: resolution)
        }
        #expect(resolve() == .normal)
        #expect(resolve(open: true) == .open)
        #expect(resolve(resolution: "1728 × 1117") == .resolution("1728 × 1117"))
        // The resolution stays while the panel hangs under the icon, which keeps its width.
        #expect(resolve(open: true, resolution: "1728 × 1117") == .resolution("1728 × 1117"))
        #expect(resolve(waiting: true, open: true, resolution: "1728 × 1117") == .waiting)
        #expect(resolve(trial: 12, waiting: true, open: true, resolution: "1728 × 1117") == .trial(secondsLeft: 12))
        #expect(resolve(trial: -1) == .trial(secondsLeft: 0))
    }

    @Test func countsDownInMinutesAndSeconds() {
        #expect(StatusItemState.countdownText(secondsLeft: 12) == "0:12")
        #expect(StatusItemState.countdownText(secondsLeft: 5) == "0:05")
        #expect(StatusItemState.countdownText(secondsLeft: 60) == "1:00")
        #expect(StatusItemState.countdownText(secondsLeft: 75) == "1:15")
        #expect(StatusItemState.countdownText(secondsLeft: -3) == "0:00")
    }

    @Test func saysWhatItShowsToVoiceOver() {
        #expect(StatusItemState.normal.accessibilityLabel == "Resolute")
        #expect(StatusItemState.open.accessibilityLabel == "Resolute")
        #expect(StatusItemState.trial(secondsLeft: 12).accessibilityLabel == "Resolute, hidden mode on trial, 12 seconds left")
        #expect(StatusItemState.trial(secondsLeft: 1).accessibilityLabel == "Resolute, hidden mode on trial, 1 second left")
        #expect(StatusItemState.resolution("1728 × 1117").accessibilityLabel == "Resolute, 1728 by 1117")
        #expect(StatusItemState.waiting.accessibilityLabel == "Resolute, a revert is waiting for its display")
        #expect(StatusItemState.trial(secondsLeft: 12).toolTip == "Hidden mode on trial, 12 s left")
    }

    @Test func drawsATemplateAtRestAndColorsDuringATrialOrAWait() {
        let height = NSStatusBar.system.thickness
        let resting = StatusItemState.normal.image(height: height)
        let trial = StatusItemState.trial(secondsLeft: 12).image(height: height)
        let waiting = StatusItemState.waiting.image(height: height)
        #expect(resting.nsImage().isTemplate)
        #expect(StatusItemState.open.image(height: height).content == .symbol)
        #expect(StatusItemState.resolution("1728 × 1117").image(height: height).nsImage().isTemplate)
        #expect(!trial.nsImage().isTemplate)
        #expect(!waiting.nsImage().isTemplate)
        #expect(resting.size.width > 0)
        #expect(trial.size.width > resting.size.width)
        #expect(trial.size.height <= height)
        #expect(StatusItemState.resolution("1728 × 1117").image(height: height).text == "1728 × 1117")
        #expect(trial.text == "0:12")
    }

    /// ⌥ held while clicking the icon shows details; the panel's shortcut (⌃⌥R by default)
    /// holds ⌥ itself, so a key press never does.
    @Test func showsDetailsOnlyForAClickWithOption() throws {
        #expect(StatusItemClick.showsDetails(type: .leftMouseDown, modifierFlags: [.option]))
        #expect(StatusItemClick.showsDetails(type: .leftMouseUp, modifierFlags: [.option, .command]))
        #expect(!StatusItemClick.showsDetails(type: .leftMouseDown, modifierFlags: []))
        #expect(!StatusItemClick.showsDetails(type: .keyDown, modifierFlags: [.control, .option]))
        #expect(!StatusItemClick.showsDetails(type: .systemDefined, modifierFlags: [.control, .option]))
        #expect(!StatusItemClick.showsDetails(for: nil))
        let optionClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        #expect(StatusItemClick.showsDetails(for: optionClick))
    }

    @Test func opensTheClassicMenuForARightClickOrAControlClick() throws {
        #expect(StatusItemClick(type: .leftMouseDown, modifierFlags: []) == .panel)
        #expect(StatusItemClick(type: .leftMouseUp, modifierFlags: [.option]) == .panel)
        #expect(StatusItemClick(type: .leftMouseDown, modifierFlags: [.control]) == .classicMenu)
        #expect(StatusItemClick(type: .rightMouseDown, modifierFlags: []) == .classicMenu)
        #expect(StatusItemClick(type: .rightMouseUp, modifierFlags: []) == .classicMenu)
        // A shortcut that opens the panel may hold Control; only clicks choose the menu.
        #expect(StatusItemClick(type: .keyDown, modifierFlags: [.control, .option]) == .panel)
        #expect(StatusItemClick(event: nil) == .panel)

        let rightClick = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        #expect(StatusItemClick(event: rightClick) == .classicMenu)
    }
}

@MainActor
@Suite struct PanelTests {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 948)
    let menuBarBottom: CGFloat = 948

    func item(midX: CGFloat) -> CGRect {
        CGRect(x: midX - 16, y: menuBarBottom, width: 32, height: 24)
    }

    @Test func hangsCenteredUnderTheIcon() {
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 340, height: 700), anchor: item(midX: 1000), visibleFrame: visible)
        #expect(frame == CGRect(x: 830, y: menuBarBottom - Metrics.Panel.menuBarGap - 700, width: 340, height: 700))
    }

    @Test func staysInsideTheScreen() {
        let right = PanelPlacement.frame(contentSize: CGSize(width: 340, height: 300), anchor: item(midX: 1490), visibleFrame: visible)
        #expect(right.maxX == visible.maxX - Metrics.Spacing.medium)
        let left = PanelPlacement.frame(contentSize: CGSize(width: 340, height: 300), anchor: item(midX: 20), visibleFrame: visible)
        #expect(left.minX == visible.minX + Metrics.Spacing.medium)
    }

    @Test func stopsAtTheBottomOfTheScreen() {
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 340, height: 2000), anchor: item(midX: 1000), visibleFrame: visible)
        #expect(frame.minY == visible.minY + Metrics.Spacing.medium)
        #expect(frame.maxY == menuBarBottom - Metrics.Panel.menuBarGap)
    }

    @Test func goesUnderTheMenuBarWhenItHides() {
        // With the menu bar hidden, the visible frame reaches the top of the screen.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let anchor = CGRect(x: 984, y: 958, width: 32, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 340, height: 400), anchor: anchor, visibleFrame: screen)
        #expect(frame.maxY == anchor.minY - Metrics.Panel.menuBarGap)
    }

    @Test func fitsItsContentAndFollowsItsChanges() throws {
        let rows = PanelFixture()
        let host = PanelHost(content: PanelFixtureView(fixture: rows))
        #expect(host.contentSize.width == Metrics.Panel.width)
        let screen = try #require(NSScreen.main)
        let anchor = CGRect(x: screen.visibleFrame.midX - 16, y: screen.visibleFrame.maxY - 200, width: 32, height: 24)
        host.position { PanelHost.Anchor(window: nil, frame: anchor, screen: screen) }
        #expect(host.panel.frame.width == Metrics.Panel.width)
        #expect(host.panel.frame.height == 40)
        #expect(host.panel.frame.maxY == anchor.minY - Metrics.Panel.menuBarGap)
        #expect(!host.panel.isVisible)

        rows.count = 3
        // SwiftUI takes up changes as the run loop turns, as it does in the app.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(host.panel.frame.height == 120)
        #expect(host.contentSize.height == 120)
        #expect(host.panel.frame.maxY == anchor.minY - Metrics.Panel.menuBarGap)
    }

    @Test func isAKeyableFloatingPanelThatLeavesTheFrontAppAlone() {
        let panel = StatusPanel()
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.isFloatingPanel)
        #expect(!panel.isOpaque)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canHide)
        var cancelled = false
        panel.onCancel = { cancelled = true }
        panel.cancelOperation(nil)
        #expect(cancelled)
    }

    @Test func closesOnEscape() throws {
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        ))
        let returnKey = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        #expect(PanelKeys.closes(escape))
        #expect(!PanelKeys.closes(returnKey))
    }
}

/// Rows of a fixed height, as many as `count` says.
@MainActor
@Observable
final class PanelFixture {
    var count = 1
}

struct PanelFixtureView: View {
    let fixture: PanelFixture

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<fixture.count, id: \.self) { _ in
                Color.clear.frame(height: 40)
            }
        }
    }
}

@MainActor
@Suite struct WindowTests {
    let model = AppModel(environment: .gallery())
    let navigation: WindowNavigation
    let controller: MainWindowController

    init() {
        navigation = WindowNavigation(route: model.defaultRoute)
        controller = MainWindowController(
            model: model, navigation: navigation, activation: ActivationPolicyController(apply: { _ in }),
            frameAutosaveName: nil, content: Color.clear
        )
    }

    @Test func opensAtTheDesignsSizeAndKeepsItsMinimum() throws {
        let window = try #require(controller.window)
        #expect(window.contentRect(forFrameRect: window.frame).size == Metrics.Window.defaultSize)
        window.setContentSize(NSSize(width: 500, height: 300))
        window.layoutIfNeeded()
        #expect(window.frame.size == Metrics.Window.minimumSize)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.toolbar != nil)
        #expect(window.toolbarStyle == .unified)
        #expect(!window.isRestorable)
        #expect(window.tabbingMode == .disallowed)
        #expect(!window.isVisible)
        #expect(!controller.isOpen)
    }

    @Test func titlesThePageInTheToolbar() throws {
        let window = try #require(controller.window)
        #expect(window.title == "Built-in Retina Display")
        #expect(window.subtitle == "1728 × 1117 · 120 Hz")

        controller.navigate(to: .presets)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(navigation.route == .presets)
        #expect(window.title == "Presets")
        #expect(window.subtitle == "")

        controller.navigate(to: .display(.id(FakeDisplayService.dellID), tab: .customResolutions))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(window.title == "DELL U2723QE")
        #expect(window.subtitle == "2560 × 1440 · 60 Hz")
        #expect(!window.isVisible)
    }
}

@MainActor
@Suite struct MainMenuLayoutTests {
    let model = AppModel(environment: .gallery())
    let shell = RecordingShell()

    func item(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == title }
    }

    @Test func hasTheDesignsMenus() {
        let menu = MainMenu.make()
        #expect(menu.items.map(\.title) == ["Resolute", "File", "Edit", "View", "Go", "Window", "Help"])
    }

    /// ⌘Q closes the window (TerminationPolicy); the Quit Resolute the menu shows always quits.
    @Test func quitResoluteIsControlOptionCommandQ() throws {
        let menu = MainMenu.make()
        let quit = try #require(item("Quit Resolute", in: menu))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == [.control, .option, .command])
        #expect(quit.action == #selector(MainMenuHandler.quitResolute(_:)))
        #expect(!quit.isHidden)

        let commandQ = try #require(menu.items.compactMap(\.submenu).flatMap(\.items).first {
            $0.action == #selector(NSApplication.terminate(_:))
        })
        #expect(commandQ.keyEquivalent == "q")
        #expect(commandQ.keyEquivalentModifierMask == [.command])
        #expect(commandQ.isHidden)
        #expect(commandQ.allowsKeyEquivalentWhenHidden)
    }

    @MainActor
    final class OpenedURLs {
        var urls: [URL] = []
    }

    @Test func performsResolutesItemsThroughTheModel() throws {
        model.shell = shell
        let opened = OpenedURLs()
        let handler = MainMenuHandler(model: model) { opened.urls.append($0) }
        let menu = MainMenu.make(handler: handler)
        let settings = try #require(item("Settings…", in: menu))
        #expect(settings.keyEquivalent == ",")
        #expect(settings.target === handler)
        handler.showSettings(settings)
        handler.showAbout(nil)
        handler.quitResolute(nil)
        handler.showHelp(nil)
        #expect(shell.windows == [.settings(.general), .settings(.about)])
        #expect(shell.quits == 1)
        #expect(opened.urls == [MainMenu.helpURL])
        #expect(MainMenu.helpURL.absoluteString == "https://github.com/omar-hanafy/Resolute#readme")
    }

    @Test func goesToEachDisplayPresetsAndHistory() throws {
        model.shell = shell
        let handler = MainMenuHandler(model: model)
        let go = NSMenu(title: "Go")
        let away = AppModel.OverrideTarget(key: OverrideKey(vendorID: 0x1E6D, productID: 0x5B11), name: "LG UltraFine 5K", hasOverride: true)
        MainMenu.fillGoMenu(go, displays: model.displays, notConnected: [away], handler: handler)
        #expect(go.items.map { $0.isSeparatorItem ? "---" : $0.title }
            == ["Built-in Retina Display", "DELL U2723QE", "LG UltraFine 5K", "---", "Presets", "History"])
        #expect(go.items.prefix(3).map(\.keyEquivalent) == ["1", "2", ""])

        for item in go.items where !item.isSeparatorItem {
            handler.go(item)
        }
        #expect(shell.windows == [
            .display(.id(FakeDisplayService.builtInID)), .display(.id(FakeDisplayService.dellID)),
            .display(.overrideKey(away.key)), .presets, .history,
        ])
    }

    @Test func fillsTheGoMenuWhenItOpens() {
        let handler = MainMenuHandler(model: model)
        let menu = MainMenu.make(handler: handler)
        let go = menu.items[4].submenu
        #expect(go?.delegate === handler)
        if let go { handler.menuNeedsUpdate(go) }
        #expect(go?.items.first?.title == "Built-in Retina Display")
    }
}

@MainActor
@Suite struct ClassicMenuTests {
    let service = FakeDisplayService()
    let shell = RecordingShell()
    let model: AppModel
    let menu: StatusMenuController

    init() {
        model = AppModel(environment: .gallery(service: service))
        model.shell = shell
        menu = StatusMenuController(model: model)
    }

    @Test func listsTheDisplaysWhenItOpens() {
        menu.menuNeedsUpdate(menu.menu)
        let titles = menu.menu.items.map(\.title)
        #expect(titles.contains("Built-in Retina Display"))
        #expect(titles.contains("DELL U2723QE"))
        #expect(titles.contains("Quit Resolute"))
    }

    @Test func sendsItsChoicesToTheModel() throws {
        menu.perform(.openCustomResolutions(displayID: FakeDisplayService.dellID))
        menu.perform(.openWindow)
        menu.perform(.openSettings)
        menu.perform(.quit)
        #expect(shell.windows == [
            .display(.id(FakeDisplayService.dellID), tab: .customResolutions),
            .display(.id(FakeDisplayService.builtInID)),
            .settings(.general),
        ])
        #expect(shell.quits == 1)

        let mode = try #require(FakeDisplayService.dell.modes.first { $0.width == 1600 })
        menu.perform(.applyMode(displayID: FakeDisplayService.dellID, modeID: mode.modeID, needsConfirmation: false))
        #expect(service.changes.map(\.modeID) == [mode.modeID])
        menu.perform(.setMirroring(true))
        #expect(service.mirroringRequests == [true])
    }

    /// A choice made in the menu for the DELL, after another monitor took its display ID.
    @Test func sendsAChoiceOnlyToTheDisplayItWasMadeFor() throws {
        menu.menuNeedsUpdate(menu.menu)
        let mode = try #require(FakeDisplayService.dell.modes.first { $0.width == 1600 })
        var other = FakeDisplayService.dell
        other.productID = 0x7777
        other.serialNumber = 0x9999
        service.set([FakeDisplayService.builtIn, other])
        menu.perform(.applyMode(displayID: FakeDisplayService.dellID, modeID: mode.modeID, needsConfirmation: false))
        #expect(service.changes.isEmpty)
    }

    @Test func dumpsTheSameMenuForDiagnostics() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "com.omarhanafy.Resolute.gallery") ?? .standard)
        let nodes = StatusMenuController.nodes(service: service, preferences: preferences, showsDetails: false)
        #expect(nodes == StatusMenuController.nodes(displays: service.displays(), preferences: preferences, showsDetails: false))
        #expect(nodes.contains(.header("DELL U2723QE")))
    }
}
