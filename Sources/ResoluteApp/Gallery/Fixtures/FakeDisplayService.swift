import CoreGraphics
import Foundation
import ResoluteKit

/// Two displays as a person might have them, for gallery scenes and tests: a 16-inch MacBook
/// Pro's built-in display (the main one, 1728 × 1117 at 120 Hz) and a DELL U2723QE (2560 ×
/// 1440 at 60 Hz, with one hidden mode). Switching changes the mode it reports, mirroring
/// links the two, and it records what was asked of it. It never touches a real display.
///
/// ResoluteKit's sample displays (Presentation/) are the shared set; scenes and tests move to
/// them once both are in.
final class FakeDisplayService: DisplayControlling, @unchecked Sendable {
    struct Change: Equatable, Sendable {
        var displayID: CGDirectDisplayID
        var modeID: Int32
        var scope: ConfigurationScope
    }

    static let builtInID: CGDirectDisplayID = 1
    static let dellID: CGDirectDisplayID = 2

    private let lock = NSLock()
    private var list: [Display]
    private var recordedChanges: [Change] = []
    private var recordedMirroring: [Bool] = []
    private var failure: ResoluteError?

    init(displays: [Display] = FakeDisplayService.sampleDisplays) {
        list = displays
    }

    /// Every switch asked for, in order.
    var changes: [Change] { lock.withLock { recordedChanges } }

    /// Every mirroring change asked for, in order.
    var mirroringRequests: [Bool] { lock.withLock { recordedMirroring } }

    /// An error every switch and mirroring change throws, while set.
    var failsWith: ResoluteError? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    /// Replaces the displays, as connecting or removing one does.
    func set(_ displays: [Display]) {
        lock.withLock { list = displays }
    }

    func displays() -> [Display] {
        lock.withLock { list }
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock { list.first { $0.id == displayID }?.currentModeID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            if let failure { throw failure }
            guard let index = list.firstIndex(where: { $0.id == displayID }) else {
                throw ResoluteError.displayNotFound("id:\(displayID)")
            }
            guard list[index].modes.contains(where: { $0.modeID == modeID }) else {
                throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: [])
            }
            recordedChanges.append(Change(displayID: displayID, modeID: modeID, scope: scope))
            list[index].currentModeID = modeID
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        try lock.withLock {
            if let failure { throw failure }
            guard list.count > 1 else { throw ResoluteError.mirroringNeedsTwoDisplays }
            recordedMirroring.append(enabled)
            let main = list.first(where: \.isMain)?.id ?? list[0].id
            for index in list.indices {
                list[index].isInMirrorSet = enabled
                list[index].mirrorSourceID = enabled && list[index].id != main ? main : nil
            }
        }
    }

    // MARK: - The sample displays

    static var sampleDisplays: [Display] {
        [builtIn, dell]
    }

    /// A 16-inch MacBook Pro's display: 3456 × 2234 pixels, ProMotion.
    static var builtIn: Display {
        var modes: [DisplayMode] = []
        var id: Int32 = 100
        func add(_ width: Int, _ height: Int, scale: Int, rates: [Double], flags: UInt32 = 0x3) {
            for rate in rates {
                modes.append(DisplayMode(
                    modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
                    refreshRate: rate, bitsPerSample: 10, ioFlags: flags
                ))
                id += 1
            }
        }
        let rates: [Double] = [120, 60, 50, 48]
        add(2056, 1329, scale: 2, rates: rates)
        add(1728, 1117, scale: 2, rates: rates, flags: 0x7)
        add(1496, 967, scale: 2, rates: rates)
        add(1312, 848, scale: 2, rates: rates)
        add(3456, 2234, scale: 1, rates: [120, 60], flags: 0x0200_0003)
        add(1728, 1117, scale: 1, rates: [120, 60])
        return Display(
            id: builtInID, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050, serialNumber: 0x4E50_3031,
            isBuiltin: true, isMain: true, currentModeID: 104, modes: modes, privateModes: .trusted
        )
    }

    /// A 27-inch 4K monitor: 3840 × 2160 pixels at up to 60 Hz, with a hidden 2880 × 1620.
    static var dell: Display {
        var modes: [DisplayMode] = []
        var id: Int32 = 200
        func add(_ width: Int, _ height: Int, scale: Int, rates: [Double], flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system) {
            for rate in rates {
                modes.append(DisplayMode(
                    modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
                    refreshRate: rate, bitsPerSample: 8, ioFlags: flags, origin: origin
                ))
                id += 1
            }
        }
        let rates: [Double] = [60, 50, 30]
        add(3008, 1692, scale: 2, rates: [60])
        add(2560, 1440, scale: 2, rates: rates)
        add(1920, 1080, scale: 2, rates: rates, flags: 0x7)
        add(1600, 900, scale: 2, rates: [60])
        add(3840, 2160, scale: 1, rates: rates, flags: 0x0200_0003)
        add(2560, 1440, scale: 1, rates: [60])
        add(2880, 1620, scale: 2, rates: [60], origin: .hidden)
        return Display(
            id: dellID, name: "DELL U2723QE", vendorID: 0x10AC, productID: 0x42A6, serialNumber: 0x4C4C_4E42,
            currentModeID: 201, modes: modes, privateModes: .trusted
        )
    }
}
