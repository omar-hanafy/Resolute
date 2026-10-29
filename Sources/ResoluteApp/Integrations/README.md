# System integrations

Figma: System integrations, page 8:10. Dock menu 44:76, Control Center 44:755, Shortcuts 45:262, Spotlight 45:442.

## Built

- **Dock menu** (`DockMenu.swift`). `DockMenu.make(model:)` returns the menu for `applicationDockMenu(_:)`. It lists each display's sizes at hand (the one in use, the default, and the sizes the presets give that display), then its refresh rates, then Presets and Mirror Displays. That reproduces Figma's two displays exactly with Figma's three presets. Every item calls the app model with `from: .dock`, so History records the Dock. Hidden modes are left out: nobody may be watching the display that a Dock menu switches. A hidden mode that is already in use is still listed, checked, so the menu always shows the display's current state. macOS adds Options, Show All Windows, Hide and Quit itself.

- **Shortcuts and Siri** (`AppIntents/`). Figma's six actions, as App Intents in the app:

  | Action | Shortcuts says | Returns |
  | --- | --- | --- |
  | Apply Preset | Apply Resolute preset *Coding* | a dialog |
  | Set Resolution | Set resolution of *DELL U2723QE* to *2560 × 1440* | the display |
  | Set Refresh Rate | Set refresh rate of *Built-in Retina Display* to *120 Hz* | the display |
  | Mirror Displays | *Turn on* display mirroring (or Turn off, Toggle) | whether it is on |
  | Get Displays | Get *all displays* from Resolute (or the main display) | displays |
  | Open Resolute | Open Resolute | |

  - **How they reach the app.** Intents run in Resolute's own process. The app delegate sets `IntentHost.appModel` as soon as it has made the model, and every intent and query waits for it (`IntentHost.readyModel()`, up to 10 seconds, for when macOS launches Resolute to run one). `AppDependencyManager` would work too, but its dependency has to be registered before an intent arrives, which is the same wait; a main-actor reference keeps it plain and lets the tests use their own model.
  - **What they do.** `ShortcutActions` does the work, through the app model, so everything the panel's actions are guarded by applies. Presets go through `runPreset(_:from:)`, mirroring through `changeMirroring(_:from:)`, sizes and rates through `applyListedMode(_:to:from:)` (refresh rates pick their mode with `AppModel.refreshOption`, as `setRefreshRate` does). Each passes `from: .shortcuts`, so History records Shortcuts, and History's Shortcuts filter appears once it has such a change. These are the throwing forms of `applyPreset`, `setMirroring` and `apply`: they throw a `ChangeFailure` (the alert's title and message), and the coordinator is told not to show its own alert, so Shortcuts shows the message instead.
  - **Listed modes only.** The resolutions and rates on offer, and the modes switched to, are a display's system modes. Nobody may be watching the display, so nothing that would need Keep or Revert is ever tried, as with the Dock menu. A resolution picked for one display and used with another switches the other to the same size when it lists it.
  - **While a question is up.** While the app's Keep/Revert countdown is up (`modeChanges.isChangingMode`) or an agent's question is (`agentRequests.isAsking`), every action that changes something fails with "Resolute is asking whether to keep a display setting. Answer that first, then try again." The coordinator would turn the switch away anyway; failing says so instead of doing nothing.
  - **Entities.** A display is named by `ShortcutCatalog.identifier(of:among:)`: "builtin", else vendor, product and serial number, which last across restarts. Identical monitors with no serial number add their display ID, which lasts while they stay connected. A resolution's ID names its display and its size in points and pixels; a rate's is its hundredths of a hertz. Presets are found by ID, and by name for Siri.
  - **App Shortcuts** (`ResoluteShortcuts`). One per action, with Figma's symbols. Apply Preset and Set Resolution have a phrase that names their value, so Siri and Spotlight offer one per preset and per resolution. `ShortcutParameterUpdates` asks App Shortcuts to read the presets and resolutions again whenever they change.

- **Spotlight** (macOS 26 shows app actions). The same metadata makes every action discoverable (`isDiscoverable` is true by default from macOS 14), and Spotlight lists the App Shortcuts. Typing a size finds "Set 1496 × 967", the Set Resolution shortcut for that resolution, which switches the display the resolution belongs to without asking which. Left out: indexing each size as a Spotlight item (`IndexedEntity` and `CSSearchableIndex.indexAppEntities`, macOS 15). An indexed item opens the app when chosen rather than switching, it needs the index kept in step with the displays, and the App Shortcut already finds the size. Figma's row says "Set Built-in Retina Display to 1496 × 967"; what Spotlight shows for the shortcut is up to macOS and hasn't been seen.

### How the metadata is built

macOS finds App Intents only through `Resolute.app/Contents/Resources/Metadata.appintents`. Xcode writes it with `appintentsmetadataprocessor` from the `.swiftconstvalues` the compiler emits; SwiftPM asks for neither, so `Scripts/build-app.sh` does both after `swift build`, before signing:

1. **Constant values, for ResoluteApp only.** A second `swiftc -wmo -c` of `Sources/ResoluteApp` against the modules `swift build` just made, with `-emit-const-values-path` and `-Xfrontend -const-gather-protocols-file`. `-Xswiftc` on `swift build` would reach every module, and each would overwrite the same file (an earlier probe's first pitfall). Xcode 16.0, the oldest CI toolchain, may want `-Xfrontend -const-gather-protocols-file` spelled this way (the third pitfall), so it is.
2. **Never stale.** It writes into a folder `mktemp -d` makes on every run and removes on exit, and the app bundle is made new on every run too, so an incremental build can't leave an older file behind (the second pitfall). Checked by renaming an intent, running the script, and renaming it back: each run's metadata had the name of that moment.
3. **The processor's options.** The options Xcode 27.1's processor requires are always passed (`--output`, `--toolchain-dir`, `--module-name`, `--sdk-root`, `--xcode-version`, `--platform-family`, `--deployment-target`, `--target-triple`, `--source-file-list`, `--swift-const-vals-list`). `--compile-time-extraction`, `--deployment-aware-processing`, `--no-app-shortcuts-localization`, `--force` and `--bundle-identifier` are passed only when the processor's `--help` lists them; 27.1's lists `--deployment-aware-processing`, `--no-app-shortcuts-localization` and `--force`. If that writes nothing, the script runs it again with the options Xcode itself passes but newer processors hide, `--compile-time-extraction` and `--binary-file`. 27.1's output was the same either way, and it ignored an option it didn't know.
4. **The check.** The processor's exit status says little (the fourth pitfall): with no constant values it prints "Extracted no relevant App Intents symbols, skipping writing output" and exits 0. So the build fails unless `Metadata.appintents/extract.actionsdata` exists and isn't empty.

The signature covers `Resources`, so signing is unchanged. The protocol list holds every name a supported Xcode extracts by; names a compiler doesn't know match nothing.

Verified on Xcode 27.1 (27A9275, Swift 6.4): `extract.actionsdata` names the six intents, the four entities and their queries, both enums and the six App Shortcuts, and `codesign --verify --strict --deep` passes. The metadata didn't change when the intents' static properties went from stored to computed (stored ones of AppIntents types need a macOS 15 `Sendable` conformance). Not verified here: the processors in Xcode 16.0 and 26.6, which CI runs; that Shortcuts and Spotlight list the actions of an ad hoc signed build; and the actions run on a real display. `TESTING.md` lists the hand checks.

## Not built

The earlier probe was a scratch SwiftPM package, built on Xcode 27.1 (27A9275, Swift 6.4, macOS 27 SDK) on 29 October 2026; nothing was installed, registered or run.

### Control Center and menu bar controls (44:755, macOS 26+)

**Verdict: needs an app extension, which SwiftPM can't package. The build script would have to assemble it by hand.**

- **The protocol.** `SwiftUI.swiftinterface` declares `@available(iOS 18.0, macOS 26.0, watchOS 26.0, *) public protocol ControlWidget`. WidgetKit runs it from a `WidgetBundle` in a WidgetKit extension (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
- **What Xcode builds.** Xcode's product type for an app extension (`DarwinProductTypes.xcspec`) uses `LD_ENTRY_POINT = _NSExtensionMain`, `APPLICATION_EXTENSION_API_ONLY = YES` and `WRAPPER_EXTENSION = appex`, and the template turns on the app sandbox.
- **The probe compiled one.** An executable target with `-application-extension`, `-Xlinker -e -Xlinker _NSExtensionMain` and `-Xlinker -application_extension`, holding a button and a toggle control, built with `Build complete!`. It was then hand-assembled into `Probe.app/Contents/PlugIns/ProbeControls.appex`, with an `XPC!` Info.plist and the extension point. Signed ad hoc with `com.apple.security.app-sandbox`, extension first and then the app, it passed `codesign --verify --strict --deep`. It was not registered with `pluginkit` or run, so whether macOS accepts it is unverified.
- **Sandboxing changes the design.** A sandboxed extension can't call SkyLight, so the controls' intents have to run in the app, for example with `openAppWhenRun`, or message it. Sharing state needs an app group, and an app group needs a real Team ID.
- **SDK stamping.** The extension's binary needs the same SDK stamping (`vtool`) as the app.

Figma's controls fit what controls allow: a Mirror Displays toggle and one button per preset.
