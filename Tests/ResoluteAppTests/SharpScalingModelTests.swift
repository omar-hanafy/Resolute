import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Runs no script: fails as the installer would for a cancelled password prompt, a file
/// that changed, or another command holding the overrides.
struct FailingRunner: CommandRunning {
    var error: ResoluteError

    func run(_ script: String) async throws {
        throw error
    }
}

/// Sharp Scaling in the app, on the sample built-in display and ASUS PA278QV, with the
/// override files in a staged folder of each test's own. Writes run the installer's real
/// scripts in that folder, or a runner that fails, never with administrator rights.
@MainActor
@Suite struct SharpScalingModelTests {
    let scratch = ScratchDefaults()
    let preferences: Preferences
    let errors = ShownErrors()
    let shell = RecordingShell()
    let root: URL
    let service: FakeDisplayService
    let model: AppModel

    static let native = SharpSize(width: 2560, height: 1440)
    static let sizes = SharpScalingGallery.designSizes
    static let asus = SampleDisplays.asusPA278QV.display
    static let builtIn = SampleDisplays.builtInRetina.display

    var sharp: SharpScalingModel { model.sharpScaling }

    init() throws {
        preferences = Preferences(defaults: scratch.defaults)
        root = FileManager.default.temporaryDirectory
            .appending(path: "ResoluteSharpScalingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        service = FakeDisplayService(displays: [Self.builtIn, Self.asus])
        model = Self.makeModel(service: service, preferences: preferences, errors: errors, root: root)
        model.shell = shell
    }

    static func makeModel(
        service: FakeDisplayService, preferences: Preferences, errors: ShownErrors, root: URL, answers: TrialAnswers = TrialAnswers()
    ) -> AppModel {
        let model = AppModelTests.makeModel(service: service, preferences: preferences, answers: answers, errors: errors, overridesRoot: root)
        model.sharpScaling.drawingLimit = DrawingLimit(width: 6144)
        // The staged files are saved after this Mac started; only a reconnect counts.
        model.sharpScaling.systemStart = nil
        model.sharpScaling.reload()
        return model
    }

    /// The display as the app model has it now.
    func asus() throws -> Display {
        try #require(model.displays.first { $0.id == Self.asus.id })
    }

    /// Writes the design's sizes as the ASUS's override, as setup does.
    func stageSetup(sizes: [SharpSize] = sizes, switchTo: SharpSize? = nil, saved: Date = Date().addingTimeInterval(-60)) throws {
        let key = OverrideKey(display: Self.asus)
        let file = try OverrideStore(locations: .staged(at: root)).editableFile(for: key)
        let setup = try SharpScalingSetup(file: file, sizes: sizes, offered: [], switchTo: switchTo, now: saved)
        let url = OverrideLocations.staged(at: root).userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try setup.override.propertyListData().write(to: url)
        sharp.reload()
    }

    /// Unplugs the ASUS and plugs it back in, offering the sharp modes for `offered`.
    func reconnect(offering offered: [SharpSize], current: Int32? = nil) {
        service.set([Self.builtIn])
        model.displaysDidChange()
        var display = SharpScalingGallery.withSharpModes(Self.asus, sizes: offered)
        if let current { display.currentModeID = current }
        service.set([Self.builtIn, display])
        model.displaysDidChange()
    }

    var installedFile: URL {
        OverrideLocations.staged(at: root).userFile(for: OverrideKey(display: Self.asus))
    }

    // MARK: - The offer

    @Test func offersSharpScalingOnlyToAStandardDisplayWithoutIt() throws {
        let offer = try #require(sharp.offer(for: asus()))
        #expect(offer == SharpScalingModel.Offer(
            title: "Sharper text on this display",
            message: "Add Retina-style sizes, from Larger Text to More Space, like a 5K display.",
            actionTitle: "Set Up Sharp Scaling…"
        ))
        #expect(sharp.offer(for: Self.builtIn) == nil)
        #expect(sharp.stage(for: Self.builtIn) == nil)
        guard case .off(let plan)? = sharp.stage(for: try asus()) else {
            Issue.record("expected the page before setup")
            return
        }
        #expect(plan.sizes == Self.sizes)
        #expect(sharp.placement(for: try asus()) == .section)
        #expect(!sharp.isSharp(try asus()))
    }

    @Test func closingTheOfferHidesItForThatDisplayFromNowOn() throws {
        sharp.dismissOffer(for: try asus())
        #expect(sharp.offer(for: try asus()) == nil)
        #expect(preferences.dismissedSharpScalingOffers == [OverrideKey(display: Self.asus).relativePath])
        // The page still offers setup; only the panel's offer is gone.
        #expect(sharp.plan(for: try asus()) != nil)
        let relaunched = Self.makeModel(service: service, preferences: preferences, errors: errors, root: root)
        #expect(relaunched.sharpScaling.offer(for: try asus()) == nil)
    }

    @Test func setUpOpensTheDisplaysPageWithTheSheet() throws {
        sharp.startSetup(for: try asus())
        #expect(shell.windows == [.display(.id(Self.asus.id), tab: .resolution)])
        #expect(sharp.setupRequest == Self.asus.id)
    }

    /// Set Up Sharp Scaling… while a countdown is up opens nothing, and leaves no request
    /// that would open the sheet unasked on a later visit.
    @Test func setUpDoesNothingWhileACountdownIsUp() throws {
        let answers = TrialAnswers()
        let model = Self.makeModel(service: service, preferences: preferences, errors: errors, root: root, answers: answers)
        model.shell = shell
        let asus = try asus()
        answers.whileAsking = { model.sharpScaling.startSetup(for: asus) }
        let builtIn = try #require(model.displays.first { $0.id == Self.builtIn.id })
        let other = try #require(builtIn.modes.first { $0.modeID != builtIn.currentModeID })
        model.apply(modeID: other.modeID, to: builtIn.id, needsConfirmation: true)
        #expect(model.sharpScaling.setupRequest == nil)
        #expect(shell.windows.isEmpty)
    }

    @Test func offersNothingOnceSetUp() throws {
        try stageSetup()
        #expect(sharp.offer(for: try asus()) == nil)
        #expect(sharp.plan(for: try asus()) == nil)
    }

    // MARK: - States

    @Test func waitsForAReconnectThenIsReady() throws {
        try stageSetup()
        guard case .waiting(let status)? = sharp.stage(for: try asus()) else {
            Issue.record("expected waiting")
            return
        }
        #expect(status.saved == Self.sizes)
        #expect(sharp.headerBadge(for: try asus()) == "Sharp Scaling saved")
        #expect(sharp.banner(for: try asus())?.text.title == "Reconnect ASUS PA278QV to finish")

        reconnect(offering: Self.sizes)
        guard case .ready? = sharp.stage(for: try asus()) else {
            Issue.record("expected ready")
            return
        }
        #expect(sharp.placement(for: try asus()) == .row)
        #expect(sharp.headerBadge(for: try asus()) == "Sharp Scaling")
        // Still at 1×: no switch was asked for, so the banner offers the sharp version.
        #expect(!sharp.isSharp(try asus()))
        let banner = try #require(sharp.banner(for: try asus()))
        #expect(banner.text.message == "macOS accepted all 5 sizes. ASUS PA278QV still uses 2560 × 1440 at 1×.")
        #expect(banner.action == .useSharpVersion)
        #expect(service.changes.isEmpty)
    }

    /// A mode change on a display that stayed connected is no reconnect: macOS hasn't read
    /// the file, so a size it doesn't offer yet isn't skipped.
    @Test func keepsWaitingThroughAChangeThatIsNoReconnect() throws {
        try stageSetup()
        try service.apply(modeID: 4, to: Self.asus.id, scope: .session)
        model.displaysDidChange()
        guard case .waiting? = sharp.stage(for: try asus()) else {
            Issue.record("expected waiting")
            return
        }
    }

    @Test func namesTheSizesMacOSSkippedAfterTheReconnect() throws {
        try stageSetup()
        reconnect(offering: Array(Self.sizes.dropLast()))
        guard case .partial(let status)? = sharp.stage(for: try asus()) else {
            Issue.record("expected partial")
            return
        }
        #expect(status.skipped == [Self.native])
        let banner = try #require(sharp.banner(for: try asus()))
        #expect(banner.text.title == "macOS added 4 of 5 sizes")
        #expect(banner.action == .removeSkippedSizes)
        #expect(banner.tone == .warning)
    }

    @Test func isSharpOnlyInASizeSharpScalingAdded() throws {
        try stageSetup()
        reconnect(offering: Self.sizes)
        let display = try asus()
        let sharpNative = try #require(display.modes.first { Self.native.isDrawn(by: $0) && $0.refreshRate == 75 })
        model.apply(sharpNative, to: display, from: .window)
        model.displaysDidChange()
        #expect(sharp.isSharp(try asus()))
        let oneX = try #require(display.modes.first { $0.modeID == 4 })
        model.apply(oneX, to: try asus(), from: .window)
        #expect(!sharp.isSharp(try asus()))
    }

    // MARK: - The switch after the reconnect

    @Test func switchesToTheSharpSizeOnceAfterTheReconnect() throws {
        try stageSetup(switchTo: Self.native)
        #expect(service.changes.isEmpty)
        reconnect(offering: Self.sizes)

        let display = try asus()
        let sharpNative = try #require(display.modes.first { Self.native.isDrawn(by: $0) && $0.refreshRate == 75 })
        #expect(service.changes.map(\.modeID) == [sharpNative.modeID])
        #expect(sharp.isSharp(display))
        let activity = try #require(sharp.activity)
        #expect(activity.title == "ASUS PA278QV → 2560 × 1440 sharp")
        #expect(activity.detail(now: activity.date) == "Sharp Scaling is ready · just now")
        #expect(activity.symbol == .sparkles)
        #expect(sharp.banner(for: display)?.text.message
            == "macOS accepted all 5 sizes, and ASUS PA278QV now uses the sharp 2560 × 1440. System Settings › Displays lists the same sizes.")
        #expect(model.historyEntries.count == 1)

        // The person goes back to 1×; another reconnect doesn't switch again.
        let oneX = try #require(display.modes.first { $0.modeID == 1 })
        model.apply(oneX, to: display, from: .window)
        model.displaysDidChange()
        #expect(sharp.activity == nil)
        reconnect(offering: Self.sizes, current: 1)
        #expect(service.changes.map(\.modeID) == [sharpNative.modeID, 1])
    }

    /// The ASUS reconnects while a countdown is up on the built-in display, when the
    /// coordinator turns switches away: the switch is made once that countdown is over,
    /// rather than marked done and lost.
    @Test func switchesOnceTheCountdownUpWhenItCameDueIsOver() throws {
        let answers = TrialAnswers()
        let model = Self.makeModel(service: service, preferences: preferences, errors: errors, root: root, answers: answers)
        try stageSetup(switchTo: Self.native)
        model.sharpScaling.reload()
        let reconnected = SharpScalingGallery.withSharpModes(Self.asus, sizes: Self.sizes)
        let service = service
        answers.whileAsking = {
            service.set([Self.builtIn])
            model.displaysDidChange()
            service.set([Self.builtIn, reconnected])
            model.displaysDidChange()
        }
        let builtIn = try #require(model.displays.first { $0.id == Self.builtIn.id })
        let other = try #require(builtIn.modes.first { $0.modeID != builtIn.currentModeID })
        model.apply(modeID: other.modeID, to: builtIn.id, needsConfirmation: true)
        #expect(!service.changes.contains { $0.displayID == Self.asus.id })

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let asus = try #require(model.displays.first { $0.id == Self.asus.id })
        let sharpNative = try #require(asus.modes.first { Self.native.isDrawn(by: $0) && $0.refreshRate == 75 })
        #expect(service.changes.filter { $0.displayID == Self.asus.id }.map(\.modeID) == [sharpNative.modeID])
        #expect(model.sharpScaling.isSharp(asus))
    }

    @Test func undoGoesBackToTheModeBeforeTheSwitch() throws {
        try stageSetup(switchTo: Self.native)
        reconnect(offering: Self.sizes)
        #expect(sharp.activity != nil)
        sharp.undoActivity()
        #expect(try asus().currentModeID == 1)
        #expect(sharp.activity == nil)
        #expect(!sharp.isSharp(try asus()))
    }

    @Test func switchesToTheNearestSizeMacOSOffersWhenItSkippedTheOneAskedFor() throws {
        try stageSetup(switchTo: Self.native)
        reconnect(offering: Array(Self.sizes.dropLast()))
        let current = try #require(try asus().currentMode)
        #expect(current.isHiDPI)
        #expect(SharpSize(current) == SharpSize(width: 2304, height: 1296))
        #expect(current.refreshRate == 75)
    }

    @Test func remembersEachSetupItSwitchedFor() {
        let key = OverrideKey(display: Self.asus)
        let saved = Date(timeIntervalSince1970: 1_790_000_000)
        let log = SharpScalingSwitchLog(defaults: scratch.defaults)
        #expect(!log.hasSwitched(key, saved: saved))
        log.markSwitched(key, saved: saved)
        // Read back as a property list keeps it: to the second.
        #expect(SharpScalingSwitchLog(defaults: scratch.defaults).hasSwitched(key, saved: saved.addingTimeInterval(0.4)))
        #expect(!SharpScalingSwitchLog(defaults: scratch.defaults).hasSwitched(key, saved: saved.addingTimeInterval(60)))
    }

    // MARK: - Writing

    @Test func addWritesTheSizesThroughTheInstaller() async throws {
        sharp.setupRequest = Self.asus.id
        let written = await sharp.turnOn(for: try asus(), sizes: Self.sizes, switchTo: Self.native)
        #expect(written)
        #expect(errors.titles.isEmpty)
        #expect(sharp.setupRequest == nil)
        #expect(sharp.working == nil)
        let installed = try #require(try OverrideStore(locations: .staged(at: root)).installedOverride(for: OverrideKey(display: Self.asus)))
        let record = try #require(try SharpScalingRecord(in: installed))
        #expect(record.sizes == Self.sizes)
        #expect(record.switchTo == Self.native)
        guard case .waiting? = sharp.stage(for: try asus()) else {
            Issue.record("expected waiting")
            return
        }
    }

    /// One administrator prompt at a time: nothing is written while the window's editors
    /// save an override, and the alert says why, as the editors' notice does.
    @Test func writesNothingWhileTheWindowSavesAnOverride() async throws {
        sharp.isEditorWriting = { true }
        let written = await sharp.turnOn(for: try asus(), sizes: Self.sizes, switchTo: Self.native)
        #expect(!written)
        #expect(!FileManager.default.fileExists(atPath: installedFile.path(percentEncoded: false)))
        #expect(errors.titles == ["Sharp Scaling could not be set up"])
        #expect(errors.messages == ["Another override is being written. Try again once it has finished."])
    }

    /// While one display's setup waits for the administrator password, another display's
    /// change writes nothing, and says why.
    @Test func changesNoOtherDisplayWhileOneSetupIsWritten() async throws {
        let gate = Gate()
        sharp.installer = OverrideInstaller(locations: .staged(at: root), runner: GatedRunner(gate: gate))
        let asus = try asus()
        let builtIn = try #require(model.displays.first { $0.id == Self.builtIn.id })
        let sharp = sharp
        let writing = Task { await sharp.turnOn(for: asus, sizes: Self.sizes, switchTo: nil) }
        for _ in 0..<1000 where sharp.working == nil { await Task.yield() }
        #expect(sharp.working == Self.asus.id)

        #expect(!(await sharp.turnOff(for: builtIn)))
        #expect(errors.titles == ["Sharp Scaling could not be removed"])
        #expect(errors.messages == ["Another override is being written. Try again once it has finished."])

        await gate.open()
        #expect(await writing.value)
    }

    /// The other way round: while Sharp Scaling writes, behind the administrator password,
    /// the window's editors save nothing, and quitting, which asks them, is refused.
    @Test func holdsTheWindowsSavesWhileItWrites() async throws {
        let gate = Gate()
        let locations = OverrideLocations.staged(at: root)
        sharp.installer = OverrideInstaller(locations: locations, runner: GatedRunner(gate: gate))
        let editors = DisplayEditors(
            model: model, store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: ShellCommandRunner()), icons: DisplayEditorsTests.everyIcon
        )
        let editor = editors.editor(for: OverrideKey(display: Self.builtIn))
        #expect(editor.add(.hiDPI(width: 1600, height: 900, flags: .standard)) == nil)
        let asus = try asus()
        let sharp = sharp
        let writing = Task { await sharp.turnOn(for: asus, sizes: Self.sizes, switchTo: nil) }
        for _ in 0..<1000 where sharp.working == nil { await Task.yield() }
        #expect(sharp.working == Self.asus.id)
        #expect(editors.isWorking)
        await editors.save(editor)
        #expect(editor.hasChanges)

        await gate.open()
        #expect(await writing.value)
        #expect(!editors.isWorking)
    }

    @Test func undoSetupPutsBackTheFileFromBefore() async throws {
        _ = await sharp.turnOn(for: try asus(), sizes: Self.sizes, switchTo: nil)
        #expect(FileManager.default.fileExists(atPath: installedFile.path(percentEncoded: false)))
        let removed = await sharp.turnOff(for: try asus())
        #expect(removed)
        // There was no file before Sharp Scaling.
        #expect(!FileManager.default.fileExists(atPath: installedFile.path(percentEncoded: false)))
        guard case .off? = sharp.stage(for: try asus()) else {
            Issue.record("expected off")
            return
        }
        // The sizes were never in use, so there is nothing to wait for.
        #expect(sharp.banner(for: try asus()) == nil)
    }

    @Test func removingSizesInUseSaysTheyLastUntilTheReconnect() async throws {
        try stageSetup()
        reconnect(offering: Self.sizes)
        #expect(await sharp.turnOff(for: try asus()))
        #expect(sharp.banner(for: try asus())?.text.title == "Sharp Scaling is removed")
        #expect(sharp.offer(for: try asus()) == nil)
        reconnect(offering: [])
        #expect(sharp.banner(for: try asus()) == nil)
        #expect(sharp.offer(for: try asus()) != nil)
    }

    @Test func removeSkippedSizeKeepsTheSizesMacOSOffers() async throws {
        try stageSetup()
        reconnect(offering: Array(Self.sizes.dropLast()))
        #expect(await sharp.removeSkippedSizes(on: try asus()))
        guard case .ready(let status)? = sharp.stage(for: try asus()) else {
            Issue.record("expected ready")
            return
        }
        #expect(status.saved == Array(Self.sizes.dropLast()))
    }

    @Test func aCancelledPasswordPromptIsNoError() async throws {
        sharp.installer = OverrideInstaller(locations: .staged(at: root), runner: FailingRunner(error: .cancelled))
        sharp.setupRequest = Self.asus.id
        let written = await sharp.turnOn(for: try asus(), sizes: Self.sizes, switchTo: nil)
        #expect(!written)
        #expect(errors.titles.isEmpty)
        // The sheet stays up to try again.
        #expect(sharp.setupRequest == Self.asus.id)
        #expect(sharp.plan(for: try asus()) != nil)
    }

    @Test(arguments: [ResoluteError.overrideChanged(path: "x"), .overridesBusy, .commandFailed(status: 1, message: "no")])
    func showsWhyTheSizesWereNotWritten(error: ResoluteError) async throws {
        sharp.installer = OverrideInstaller(locations: .staged(at: root), runner: FailingRunner(error: error))
        #expect(await !sharp.turnOn(for: try asus(), sizes: Self.sizes, switchTo: nil))
        #expect(errors.titles == ["Sharp Scaling could not be set up"])
        #expect(sharp.working == nil)
    }
}
