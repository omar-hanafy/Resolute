# System integrations

Figma: System integrations, page 8:10. Dock menu 44:76, Control Center 44:755, Shortcuts 45:262, Spotlight 45:442.

## Built

- **Dock menu** (`DockMenu.swift`). `DockMenu.make(model:)` returns the menu for `applicationDockMenu(_:)`. It lists each display's sizes at hand (the one in use, the default, and the sizes the presets give that display), then its refresh rates, then Presets and Mirror Displays. That reproduces Figma's two displays exactly with Figma's three presets. Every item calls the app model with `from: .dock`, so History records the Dock. Hidden modes are left out: nobody may be watching the display that a Dock menu switches. A hidden mode that is already in use is still listed, checked, so the menu always shows the display's current state. macOS adds Options, Show All Windows, Hide and Quit itself.

## Investigated, not built

The probe in this investigation was a scratch SwiftPM package. It was built on Xcode 27.1 (27A9275, Swift 6.4, macOS 27 SDK) on 29 October 2026, and nothing was installed, registered or run. `Scripts/build-app.sh` was left unchanged, as the task required. None of the three integrations below can work without changing that script, so this branch contains no code for them. App Intents types without their metadata would compile, but macOS would never find them.

### Shortcuts and Siri (App Intents, 45:262)

**Verdict: feasible in a pure SwiftPM build, but only with build-script changes. No Xcode project is needed.**

macOS discovers intents only through `Resolute.app/Contents/Resources/Metadata.appintents`. Xcode writes that folder with `appintentsmetadataprocessor`, which is in the toolchain:

```
$ xcrun --find appintentsmetadataprocessor
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor
```

The processor reads the `.swiftconstvalues` the compiler emits for the module. Without them it prints `No swiftconstvalues found ... Extracted no relevant App Intents symbols, skipping writing output` and writes nothing. The compiler emits them only when told to. The flags are those Xcode's own build rule passes:

```
$ swift build --jobs 4 -c release --arch arm64 \
    -Xswiftc -emit-const-values-path -Xswiftc $P/out/Probe.swiftconstvalues \
    -Xswiftc -const-gather-protocols-list -Xswiftc $P/protocols.json
Build complete!            # Probe.swiftconstvalues lists Probe.OpenProbeIntent, Probe.ProbeShortcuts

$ xcrun appintentsmetadataprocessor --output meta/Resources --toolchain-dir $TC --module-name Probe \
    --sdk-root $SDK --xcode-version 27A9275 --platform-family macOS --deployment-target 14.0 \
    --target-triple arm64-apple-macos14.0 --bundle-identifier com.example.probe \
    --source-file-list meta/sources.txt --swift-const-vals-list meta/constvals.txt \
    --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization --force
Writing Metadata.appintents
# Metadata.appintents/extract.actionsdata (1553 B): OpenProbeIntent, isDiscoverable true, autoShortcuts
# Metadata.appintents/version.json: {"toolsVersion":"27A9275","version":"3.0"}
```

The probe found four pitfalls:

- `-Xswiftc` on the command line applies to every module. Each module overwrites the same const-values file, and a module without intents writes `[]`. Resolute builds the CLI and ArgumentParser alongside the app, so the flag must apply to the ResoluteApp target alone. Two ways to do that:
  - A per-target `.unsafeFlags` in `Package.swift`, with absolute paths from `Context.packageDirectory`. Swift Build runs `swiftc` from the package's parent folder, so a relative path lands outside the package.
  - A second `swiftc -wmo -emit-module` pass over `Sources/ResoluteApp` after `swift build`.
- SwiftPM doesn't track the file as a build output, so an incremental build may not rewrite it.
- With Xcode 16.0 (Swift 6.0, which CI still uses), the frontend form `-Xfrontend -const-gather-protocols-file` is the safe spelling. This was inferred and not run.
- The processor's exit status wasn't captured. The script should check that `extract.actionsdata` exists rather than trust the exit status.

The script would need these steps, after `swift build` and before both `codesign` calls:

1. Produce `ResoluteApp.swiftconstvalues`, using one of the two ways above.
2. Write the list of `Sources/ResoluteApp` files and the const-values path to two list files.
3. Run the processor into `$APP/Contents/Resources`, with the flags shown above and the app's bundle identifier.
4. Fail if `Metadata.appintents/extract.actionsdata` is missing.

The existing signature covers `Resources`, so signing stays as it is.

Two things remain unverified: that Shortcuts lists the actions of an ad hoc signed app assembled this way, and Figma's actions (Apply Preset, Set Resolution, Set Refresh Rate, Mirror Displays, Get Displays, Open Resolute). Both need a run on a test Mac.

### Spotlight actions (45:442, macOS 26+)

**Verdict: feasible in a pure SwiftPM build, with the same build-script changes as Shortcuts, and no extension.**

Spotlight's actions come from the same `Metadata.appintents`. `AppIntent.isDiscoverable` is available from macOS 14, defaults to true, and the probe's metadata already carries `"isDiscoverable": true`. Figma's "type a size" search would also need `IndexedEntity` entities (macOS 15) indexed with `CSSearchableIndex.indexAppEntities(_:)`. `IndexedEntityQuery` is macOS 27 only.

### Control Center and menu bar controls (44:755, macOS 26+)

**Verdict: needs an app extension, which SwiftPM can't package. The build script would have to assemble it by hand.**

- **The protocol.** `SwiftUI.swiftinterface` declares `@available(iOS 18.0, macOS 26.0, watchOS 26.0, *) public protocol ControlWidget`. WidgetKit runs it from a `WidgetBundle` in a WidgetKit extension (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
- **What Xcode builds.** Xcode's product type for an app extension (`DarwinProductTypes.xcspec`) uses `LD_ENTRY_POINT = _NSExtensionMain`, `APPLICATION_EXTENSION_API_ONLY = YES` and `WRAPPER_EXTENSION = appex`, and the template turns on the app sandbox.
- **The probe compiled one.** An executable target with `-application-extension`, `-Xlinker -e -Xlinker _NSExtensionMain` and `-Xlinker -application_extension`, holding a button and a toggle control, built with `Build complete!`. It was then hand-assembled into `Probe.app/Contents/PlugIns/ProbeControls.appex`, with an `XPC!` Info.plist and the extension point. Signed ad hoc with `com.apple.security.app-sandbox`, extension first and then the app, it passed `codesign --verify --strict --deep`. It was not registered with `pluginkit` or run, so whether macOS accepts it is unverified.
- **Sandboxing changes the design.** A sandboxed extension can't call SkyLight, so the controls' intents have to run in the app, for example with `openAppWhenRun`, or message it. Sharing state needs an app group, and an app group needs a real Team ID.
- **SDK stamping.** The extension's binary needs the same SDK stamping (`vtool`) as the app.

Figma's controls fit what controls allow: a Mirror Displays toggle and one button per preset.
