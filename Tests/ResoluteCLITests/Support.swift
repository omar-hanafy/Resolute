import ArgumentParser
import CoreGraphics
import Foundation
import ResoluteKit
@testable import resolute

/// Displays for command tests. Mode changes and mirroring are recorded and reflected in
/// later snapshots, like the real system.
final class FakeDisplays: DisplayControlling, @unchecked Sendable {
    struct Change: Equatable {
        var displayID: CGDirectDisplayID
        var modeID: Int32
        var scope: ConfigurationScope
    }

    private let lock = NSLock()
    private var list: [Display]
    private var recorded: [Change] = []
    private var mirroring: [Bool] = []
    private let ignoredModeIDs: Set<Int32>
    private let hidesHiddenCurrentMode: Bool

    /// `ignoring` modes report success but change nothing, as SkyLight does for a mode the
    /// display refuses. `hidesHiddenCurrentMode` makes `currentModeID(of:)` return nil while
    /// a hidden mode is in use, as CoreGraphics does.
    init(_ displays: [Display], ignoring: Set<Int32> = [], hidesHiddenCurrentMode: Bool = false) {
        list = displays
        ignoredModeIDs = ignoring
        self.hidesHiddenCurrentMode = hidesHiddenCurrentMode
    }

    var changes: [Change] { lock.withLock { recorded } }
    var mirroringCalls: [Bool] { lock.withLock { mirroring } }

    func displays() -> [Display] { lock.withLock { list } }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock {
            guard let display = list.first(where: { $0.id == displayID }) else { return nil }
            if hidesHiddenCurrentMode, display.currentMode?.origin == .hidden { return nil }
            return display.currentModeID
        }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            guard let index = list.firstIndex(where: { $0.id == displayID }),
                  list[index].modes.contains(where: { $0.modeID == modeID })
            else { throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: []) }
            recorded.append(Change(displayID: displayID, modeID: modeID, scope: scope))
            if !ignoredModeIDs.contains(modeID) { list[index].currentModeID = modeID }
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        lock.withLock {
            mirroring.append(enabled)
            for index in list.indices { list[index].isInMirrorSet = enabled }
        }
    }
}

enum Sample {
    static func mode(
        _ id: Int32, _ width: Int, _ height: Int, scale: Int = 2, hz: Double = 120,
        flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system
    ) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, bitsPerSample: 10, ioFlags: flags, origin: origin
        )
    }

    /// Like a 16-inch MacBook Pro panel, at 1728 × 1117 HiDPI and 120 Hz.
    static let builtIn = Display(
        id: 1, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050,
        isBuiltin: true, isMain: true, currentModeID: 54,
        modes: [
            mode(54, 1728, 1117, flags: 0x0200_0007), mode(55, 1728, 1117, hz: 60),
            mode(42, 1496, 967), mode(43, 1496, 967, hz: 60),
            mode(126, 3456, 2234, scale: 1, flags: 0x0200_0003), mode(127, 3456, 2234, scale: 1, hz: 60),
        ],
        privateModes: .trusted
    )

    /// A 1080p monitor with two hidden modes.
    static let monitor = Display(
        id: 2, name: "DELL P2419H", vendorID: 0x10AC, productID: 0xA0C4, currentModeID: 1,
        modes: [
            mode(1, 1920, 1080, scale: 1, hz: 60, flags: 0x0200_0007), mode(2, 1920, 1080, scale: 1, hz: 50),
            mode(3, 1280, 720, scale: 1, hz: 60),
            mode(90, 1920, 1080, scale: 1, hz: 75, flags: 0x1, origin: .hidden),
            mode(91, 2560, 1440, scale: 1, hz: 30, flags: 0x1, origin: .hidden),
        ],
        privateModes: .trusted
    )
}

/// What a command printed.
final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private var outputLines: [String] = []
    private var errorLines: [String] = []

    var output: String { lock.withLock { outputLines.joined(separator: "\n") } }
    var errors: String { lock.withLock { errorLines.joined(separator: "\n") } }

    func context(service: any DisplayControlling, isRoot: Bool, decision: ModeSwitcher.Decision) -> CommandContext {
        CommandContext(
            service: service,
            write: { [self] line in lock.withLock { outputLines.append(line) } },
            writeError: { [self] line in lock.withLock { errorLines.append(line) } },
            confirmHiddenMode: { decision },
            isRoot: isRoot
        )
    }
}

/// Parses `arguments` as a shell passes them and runs the command against `service`.
@discardableResult
func resolute(
    _ arguments: [String],
    service: any DisplayControlling = FakeDisplays([Sample.builtIn]),
    isRoot: Bool = false,
    decision: ModeSwitcher.Decision = .revert
) async throws -> Transcript {
    let command = try ResoluteCommand.parseAsRoot(arguments)
    guard let runnable = command as? any ContextCommand else {
        throw CLITestError.notRunnable(String(describing: type(of: command)))
    }
    let transcript = Transcript()
    try await runnable.run(in: transcript.context(service: service, isRoot: isRoot, decision: decision))
    return transcript
}

/// The message and exit code the command line would show for `arguments`, or nil when
/// the command succeeds. It goes through the same `execute` as `main`.
func failure(_ arguments: [String], service: any DisplayControlling = FakeDisplays([Sample.builtIn])) async -> (message: String, code: Int32)? {
    let transcript = Transcript()
    let result = await ResoluteCommand.execute(arguments, in: transcript.context(service: service, isRoot: false, decision: .revert))
    return result.code == 0 ? nil : (result.message ?? "", result.code)
}

enum CLITestError: Error {
    case notRunnable(String)
}

/// Apple's override for the built-in panel of a 16-inch MacBook Pro, as macOS 27 ships it:
/// five 1× entries and two HiDPI entries in Apple's 12-byte form.
func appleBuiltInOverride() -> [String: Any] {
    [
    "DisplayProductName": "Color LCD",
    "DisplayVendorID": 1552,
    "DisplayProductID": 41040,
    "IOGFlags": 4,
    "scale-resolutions": [
        "0000101000000a62", "00000d80000008ba", "00000bb00000078e", "00000a40000006a0", "00000920000005e6",
        "00000a000000064000000001", "00000780000004b000000001",
    ].map(hexData),
    ]
}

func hexData(_ hex: String) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    })
}

/// A staged root whose `System` folder holds Apple's file for the built-in panel.
func stagedRootWithApplesFile() throws -> URL {
    let root = try stagedRoot()
    let file = OverrideLocations.staged(at: root).systemFile(for: OverrideKey(vendorID: 0x610, productID: 0xA050))
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: appleBuiltInOverride(), format: .xml, options: 0).write(to: file)
    return root
}

/// A fresh directory for a staged override root; its name has a space and a quote.
func stagedRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "Resolute CLI 'tests' \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
