# Resolute — design

Date: 2026-09-25
Status: accepted for implementation under the owner's standing goal (no interactive
review; assumptions are listed below so they can be corrected later)

## Understanding

**What was asked.** RDM (the menu-bar resolution switcher at `clones/RDM`, a fork of
`avibrazil/RDM` via `usr-sse2/RDM`) is abandoned. Build our own replacement from the
ground up, make it support macOS 27, verify that it works, and publish it as a
**private** GitHub repository under the `omar-hanafy` account (switching `gh` to that
account). It becomes public after the owner has tested it.

**Assumptions (not stated by the owner).**

- The product keeps RDM's reason to exist: one-click access to *every* display mode,
  including the 1× and "hidden" modes that System Settings does not offer, plus RDM's
  custom HiDPI resolution editor and its command-line mode.
- New name: **Resolute** (repo `omar-hanafy/Resolute`, bundle id
  `com.omarhanafy.Resolute`, CLI `resolute`). Easy to rename before going public.
- The project lives next to RDM at `clones/Resolute`.
- Commits use the identity the owner uses for personal repos
  (`Omar Khaled <omar_hanafy@icloud.com>`), set locally in this repository only.
- Minimum OS is macOS 14 (Sonoma) so modern AppKit/SwiftUI APIs are available;
  macOS 27 on Apple silicon is the verified target.

**Success criteria.**

1. Builds from a clean checkout with `swift build` / `make app` on Xcode 27.
2. On this Mac (MacBook Pro M2 Pro, macOS 27.0) it lists the built-in display's modes
   with correct sizes, scales and refresh rates, and switches modes through both the
   public and the private path.
3. Automated tests cover the pure logic (mode decoding, grouping, menu model, override
   file codec, CLI parsing) and run green; live tests prove the system integration.
4. The app bundle launches as a menu-bar agent and its menu renders from live data.
5. Pushed to a private repository under `omar-hanafy`.

## Why RDM no longer works on macOS 27 (evidence)

Measured on this Mac (macOS 27.0, build 26A428, M2 Pro, built-in Liquid Retina XDR):

- The private SkyLight functions RDM uses still exist:
  `CGSGetNumberOfDisplayModes`, `CGSGetDisplayModeDescriptionOfLength`,
  `CGSGetCurrentDisplayMode`, `CGSConfigureDisplayMode`.
- The 0xD4-byte mode record **changed layout**. RDM reads the refresh rate as a
  `uint16` at 0xBC; on macOS 27 the `uint32` at 0xBC is a 16.16 fixed-point rate, so RDM
  sees `0` for integer rates and garbage for fractional ones (61603 for 59.94 Hz, 62259
  for 47.95 Hz). RDM's "pick the highest refresh rate" logic therefore selects
  47.95 Hz whenever a resolution is chosen, and its refresh-rate menu disappears.
- RDM maps `depth == 4` to 32-bit colour; macOS 27 reports `8` (10-bit
  `--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB`), so every mode is labelled 16-bit.
