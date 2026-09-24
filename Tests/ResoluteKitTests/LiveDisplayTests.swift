import Foundation
import Testing
@testable import ResoluteKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_TESTS"] == "1"), .serialized)
struct LiveDisplayTests {
    let service = SystemDisplayService()

    @Test func listsTheMainDisplay() throws {
        let main = try #require(service.displays().first { $0.isMain })
        #expect(!main.name.isEmpty)
        #expect(!main.modes.isEmpty)
        #expect(main.currentMode != nil)
        #expect(service.currentModeID(of: main.id) == main.currentModeID)
    }

    @Test func trustsTheSkyLightRecordsOnThisMac() throws {
        let main = try #require(service.displays().first { $0.isMain })
        #expect(main.privateModes == .trusted)
        #expect(main.modes.filter { $0.origin == .system }.allSatisfy { $0.privateIndex != nil })
    }

    @Test func switchesTheRefreshRateThroughCoreGraphicsAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        try service.apply(modeID: sibling.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(modeID: current.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    @Test func switchesTheRefreshRateThroughSkyLightAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        try service.apply(privateIndex: try #require(sibling.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(privateIndex: try #require(current.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    /// The main display, its current mode, and a mode with the same size at another refresh rate.
    private func refreshSibling() throws -> (Display, DisplayMode, DisplayMode) {
        let main = try #require(service.displays().first { $0.isMain })
        let current = try #require(main.currentMode)
        let sibling = try #require(main.modes.first {
            $0.origin == .system && $0.width == current.width && $0.height == current.height
                && $0.pixelWidth == current.pixelWidth && $0.refreshKey != current.refreshKey
        })
        return (main, current, sibling)
    }
}
