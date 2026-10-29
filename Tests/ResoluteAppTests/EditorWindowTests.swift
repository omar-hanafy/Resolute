import AppKit
import Foundation
import ResoluteDesign
import SwiftUI
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The Resolute window's display pages and the editor's own window, built headlessly:
/// nothing here orders a window in.
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

    /// 20 HiDPI entries with their 1× entries, as RDM writes them: 40 rows.
    var manyEntries: [ScaleResolution] {
        let scaled = (0..<20).map { ScaleResolution.hiDPI(width: 1280 + 64 * $0, height: 720 + 36 * $0, flags: .standard) }
        return scaled.compactMap { $0.pixelSize.map { .standard(width: $0.width, height: $0.height) } } + scaled
    }

    /// The narrowest the page can be laid out: as wide as the widest thing on it that can't
    /// narrow, such as a row of buttons that doesn't wrap.
    func narrowestWidth(of fixture: DisplayGalleryFixture, on target: DisplayTarget, tab: DisplayTab) -> CGFloat {
        let page = DisplayPage(model: fixture.model, editors: fixture.editors, target: target, tab: tab, scrolls: false) { _ in }
        return NSHostingController(rootView: page).sizeThatFits(in: CGSize(width: 1, height: 100_000)).width
    }

    /// The page's room in the window at its minimum size: the window less the sidebar.
    static let pageWidth = Metrics.Window.minimumSize.width - Metrics.Window.sidebarWidth

    /// Every tab of a display's page, with a long list of custom resolutions and unsaved
    /// changes, fits the page's width at the window's minimum size: the file's buttons wrap,
    /// and the page scrolls down.
    @Test(arguments: [DisplayTab.resolution, .customResolutions, .pictureAndName])
    func fitsTheWindowsWidth(tab: DisplayTab) throws {
        let fixture = DisplayGalleryFixture()
        let editor = fixture.editors.editor(for: OverrideKey(display: DisplayGalleryFixture.dell))
        for entry in manyEntries {
            _ = editor.add(entry)
        }
        #expect(editor.rows.count > 40)
        #expect(narrowestWidth(of: fixture, on: .id(DisplayGalleryFixture.dell.id), tab: tab) <= Self.pageWidth)
    }

    /// A display that is away, which has Add Resolution… among its file's buttons, and a
    /// standard display fit too.
    @Test(arguments: [DisplayTab.customResolutions, .pictureAndName])
    func fitsTheWindowsWidthForOtherDisplays(tab: DisplayTab) throws {
        let fixture = DisplayGalleryFixture(displays: [DisplayGalleryFixture.builtIn, DisplayGalleryFixture.asus])
        #expect(narrowestWidth(of: fixture, on: .overrideKey(DisplayGalleryFixture.lg.key), tab: tab) <= Self.pageWidth)
        #expect(narrowestWidth(of: fixture, on: .id(DisplayGalleryFixture.asus.id), tab: .resolution) <= Self.pageWidth)
    }

    /// The window holds the page at its minimum size without growing.
    @Test func showsThePageInTheWindowAtItsMinimumSize() throws {
        let fixture = DisplayGalleryFixture()
        let window = fixture.window(on: .display(.id(DisplayGalleryFixture.dell.id), tab: .customResolutions))
        window.setContentSize(Metrics.Window.minimumSize)
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        #expect(content.frame.size == Metrics.Window.minimumSize)
        #expect(!window.isVisible)
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
