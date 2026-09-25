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

    // MARK: - Layout

    static let defaultSize = CGSize(width: 860, height: 560)
    static let minimumSize = CGSize(width: 780, height: 500)

    /// 20 HiDPI entries with their 1× entries, as RDM writes them: 40 rows.
    var manyEntries: [ScaleResolution] {
        let scaled = (0..<20).map { ScaleResolution.hiDPI(width: 1280 + 64 * $0, height: 720 + 36 * $0, flags: .standard) }
        return scaled.compactMap { $0.pixelSize.map { .standard(width: $0.width, height: $0.height) } } + scaled
    }

    /// Views that stick out of `bounds`, in window coordinates. What scrolls inside a clip
    /// view may be taller than the window, and views without an area show nothing.
    func overflowingViews(in view: NSView, bounds: NSRect) -> [String] {
        view.subviews.filter { !$0.isHidden }.flatMap { subview -> [String] in
            let frame = subview.convert(subview.bounds, to: nil)
            var found: [String] = []
            if frame.width > 0, frame.height > 0, !bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                found.append("\(type(of: subview)) at \(frame)")
            }
            if !(subview is NSClipView) {
                found += overflowingViews(in: subview, bounds: bounds)
            }
            return found
        }
    }

    /// Lays the editor out in a window of `size` that is never ordered in, and returns the
    /// views that do not fit in it.
    func overflow(of model: CustomResolutionsModel, at size: CGSize) throws -> [String] {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: CustomResolutionsView(model: model))
        window.setContentSize(size)
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        #expect(!window.isVisible)
        #expect(content.frame.size == size)
        return overflowingViews(in: content, bounds: content.convert(content.bounds, to: nil))
    }

    /// 0.1's NavigationSplitView sized itself to the table's ideal height in an NSWindow
    /// and pushed the editor's controls out of it. With many rows, and with the banner and
    /// the note about 1× entries showing, the editor fits the window's default size and its
    /// minimum, and only the table scrolls.
    @Test(arguments: [false, true])
    func fitsTheWindowWithManyRows(showingNotes: Bool) throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install(manyEntries, under: root)
        let model = makeModel(root: root)
        #expect(model.rows.count == 40)
        if showingNotes {
            model.selectedEntries = [manyEntries[0]]
            model.removeSelection()
            try install(Array(manyEntries.dropLast()), under: root)
            model.refresh()
            #expect(model.unpairedNote != nil)
            #expect(model.changedOnDisk)
        }

        let controller = NSHostingController(rootView: CustomResolutionsView(model: model))
        #expect(controller.sizeThatFits(in: Self.defaultSize) == Self.defaultSize)
        #expect(controller.sizeThatFits(in: .zero) == Self.minimumSize)
        for size in [Self.defaultSize, Self.minimumSize] {
            let views = try overflow(of: model, at: size)
            #expect(views.isEmpty, "At \(size.width) × \(size.height) these stick out of the window: \(views)")
        }
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
