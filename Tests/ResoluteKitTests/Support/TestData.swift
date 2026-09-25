import CoreGraphics
import Foundation
@testable import ResoluteKit

/// Modes captured from the built-in display of a MacBook Pro 16" (M2 Pro) on macOS 27.0
/// with `Scripts/capture-mode-fixture.swift`.
struct CapturedDisplay: Decodable {
    struct SystemMode: Decodable {
        let modeID: Int32
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Double
        let ioFlags: UInt32
    }

    let macOS: String
    let model: String
    let currentModeID: Int32
    let systemModes: [SystemMode]
    /// Raw private records in list order, hex encoded.
    let privateRecords: [String]

    static func load() throws -> CapturedDisplay {
        guard let url = Bundle.module.url(
            forResource: "m2pro-builtin-macos27", withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw FixtureError.missing
        }
        return try JSONDecoder().decode(CapturedDisplay.self, from: Data(contentsOf: url))
    }

    var records: [[UInt8]] { privateRecords.map(TestData.bytes(hex:)) }

    var modes: [DisplayMode] {
        systemModes.map {
            DisplayMode(
                modeID: $0.modeID, width: $0.width, height: $0.height,
                pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                refreshRate: $0.refreshRate, ioFlags: $0.ioFlags
            )
        }
    }

    /// The capture as a snapshot, with private indexes and bit depth filled in the way
    /// the live service does.
    func display(currentModeID: Int32? = nil) -> Display {
        Display(
            id: 1, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050,
            isBuiltin: true, isMain: true,
            currentModeID: currentModeID ?? self.currentModeID,
            modes: modes.map { mode in
                var mode = mode
                mode.privateIndex = mode.modeID
                mode.bitsPerSample = 10
                return mode
            },
            privateModes: .trusted
        )
    }
}

enum FixtureError: Error {
    case missing
}

enum TestData {
    static func bytes(hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }

    static func mode(
        _ id: Int32, _ width: Int, _ height: Int, scale: Int = 1, hz: Double = 60,
        flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system
    ) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height,
            pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, ioFlags: flags, origin: origin
        )
    }

    /// A 1080p monitor without HiDPI modes (60 and 50 Hz) and two hidden modes.
    static func fullHD(id: CGDirectDisplayID = 2, currentModeID: Int32 = 1) -> Display {
        Display(
            id: id, name: "Full HD Monitor", vendorID: 0x10AC, productID: 0x1234,
            currentModeID: currentModeID,
            modes: [
                mode(1, 1920, 1080, hz: 60, flags: 0x0200_0007),
                mode(2, 1920, 1080, hz: 50, flags: 0x0200_0003),
                mode(3, 1280, 720, hz: 60),
                mode(4, 1024, 768, hz: 60),
                mode(90, 1920, 1080, hz: 75, flags: 0x1, origin: .hidden),
                mode(91, 2560, 1440, hz: 30, flags: 0x1, origin: .hidden),
            ],
            privateModes: .trusted
        )
    }

    /// A 4K monitor: 1920×1080 HiDPI (default) and 2560×1440 HiDPI, plus 1× modes.
    static func uhd(id: CGDirectDisplayID = 3, currentModeID: Int32 = 10) -> Display {
        Display(
            id: id, name: "4K Monitor", vendorID: 0x1E6D, productID: 0x5B09,
            currentModeID: currentModeID,
            modes: [
                mode(10, 1920, 1080, scale: 2, hz: 60, flags: 0x7),
                mode(11, 1920, 1080, scale: 2, hz: 30),
                mode(12, 2560, 1440, scale: 2, hz: 60),
                mode(20, 3840, 2160, hz: 60, flags: 0x0200_0003),
                mode(21, 1920, 1080, hz: 60),
                mode(22, 2560, 1440, hz: 60),
            ],
            privateModes: .trusted
        )
    }
}

/// A display service that records what it is asked to do and can refuse chosen modes.
final class FakeDisplayService: DisplayControlling, @unchecked Sendable {
    struct Call: Equatable {
        var modeID: Int32
        var scope: ConfigurationScope
    }

    private let lock = NSLock()
    private var display: Display
    private let refusedModeIDs: Set<Int32>
    private let ignoredModeIDs: Set<Int32>
    private let reportsCurrentMode: Bool
    private var recorded: [Call] = []

    /// `refusing` modes fail with an error; `ignoring` modes report success but leave the
    /// display as it was, as SkyLight does. `reportsCurrentMode: false` makes
    /// `currentModeID(of:)` return nil, as CoreGraphics can for a hidden mode, while
    /// `displays()` still knows it.
    init(
        display: Display,
        refusing refusedModeIDs: Set<Int32> = [],
        ignoring ignoredModeIDs: Set<Int32> = [],
        reportsCurrentMode: Bool = true
    ) {
        self.display = display
        self.refusedModeIDs = refusedModeIDs
        self.ignoredModeIDs = ignoredModeIDs
        self.reportsCurrentMode = reportsCurrentMode
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func displays() -> [Display] {
        lock.withLock { [display] }
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock { reportsCurrentMode ? display.currentModeID : nil }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            guard !refusedModeIDs.contains(modeID) else {
                throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode")
            }
            recorded.append(Call(modeID: modeID, scope: scope))
            if !ignoredModeIDs.contains(modeID) { display.currentModeID = modeID }
        }
    }

    func setMirroring(_ enabled: Bool) throws {}
}
