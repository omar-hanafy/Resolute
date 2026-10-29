import AppKit

/// How Resolute was started. The first deliberate launch shows Welcome with the window,
/// the Dock icon and ⌘Tab; a launch at login stays quiet in the menu bar (Figma: Settings &
/// Onboarding, the page header).
enum LaunchKind: Equatable, Sendable {
    /// Opened by a person: from Finder, the Dock, Spotlight, `open` or `make install`.
    case deliberate
    /// Started by macOS as a login item.
    case atLogin

    /// Reads the open-application Apple event that launched the app, which is the current
    /// event while `applicationDidFinishLaunching(_:)` runs. macOS marks a login item's launch
    /// with `keyAELaunchedAsLogInItem`; anything else, no event included, is deliberate.
    init(appleEvent event: NSAppleEventDescriptor?) {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
        else {
            self = .deliberate
            return
        }
        self = .atLogin
    }
}