- `IODisplayConnect` services do not exist on Apple silicon, so RDM's display-name
  lookup returns nothing (the owner's override file has `DisplayProductName = ""`).

Verified macOS 27 record layout (all 132 modes cross-checked against the public API,
0 mismatches):

| Offset | Type | Meaning |
|---|---|---|
| 0x00 | u32 | index in the private mode list (argument to `CGSConfigureDisplayMode`) |
| 0x04 | u32 | IO mode flags (private variant) |
| 0x08 / 0x0C | u32 | width / height in points |
| 0x10 | u32 | depth code (8 = 30-bit) |
| 0x14 | u32 | bytes per row |
| 0x18 / 0x1C / 0x20 | u32 | bits per pixel / bits per sample / samples per pixel |
| 0x24 | u32 | integer refresh rate (truncated) |
| 0x30 | char[64] | IO pixel encoding string |
| 0xB8 | u32 | record size marker (= 0xD4) |
| 0xBC | u32 | refresh rate, 16.16 fixed point |
| 0xC0 | u32 | IO flags (same value as `CGDisplayModeGetIOFlags`) |
| 0xC4 | u32 | IO display mode ID (same as `CGDisplayModeGetIODisplayModeID`) |
| 0xC8 / 0xCC | u32 | pixel width / pixel height |
| 0xD0 | f32 | scale (density) |

## Approaches considered

**Project shape**

1. **Swift package + bundling script (chosen).** One `Package.swift` with a core
   library, a CLI and an AppKit/SwiftUI app target; a script assembles and ad-hoc signs
   `Resolute.app`. Reproducible from the command line, testable with `swift test`,
   no `.pbxproj` to maintain.
2. Xcode project like RDM. Familiar, but the project file is opaque to review and to
   generate, and CLI-driven verification is clumsier.
3. Patch RDM in place. Fastest, but the owner asked for a ground-up rebuild, and RDM's
   Objective-C++/storyboard structure is where most of its bugs live.

**Mode discovery**

1. **Public API first, private API as a validated extra (chosen).**
   `CGDisplayCopyAllDisplayModes` with `kCGDisplayShowDuplicateLowResolutionModes`
   supplies documented, switchable modes. The private list is decoded and
   cross-checked against it at runtime; only when every overlapping record agrees is
   the private decoder trusted, and only then are private-only ("hidden") modes shown.
   A future layout change degrades to public-only instead of showing garbage.
2. Private API only (RDM). Breaks silently when the layout changes — exactly today's
   failure.
3. Public API only. Safe, but loses modes macOS hides, which is RDM's purpose.

## Scope

In:

- Menu-bar agent: per display, current resolution and refresh rate; resolution submenu
  sectioned into HiDPI / Low Resolution (1×) / Hidden; refresh-rate submenu; Default and
  Native badges; mirroring toggle (two or more displays); Custom Resolutions editor;
  Show Low-Resolution Modes and Launch at Login toggles; About; Quit.
- Holding ⌥ while opening the menu reveals hidden modes and mode IDs.
- Hidden (private-only) modes are applied for the session first with a 15-second
  "Keep / Revert" countdown, then made permanent on Keep; a black screen reverts itself.
- Custom Resolutions editor for display override plists in
  `/Library/Displays/Contents/Resources/Overrides`, with backup, admin-authorised
  writes, and removal.
- `resolute` CLI: `displays`, `modes`, `set`, `mirror`, `overrides list|show|add|remove|reset`,
  JSON output for scripting.
- Build, install and uninstall scripts; generated app icon; README; MIT licence.

Out (YAGNI): RDM's `Icons.plist` preview-icon editor, HDR/brightness control, virtual
displays, EDID overrides, auto-update, notarisation (needs a Developer ID; the build
script signs ad hoc), CI (would spend private-repo macOS minutes; add when public).

## Architecture

```
Package.swift                (swift-tools 6.0, macOS 14+, Swift 6 language mode)
Sources/
  ResoluteKit/               library — no UI
    Model/        Display, DisplayMode, ModeCatalog (grouping), ModeQuery (CLI matching),
                  MenuModel (pure menu tree), AspectRatio
    System/       SystemDisplayService (CoreGraphics), SkyLight (dlsym bridge),
                  PrivateModeRecord (pure decoder + validator), DisplayNames,
                  Mirroring, ConfigurationScope
    Overrides/    ScaleResolution (entry codec), DisplayOverride (plist model),
                  OverrideLocations, OverrideStore (read/scan), OverrideInstaller
                  (write/remove/back up through a CommandRunning), OverrideDraft
  resolute/                  CLI (swift-argument-parser)
  ResoluteApp/               AppKit menu-bar app + SwiftUI editor window
Tests/ResoluteKitTests/      Swift Testing; fixtures captured from this Mac
Resources/                   Info.plist template, AppIcon.icns
Scripts/                     build-app.sh, install.sh, uninstall.sh, make-icon.swift
Makefile                     build / test / app / install / uninstall / clean
```

### Units and their contracts

- **`DisplayMode`** (value, `Sendable`, `Codable`): `modeID` (IO display mode ID),
  `privateIndex?`, point size, pixel size, `refreshRate`, `bitsPerSample?`, `ioFlags`,
  `origin` (`.system` or `.hidden`). Derived: `scale`, `isHiDPI`, `isDefault`
  (flag 0x4), `isNative` (flag 0x0200_0000).
- **`Display`** (value): `id`, `name`, vendor/product/serial, `isBuiltin`, `isMain`,
  mirror state, `currentModeID`, `modes`, `privateModes` (trusted / untrusted with a
  reason / unavailable).
- **`PrivateModeRecord`**: decodes one 0xD4 record from raw bytes (pure, fixture-tested).
  `PrivateModeValidator` compares decoded records with public modes and answers
  "trusted?" plus the hidden extras.
- **`SkyLight`**: resolves the four private functions with `dlsym`; returns `nil` when
  any is missing. Allocates 0x100 zeroed bytes per record, requests 0xD4.
- **`SystemDisplayService`** (`DisplayControlling` protocol): `displays()` snapshot;
  `apply(modeID:to:scope:)` using `CGConfigureDisplayWithDisplayMode` for system modes
  and `CGSConfigureDisplayMode(privateIndex)` for hidden ones inside a
  `CGBeginDisplayConfiguration` transaction; `setMirroring(_:)` with
  `CGConfigureDisplayMirrorOfDisplay`. Scope maps to
  `.permanently` / `.forSession` / `.forAppOnly`.
- **`ModeCatalog`** (pure): groups modes by (points, pixels); per group picks the mode
  to apply — current refresh rate if offered, else the highest; prefers the current bit
  depth and system origin. Produces resolution sections and refresh options.
- **`MenuModel`** (pure): builds the whole menu as a tree of nodes with titles, badges,
  check states and typed actions from `[Display]` + settings + "option key held".
  The app renders it to `NSMenu`; `Resolute --dump-menu` prints it.
- **`ModeQuery`** (pure): parses `1920x1080`, `1920x1080@2x`, `@60`, `--refresh`,
  `--scale`, `--mode-id` and picks the best matching mode or explains why none match.
- **Override files**: `ScaleResolution` decodes each `scale-resolutions` entry:
  8 bytes → standard (pixels); 16 bytes with bit 0 of word 2 → HiDPI (pixels, shown as
  points = pixels / 2, flags kept); anything else (12/9-byte, non-HiDPI 16-byte,
  non-data) → preserved verbatim, shown read-only. Every entry is listed and written
  back exactly as listed, in the file's order, so a file reads back the way it was saved
  and a copy of Apple's file keeps Apple's order (see Revisions). A new entry goes where
  it sorts when the list is in RDM's order (standard entries, then HiDPI entries, each
  largest first), else at the end. Adding a HiDPI entry also adds a standard entry at its pixel
  size (RDM's pairing) unless one is listed; removing the HiDPI entry removes that
  partner only when the same edit added it, because a file cannot say why a standard
  entry is there (see Revisions). New HiDPI entries use flags `0x00000009 / 0x00A00000`
  (Apple's most common HiDPI combination). Unknown top-level keys are preserved; empty product names are omitted
  instead of written as `""`; a new file gets `target-default-ppmm` 10.01 as RDM's did,
  while an existing one (such as a copy of Apple's) keeps its own keys. Apple's 12-byte
  entries (pixel width, pixel height, flags) are kept byte for byte but count as the
  modes they name.
  Golden test: the owner's existing RDM-written file round-trips unchanged.
- **`OverrideInstaller`**: runs one shell script that carries the plist base64-encoded,
  so root never reads a file another process could swap. Under `umask 022` it copies an
  existing file to `/Library/Application Support/Resolute/Backups/` (claiming each
  backup name with an exclusive create, so overlapping installs keep every backup),
  writes the new file with `mktemp` beside the destination, sets mode 644 and renames it
  over the destination. The script runs through a `CommandRunning`: `AdminCommandRunner`
  (`osascript … with administrator privileges` and a prompt naming Resolute, waited on
  from a dedicated thread; user cancel is not an error), or `ShellCommandRunner`
  (`/bin/sh`, used under `sudo` and by tests against a temp root). Every path is
  single-quote escaped. CLI edits hold a lock (`overrides.lock` beside the backups), so
  overlapping commands keep each other's entries; the app's scripts take the same lock
  with `lockf`. Each change carries the state of the file it was based on, and the script
  refuses to act if the file no longer matches.

### App

- `main.swift` starts `NSApplication` with `.accessory` activation policy
  (`LSUIElement` in the bundle as well).
- `StatusMenuController` owns the `NSStatusItem` (SF Symbol `display`, template) and
  rebuilds the menu in `menuNeedsUpdate(_:)`, so it is always current; the screen-parameters
  change notification refreshes an open editor window.
- Mode changes run through `ModeChangeCoordinator` (hidden modes: session scope +
  countdown; others: permanent).
- `LoginItem` wraps `SMAppService.mainApp`.
- `OverrideEditorWindow`: SwiftUI in an `NSWindow`; sidebar of connected displays and
  existing overrides; table of custom resolutions with add/edit sheet (width, height,
  HiDPI, aspect-ratio helper, advanced flags); Save (admin prompt), Revert, Remove
  Override, Reveal in Finder. A banner explains that changes apply after reconnecting
  the display or restarting, and that Apple silicon Macs may ignore custom scaled
  resolutions for some displays.
- Diagnostics: `--dump-menu` prints the live menu tree; `--render-editor <png>` renders
  the editor offscreen (verification without opening windows on the owner's screen).

### CLI

```
resolute displays [--json]
resolute modes [-d <display>] [--all] [--raw] [--json]
resolute set [<WxH>] [--scale <n>] [--refresh <hz>] [--mode-id <id>] [--default]
             [-d <display>] [--session] [--allow-hidden]
resolute mirror on|off|toggle
resolute overrides list [--json]
resolute overrides show   (-d <display> | --vendor <hex> --product <hex>) [--json]
resolute overrides add    <WxH> [--standard] [--flags <hex>] (target) [--root <dir>]
resolute overrides remove <WxH> (target) [--root <dir>]
resolute overrides reset  (target) [--root <dir>]
```

Display selectors: `main`, a list index, `id:<number>`, or part of the name.
Write commands need root (run with `sudo`) unless `--root` points at a staging
directory.

## Error handling

- Typed `ResoluteError` cases: display not found / ambiguous, mode not found (with the
  closest alternatives), CoreGraphics error (named, not just a number), private API
  unavailable, override file unreadable, command failed (with stderr), cancelled.
- CLI: message on stderr, non-zero exit code. App: `NSAlert`; cancellation is silent.
- Private API absence or distrust is not an error: hidden modes are simply not shown
  (`resolute modes --all` says why).

## Testing and verification

- Unit (Swift Testing): record decoding and validation from fixtures captured on this
  Mac, grouping and representative-mode choice, menu tree, CLI query parsing and
  matching, override codec (including Apple's system file variants and the owner's
  real file), installer script construction and quoting, aspect ratios, revert
  countdown.
- Integration (opt-in `RESOLUTE_LIVE_TESTS=1`): enumerate real displays, check that the
  private decoder is trusted and agrees with the public API, apply a refresh-rate change
  with `.forAppOnly` scope and restore it, run the installer for real against a
  temporary root through `/bin/sh`.
- End to end: build the bundle, verify its signature, run the CLI (`displays`, `modes`,
  `set` a refresh rate for the session and back, `overrides list/show` against the real
  `/Library` file, `overrides add/remove --root <tmp>`), run `--dump-menu`, render the
  editor to PNG and inspect it, launch the agent and confirm it stays running.
- Owner-facing constraint: the owner may be watching full-screen video, so live tests
  change only the refresh rate, never the resolution, and always restore it.

## Publishing

`gh auth switch --user omar-hanafy`, then
`gh repo create omar-hanafy/Resolute --private --source . --push`.
Commit messages describe the change only (no tool attribution).

## Risks

- Private API layout may change again → runtime validation falls back to public-only.
- Custom scaled resolutions may be ignored on Apple silicon; they could not be verified
  on this Mac without an external display and a restart. The file format is verified
  against Apple's files and the owner's existing RDM file; the UI states the caveat.
- `SMAppService` with an ad-hoc signature may require approval in System Settings; the
  app surfaces the status instead of failing silently.

## Revisions

### 0.2 (2026-09-25)

- **Override lists show every entry.** 0.1 hid a standard entry at a HiDPI entry's
  pixel size as that entry's "backing" and rewrote it on save. The file cannot say why
  a standard entry is there, so the guess lost data: Apple's file for the built-in panel
  lists the native 3456 × 2234 at 1×, and adding 1728 × 1117 HiDPI and removing it again
  deleted that entry. The pairing now happens only when a HiDPI entry is added, as a
  visible row.
- **Apple's own entries are respected.** Apple's file for the built-in panel writes its
  HiDPI modes as 12-byte entries and has no `target-default-ppmm`; 0.1 duplicated those
  modes and added the density to every copy it saved.
- **Hidden-mode trials check that the display switched** before asking to keep the
  mode: `CGSConfigureDisplayMode` returns nothing, so a mode the display refused looked
  applied.
- **Input is bounded where it is parsed**: sizes up to 65535, refresh rates from 1 Hz to
  10 kHz, scales up to 8. Larger values overflowed later arithmetic and crashed.
- **Command-line errors come before any change**: contradictory `set` options, a scale
  or rate given twice, and bad hex IDs are usage errors of the subcommand.

### 0.3 (2026-09-25)

- **Entries keep the file's order.** 167 of the 251 files macOS 27 ships that list
  resolutions do not sort them the way RDM did, and nothing shows whether macOS cares, so
  an edit no longer re-sorts a copy of Apple's file. New entries go where they sort when
  the list is already sorted, else at the end. `ShippedOverrideTests` reads every file
  macOS ships and checks that Resolute writes each one back unchanged.
- **12-byte entries without the HiDPI bit are 1×.** macOS 27 ships 156 of them, all with
  flags 2 and classic 1× sizes (640 × 480 to 1920 × 1200), for example in the files for
  vendor 610, products b002 and b003. Two shipped files are lists of overrides chosen by
  display properties; Resolute reports them as not editable.
- **Case-sensitive volumes.** macOS looks for lowercase hexadecimal names, so an
  override is listed only when that name resolves: "DisplayVendorID-DB4" counts on the
  usual case-insensitive volume, and not on a case-sensitive one (checked on a
  case-sensitive APFS disk image).
- **Changes are based on what was read.** Every write carries the state of the file it
  was based on (absent, or its bytes); the privileged script compares with `cmp` and
  stops with status 3, reported as "changed after Resolute read it", before it backs up
  or writes anything. The command line holds `overrides.lock` itself. The app runs as the
  user and cannot create that file in `/Library/Application Support`, so its scripts take
  the same flock(2) lock with `lockf(1)`. osascript reports every failed script as status
  1; the script's own status and message are read from its report.
- **The editor asks before replacing a change made elsewhere.** It keeps the state of
  the installed file from its last read. Save, Remove Override… and Restore Backup…
  compare first and, before any password prompt, offer Save Anyway, Discard My Changes
  (Reload when there are none) or Cancel; the script checks again under the lock. The
  editor reads the file again when its window becomes key and when the app becomes
  active, and keeps unsaved changes under a banner rather than reloading over them. A
  restore compares with the file as it was when the backup list was read, because
  closing the sheet makes the window key, which would otherwise reload a changed file
  without a word.
- **Backups can be listed, restored and pruned.** Names stay in UTC so they sort by time
  whatever the time zone; listings show local time. A restore writes the backup's bytes
  as they are, and backs up what it replaces.
- **VoiceOver.** A table row is read from its first cell, which carries the whole row;
  sizes say "by", because "×" is read as "multiplied by". In the menu only the
  hidden-mode sign gets a description, as the other symbols repeat their item's title.
- **The editor's layout is tested without showing it.** A test lays the window out with
  40 rows, at its default and its minimum size, in a window that is never shown, and
  lists the views outside it. NavigationSplitView, which 0.1 dropped for pushing the
  buttons off the window, fails it. At the minimum size Revert and Save… move to a
  second row rather than cut button titles short.
- **JSON has every key.** A missing value is `null`, never an absent key
  ([docs/json.md](../json.md)).
- **Rates and scales are decimal numbers.** `Double(_:)` also read "0x3c" as 60.
- **Identical elements.** A file with the same element twice lists it once: rows need
  an identity, and none of Apple's 251 files repeats an element.
- **Hidden modes after logout (open).** WindowServer saves a display's mode by its
  attributes (`Wide`, `High`, `Hz`, `Depth`, `Scale` in
  `~/Library/Preferences/ByHost/com.apple.windowserver.displays.<UUID>.plist`), not by
  mode ID. Whether it brings back a mode only SkyLight lists depends on which list it
  matches against, which needs a display with hidden modes and a logout to find out;
  TESTING.md asks. Reapplying the mode at login is not built: it would show the
  Keep/Revert countdown at every login.

- **A revert waits for a display that dropped off.** A display that cannot show a mode may
  lose its link during the countdown. The revert then comes back as `restorePending`
  instead of failing, and is finished when the display returns. Only the trial is undone:
  a display that comes back in another mode it lists is left alone. The command line
  looks every half second for 30 seconds. The app listens for screen changes for 2
  minutes and shows nothing while the display is away, and a mode picked for that display
  meanwhile cancels the wait. Keep, chosen while the display is away, fails, since
  nothing could save the mode later. The answer itself is judged by what the display
  shows when it comes: a display that came back in another mode, or was switched
  elsewhere, is neither saved over nor switched back. The app tries a refused revert again
  every second, since a display that has only just returned may refuse a mode and then
  change nothing more. Mode choices made while a countdown is up are ignored, since a
  second alert or countdown over it would hold up its revert. `abortModal` ends the
  innermost modal session, so the countdown's timer ends it only while the countdown's own
  alert is on top, and otherwise waits for the other alert to close. In the terminal,
  Ctrl-C answers the prompt with no, and stops a wait for a display with the command that
  puts the previous mode back.
- **SkyLight is asked only about online displays.** For an ID it never saw,
  `CGDisplayIsOnline` answers -1 (4294967295 under Rosetta), and for a display that went
  away CoreGraphics keeps a 1×1 placeholder mode. So only an answer that is positive as a
  signed number counts, and it is checked right before each SkyLight call.
- **Screen names are read on the main thread.** The app reads NSScreen directly; the
  command line goes through `DispatchQueue.main.sync`, since its async `main` keeps the
  main queue running.
- **Logging.** Subsystem `com.omarhanafy.Resolute`, with two categories. `modes` covers
  switches, trials, reverts and waits. `overrides` covers each write, removal and backup
  deletion, or why it failed. Display names and paths are logged as public; `doctor`
  leaves serial numbers out, because people paste its report into public bug reports.
