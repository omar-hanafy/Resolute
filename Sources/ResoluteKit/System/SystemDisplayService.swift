import CoreGraphics
import Foundation

/// Reads and changes the display configuration.
public protocol DisplayControlling: Sendable {
    /// A fresh snapshot of every online display.
    func displays() -> [Display]
    /// The IO mode ID `displayID` is using right now.
    func currentModeID(of displayID: CGDirectDisplayID) -> Int32?
    /// Switches `displayID` to the mode with `modeID`.
    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws
    /// Mirrors every display to the main display, or stops mirroring.
    func setMirroring(_ enabled: Bool) throws
}

/// `DisplayControlling` backed by CoreGraphics and, when its records check out, SkyLight.
public struct SystemDisplayService: DisplayControlling {
    private let skyLight: SkyLight?

    public init(skyLight: SkyLight? = SkyLight.shared) {
        self.skyLight = skyLight
    }

    public func displays() -> [Display] {
        let ids = Self.onlineDisplayIDs()
        let screenNames = DisplayNames.screenNames()
        let names = DisplayNames.disambiguate(ids.map {
            screenNames[$0] ?? DisplayNames.coreDisplayName(for: $0) ?? DisplayNames.fallbackName(for: $0)
        })
        return zip(ids, names).map { makeDisplay(id: $0, name: $1) }
    }

    public func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID
    }

    public func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        // CoreGraphics still lists a placeholder mode for a display that went away.
        guard Self.isOnline(displayID) else { throw ResoluteError.displayNotFound("id:\(displayID)") }
        if let mode = Self.systemModes(for: displayID).first(where: { $0.ioDisplayModeID == modeID }) {
            try configure(scope: scope) { config in
                try check(CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil), "select the display mode")
            }
        } else if let index = hiddenModeIndex(modeID, display: displayID) {
            try apply(privateIndex: index, to: displayID, scope: scope)
        } else {
            throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: [])
        }
    }

    public func setMirroring(_ enabled: Bool) throws {
        let online = Self.onlineDisplayIDs()
        guard online.count > 1 else { throw ResoluteError.mirroringNeedsTwoDisplays }
        let operation = enabled ? "mirror the displays" : "stop mirroring"
        try configure(scope: .permanent) { config in
            for step in MirroringPlan.steps(online: online, main: CGMainDisplayID(), enable: enabled) {
                try check(CGConfigureDisplayMirrorOfDisplay(config, step.display, step.source), operation)
            }
        }
    }

    /// Switches through SkyLight to the mode at `privateIndex` in the private list.
    func apply(privateIndex: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard let skyLight else { throw ResoluteError.modeNotFound("private mode \(privateIndex)", suggestions: []) }
        try configure(scope: scope) { config in
            // Checked last thing before SkyLight is asked: a display can go away at any time,
            // and what SkyLight does with one that has is undefined.
            guard Self.isOnline(displayID) else { throw ResoluteError.displayNotFound("id:\(displayID)") }
            skyLight.configure(config, display: displayID, index: privateIndex)
        }
    }

    // MARK: - Snapshot

    private func makeDisplay(id: CGDirectDisplayID, name: String) -> Display {
        var modes = Self.systemModes(for: id).map(DisplayMode.init(systemMode:))
        var currentID = currentModeID(of: id)
        var status = PrivateModeStatus.unavailable
        if let skyLight {
            status = addPrivateModes(from: skyLight, display: id, to: &modes, currentID: &currentID)
        }

        let mirrorSource = CGDisplayMirrorsDisplay(id)
        return Display(
            id: id,
            name: name,
            vendorID: CGDisplayVendorNumber(id),
            productID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            mirrorSourceID: mirrorSource == kCGNullDirectDisplay ? nil : mirrorSource,
            isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
            currentModeID: currentID,
            modes: modes,
            privateModes: status
        )
    }

    /// Adds the hidden modes and the private indexes when SkyLight's records check out. Each
    /// SkyLight call is made only while the display is online: a display that cannot show a
    /// mode may drop off at any moment, and what SkyLight does with one that has is undefined.
    private func addPrivateModes(
        from skyLight: SkyLight,
        display id: CGDirectDisplayID,
        to modes: inout [DisplayMode],
        currentID: inout Int32?
    ) -> PrivateModeStatus {
        guard Self.isOnline(id) else { return .untrusted(reason: "the display went offline") }
        switch PrivateModeValidator.validate(records: skyLight.records(for: id), against: modes) {
        case .trusted(let records, let hidden):
            let currentIndex = Self.isOnline(id) ? skyLight.currentModeIndex(for: id) : nil
            (modes, currentID) = ModeMerge.merge(
                systemModes: modes, records: records, hidden: hidden,
                currentModeID: currentID, currentPrivateIndex: currentIndex
            )
            return .trusted
        case .untrusted(let reason):
            return .untrusted(reason: reason)
        }
    }

    private func hiddenModeIndex(_ modeID: Int32, display: CGDirectDisplayID) -> Int32? {
        guard let skyLight, Self.isOnline(display) else { return nil }
        let systemModes = Self.systemModes(for: display).map(DisplayMode.init(systemMode:))
        guard case .trusted(_, let hidden) = PrivateModeValidator.validate(
            records: skyLight.records(for: display), against: systemModes
        ) else { return nil }
        return ModeMerge.privateIndex(ofHiddenMode: modeID, in: hidden)
    }

    // MARK: - CoreGraphics helpers

    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Whether `display` is online now. CoreGraphics answers -1, which is not false, for an
    /// ID it has never seen, so only a positive answer counts.
    static func isOnline(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayIsOnline(display) > 0
    }

    static func systemModes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// Runs `body` inside a configuration transaction and commits it with `scope`.
    private func configure(scope: ConfigurationScope, _ body: (CGDisplayConfigRef) throws -> Void) throws {
        var configRef: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configRef), "start a display configuration")
        guard let config = configRef else {
            throw ResoluteError.coreGraphics(code: CGError.failure.rawValue, operation: "start a display configuration")
        }
        do {
            try body(config)
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, scope.option), "apply the display configuration")
    }

    private func check(_ error: CGError, _ operation: String) throws {
        guard error == .success else {
            throw ResoluteError.coreGraphics(code: error.rawValue, operation: operation)
        }
    }
}

extension DisplayMode {
    init(systemMode mode: CGDisplayMode) {
        self.init(
            modeID: mode.ioDisplayModeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: (mode.refreshRate * 1_000).rounded() / 1_000,
            ioFlags: mode.ioFlags,
            origin: .system
        )
    }
}
