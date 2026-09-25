# Checking a new macOS release

Resolute depends on two things macOS does not document: the layout of the private SkyLight mode records, and the format of display override files. Run these checks on each new major macOS release, betas included, on as many Macs and displays as you can.

## 1. Mode records

1. `swift Scripts/capture-mode-fixture.swift --list` lists the online displays and their IDs.
2. Capture each display: `swift Scripts/capture-mode-fixture.swift <id> > Tests/ResoluteKitTests/Fixtures/<mac>-<display>-macos<version>.json`, for example `m2pro-builtin-macos28.json`. The script only reads.
3. Run `swift test`. `CapturedFixtureTests` checks that every capture's records agree with CoreGraphics.
4. Run `resolute doctor`. Each display should say "hidden modes available".
   - If it says "hidden modes ignored", the record layout changed. Compare a captured record with the offsets table in [the design document](design/2026-09-25-resolute-design.md) and update `PrivateModeRecord`.
   - Until then, Resolute offers only the modes CoreGraphics lists, which is safe.
5. Run `make live-test`. It switches the main display's refresh rate for a moment and back.

## 2. Override files

`swift test` also runs `ShippedOverrideTests`. It reads every override file macOS ships and checks that Resolute writes each one back unchanged. A failure names the file, which means a new kind of entry or key. Inspect it with `plutil -p <file>`.

## 3. By hand

Work through [TESTING.md](../TESTING.md), at least the Menu and Custom resolutions sections.

Commit the new captures, and note the release in CHANGELOG.md.
