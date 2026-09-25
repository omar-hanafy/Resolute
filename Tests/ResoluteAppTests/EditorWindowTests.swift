import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The Custom Resolutions window, built headlessly: nothing here orders a window in.
@MainActor
@Suite struct EditorWindowTests {
    let display = Display(id: 5, name: "First", vendorID: 0x10AC, productID: 0x1111, currentModeID: nil, modes: [])
    var key: OverrideKey { OverrideKey(display: display) }

    func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ResoluteAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `resolutions` as the display's installed override, as another tool would.
    func install(_ resolutions: [ScaleResolution], under root: URL) throws {
        let url = OverrideLocations.staged(at: root).userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DisplayOverride(key: key, resolutions: resolutions).propertyListData().write(to: url)
    }

    func makeModel(root: URL) -> CustomResolutionsModel {
        let locations = OverrideLocations.staged(at: root)
        return CustomResolutionsModel(
            service: StubDisplays([display]),
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: ShellCommandRunner())
        )
    }

    /// The window becomes key when someone comes back to it, and after its sheets and
    /// alerts close: the override is read again then.
    @Test func readsTheOverrideAgainWhenTheWindowBecomesKey() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install([.standard(width: 2560, height: 1440)], under: root)
        let model = makeModel(root: root)
        let controller = CustomResolutionsWindowController(model: model, frameAutosaveName: nil)
        let window = try #require(controller.window)
        try install([.standard(width: 1280, height: 800)], under: root)

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(model.rows.map(\.entry) == [.standard(width: 1280, height: 800)])
        #expect(!window.isVisible)
    }
}
