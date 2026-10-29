import Carbon.HIToolbox
import ResoluteKit

/// Registers shortcuts that work from anywhere with Carbon's `RegisterEventHotKey`, the one
/// public API for them that needs no Accessibility or Input Monitoring permission. macOS
/// sends their presses to the app's event target on the main thread.
@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    var onPress: (@MainActor (UInt32) -> Void)?

    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    /// "RSLT": marks Resolute's hot keys among the events the handler sees.
    nonisolated static let signature: OSType = 0x5253_4C54

    func register(_ shortcut: KeyShortcut, id: UInt32) throws {
        try installHandler()
        unregister(id: id)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &hotKey
        )
        guard status == noErr, let hotKey else { throw HotKeyRefused(shortcut: shortcut, status: status) }
        hotKeys[id] = hotKey
    }

    func unregister(id: UInt32) {
        guard let hotKey = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(hotKey)
    }

    /// Carbon's modifier mask for `modifiers`.
    nonisolated static func carbonModifiers(_ modifiers: KeyShortcut.Modifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    /// Installs the handler for hot key presses once. The registrar lives as long as the
    /// app, so the handler's unretained pointer to it stays good.
    private func installHandler() throws {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), carbonHotKeyHandler, 1, &pressed,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { throw HotKeyRefused(shortcut: .openPanel, status: status) }
    }

    fileprivate func pressed(_ id: UInt32) {
        guard hotKeys[id] != nil else { return }
        onPress?(id)
    }
}

/// Carbon's handler for `kEventHotKeyPressed`: hands the hot key's ID to the registrar.
private func carbonHotKeyHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == CarbonHotKeyRegistrar.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers application events on the main thread.
    MainActor.assumeIsolated { registrar.pressed(id) }
    return noErr
}
