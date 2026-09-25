import Foundation
import Testing
@testable import ResoluteKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_TESTS"] == "1"), .serialized)
struct LiveDisplayTests {
    let service = SystemDisplayService()

    @Test func listsTheSelectedDisplay() throws {
        let main = try selectedDisplay()
        #expect(!main.name.isEmpty)
        #expect(!main.modes.isEmpty)
        #expect(main.currentMode != nil)
        #expect(service.currentModeID(of: main.id) == main.currentModeID)
    }

    @Test func trustsTheSkyLightRecordsOnThisMac() throws {
        let main = try selectedDisplay()
        #expect(main.privateModes == .trusted)
        #expect(main.modes.filter { $0.origin == .system }.allSatisfy { $0.privateIndex != nil })
    }

    @Test func switchesTheRefreshRateThroughCoreGraphicsAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        defer { try? service.apply(modeID: current.modeID, to: main.id, scope: .app) }
        try service.apply(modeID: sibling.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(modeID: current.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    @Test func switchesTheRefreshRateThroughSkyLightAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        defer { try? service.apply(modeID: current.modeID, to: main.id, scope: .app) }
        try service.apply(privateIndex: try #require(sibling.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(privateIndex: try #require(current.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    /// A trial through the check hidden modes get (the display must report the mode within
    /// half a second before anyone is asked), then the previous mode is put back. This Mac
    /// has no hidden modes, so a listed refresh rate stands in; the resolution never changes.
    /// Everything is for this process only, so CoreGraphics undoes it when the tests end,
    /// even if they crash.
    @Test func triesARefreshRateTheWayHiddenModesAreTriedAndPutsItBack() throws {
        let (main, current, sibling) = try refreshSibling()
        defer {
            if service.currentModeID(of: main.id) != current.modeID {
                try? service.apply(modeID: current.modeID, to: main.id, scope: .app)
            }
        }
        var switcher = ModeSwitcher(service: service)
        switcher.verifiesListedModes = true
        switcher.trialScope = .app
        var shownWhenAsked: Int32?
        let outcome = try switcher.apply(modeID: sibling.modeID, to: main.id, trial: true) {
            shownWhenAsked = service.currentModeID(of: main.id)
            return .revert
        }
        #expect(shownWhenAsked == sibling.modeID)
        #expect(outcome == .reverted(to: current.modeID))
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    /// Optional physical scaling checks, e.g. RESOLUTE_LIVE_SCALES=2752x1152,2408x1008.
    /// Each trial returns before the next one, and only explicitly requested sizes run.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_SCALES"] != nil))
    func preservesRefreshAcrossRequestedScalesAndReverts() throws {
        let display = try selectedDisplay()
        let original = try #require(display.currentMode)
        try #require(!display.isInMirrorSet)
        let others = service.displays().filter { $0.id != display.id }
        let sizes = try #require(ProcessInfo.processInfo.environment["RESOLUTE_LIVE_SCALES"])
            .split(separator: ",").map(String.init)
        try #require(!sizes.isEmpty)
        defer { try? service.apply(modeID: original.modeID, to: display.id, scope: .app) }
        for size in sizes {
            let before = try selectedDisplay()
            let mode = try ModeQuery(resolution: size).resolve(on: before)
            try #require(mode.origin == .system)
            try #require(mode.refreshKey == original.refreshKey)
            if mode.modeID == original.modeID { continue }
            try trialAndRevert(mode, on: before)
            for other in others {
                try #require(service.currentModeID(of: other.id) == other.currentModeID)
            }
            print("LIVE_SCALE \(size): \(mode.pixelSizeText) backing, \(RefreshRate.format(mode.refreshRate)), restored \(original.modeID)")
        }
    }

    /// Opt in to one inspected hidden mode while keeping another working display.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_HIDDEN_MODE"] != nil))
    func triesAnActualHiddenModeAndReverts() throws {
        let display = try selectedDisplay()
        try #require(!display.isInMirrorSet)
        try #require(service.displays().contains { $0.id != display.id && !$0.isInMirrorSet })
        let text = try #require(ProcessInfo.processInfo.environment["RESOLUTE_LIVE_HIDDEN_MODE"])
        let modeID = try #require(Int32(text))
        let mode = try #require(display.modes.first { $0.modeID == modeID && $0.origin == .hidden })
        try trialAndRevert(mode, on: display)
        print("LIVE_HIDDEN \(mode.modeID): \(mode.sizeText), \(mode.pixelSizeText) backing, \(RefreshRate.format(mode.refreshRate)), reverted")
    }

    private func trialAndRevert(_ mode: DisplayMode, on display: Display) throws {
        let original = try #require(display.currentMode)
        defer { try? service.apply(modeID: original.modeID, to: display.id, scope: .app) }
        var switcher = ModeSwitcher(service: service)
        switcher.trialScope = .app
        switcher.verifiesListedModes = true
        var observed: DisplayMode?
        let outcome = try switcher.apply(modeID: mode.modeID, to: display.id, trial: true) {
            observed = service.displays().first { $0.id == display.id }?.currentMode
            return .revert
        }
        try #require(observed?.modeID == mode.modeID)
        try #require(observed.map(ModeSwitcher.ModeFingerprint.init) == ModeSwitcher.ModeFingerprint(mode))
        try #require(outcome == .reverted(to: original.modeID))
        try #require(service.currentModeID(of: display.id) == original.modeID)
    }

    /// Choose explicitly for external testing; never silently fall back to the main screen.
    private func selectedDisplay() throws -> Display {
        let selector = ProcessInfo.processInfo.environment["RESOLUTE_LIVE_DISPLAY"] ?? "main"
        return try DisplaySelector(selector).resolve(in: service.displays())
    }

    /// The selected display, its current mode, and the nearest alternate refresh rate.
    private func refreshSibling() throws -> (Display, DisplayMode, DisplayMode) {
        let main = try selectedDisplay()
        let current = try #require(main.currentMode)
        let sibling = try #require(main.modes.filter {
            $0.origin == .system && $0.width == current.width && $0.height == current.height
                && $0.pixelWidth == current.pixelWidth && $0.pixelHeight == current.pixelHeight
                && $0.bitsPerSample == current.bitsPerSample && $0.refreshKey != current.refreshKey
        }.min { abs($0.refreshRate - current.refreshRate) < abs($1.refreshRate - current.refreshRate) })
        return (main, current, sibling)
    }
}
