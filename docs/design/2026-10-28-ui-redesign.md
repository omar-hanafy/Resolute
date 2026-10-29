# Resolute UI redesign (October 2026)

The UI and UX refresh designed in Figma ([Resolute](https://www.figma.com/design/84S2G57E0NBXaPpaVxg8C7/Resolute),
"UI and UX redesign for macOS 27 Golden Gate · 27 October 2026"), rebuilt on the
existing core. This document is the build's single source of truth: module layout,
design-system rules, the Figma map and the behavior of the features the design adds.

## Principles (from the Figma cover)

- **Menu bar first.** The panel switches modes in one click; the window is for deeper work.
- **Speak human.** "Larger Text ↔ More Space" and pictures, not mode numbers.
- **Safe by default.** Hidden modes are tried on their own display. Revert is the default.
- **Agent-friendly.** Everything works from `resolute`. Agents can ask; people keep.
- **Native.** macOS materials, controls and type; Light, Dark and the glass slider.

## Modules

| Target | Role | Depends on |
| --- | --- | --- |
| `ResoluteKit` | Displays, modes, switching, overrides, presets, history, Sharp Scaling plans, the agent channel. No UI. | — |
| `ResoluteDesign` | The design system: tokens, materials, pictures, components, the component catalog. AppKit and SwiftUI only; it knows nothing about displays. | — |
| `ResoluteApp` | The menu-bar app: composition root and features. | Kit, Design |
| `resolute` | The command-line tool. | Kit, ArgumentParser |

`ResoluteDesign` components take plain values (strings, enums, booleans, closures),
never Kit types; the app maps Kit models to them.

## Source tree

```
Sources/ResoluteDesign/
  Tokens/        Palette (Color) + NSPalette (NSColor), TextStyle (type scale), Metrics, Symbol (SF Symbols)
  Materials/     GlassBackground (Liquid Glass on 26+, visual effect before), WallpaperBackdrop (gallery only)
  Pictures/      DisplayPicture (7 models), SpaceThumbnail (5 stops), AppIconView
  Assets/        Embedded artwork (generated; sources in Design/)
  Components/
    Controls/    Badge, SegmentedTabs, SectionLabel, Banner, buttons, HUD, progress, shortcut labels
    Panel/       Status item images, panel surface and rows, display card, stops, presets, activity, mode rows
    Window/      Sidebar items, display header, picture choice, space option, form rows, tables, unsaved bar, history row, preset card
  Catalog/       CatalogScene + DesignCatalog: every component state, for the gallery
Sources/ResoluteApp/
  App/           main, AppDelegate, main menu, app model and environment
  Shell/         status item, panel host, window host, activation policy (Dock while the window is open)
  MenuBar/       panel content, All Resolutions, classic (right-click) menu
  Trial/         Keep/Revert dialog on the tried display, HUDs, quit confirmations
  Window/        sidebar, routing, toolbar
  Displays/      display page: header, tabs, Resolution, Custom Resolutions, Picture & Name, sheets
  Presets/  History/  Shortcuts/  Settings/  Onboarding/  SharpScaling/  Integrations/
  ModeChanges/   ModeChangeCoordinator (switching, trials, waiting reverts)
  Diagnostics/   --version, --dump-menu, --render-gallery, --unregister-login-item
  Gallery/       GalleryRenderer, WindowCapture, AppGallery, Scenes/ (one file per owner)
Sources/ResoluteKit/
  Model/ System/ Overrides/   (existing)
  Presentation/  space stops, display facts, picture suggestion, sample displays
  Presets/ History/ Scaling/ Agents/ Support/
Design/          source artwork exported from Figma (embedded into ResoluteDesign/Assets)
```

## Design-system rules

- Colors come from `Palette` (SwiftUI) or `NSPalette` (AppKit). Never a literal color in a
  view. Kit colors (labels, accents, window background) are the system colors; Resolute's
  surfaces and strokes carry Figma's Light and Dark values.
- Text uses `.textStyle(_:)` with a `TextStyle` from the Figma type scale, in SF Pro.
  Figma draws Inter as a stand-in; its letter spacing is not carried over.
- Sizes and spacing come from `Metrics`. Symbols come from `Symbol`.
- Selection and primary actions use the person's accent color (`Palette.accent`).
- Every component has catalog scenes for each state in Figma, rendered in Light and Dark.
- Artwork (display pictures, app icon) is embedded as data in Swift, not as SwiftPM
  resources: SwiftPM's `Bundle.module` looks for its bundle at the root of the `.app`,
  where it can't be signed, and falls back to a build-folder path that doesn't exist on
  other Macs.

## Checking against Figma

`Resolute --render-gallery <folder> [--only <id-prefix>,…] [--appearance light|dark|both]`
renders every catalog and app scene to `<id>.<appearance>.png` without showing anything
(the window is ordered in below the desktop picture and captured by ScreenCaptureKit; the
terminal needs the Screen Recording permission). `--list-gallery` lists the scenes with
their Figma nodes. Compare each with its Figma frame in both appearances.

## Platform notes

- Deployment target macOS 14; builds with Xcode 16.0 (Swift 6.0, macOS 15 SDK) through
  Xcode 27. Guard runtime availability with `if #available`, and APIs that older SDKs
  lack with `#if compiler(>=6.2)` (macOS 26 SDK: `NSGlassEffectView`, `.glassEffect`)
  or `#if compiler(>=6.4)` (macOS 27 SDK: `NSStatusItem.expandedInterfaceDelegate`).
- The panel: on macOS 27 the status item's `expandedInterfaceDelegate` drives it, so it
  opens, closes and takes the keyboard like a system menu; before, an `NSPanel` under the
  item. Right-click opens the classic `NSMenu` (keyboard and VoiceOver users).
- macOS 27 hides menu item images by default; the classic menu has none.

## Figma map

| Area | Nodes |
| --- | --- |
| Foundations | page 8:3 — type scale 48:546, colors 48:594 / 48:659, icons 48:725, metrics 48:1022 |
| Components | page 8:4 — pictures 50:704 (display pictures 9:56, space thumbnails 9:297, icons), shared controls 50:705 (badge 17:15, segment 17:20, banner 17:115), panel 50:706 (status item 17:135, section label 17:61, panel row 17:60, display card 18:27 and 59:704, preset chip 17:78, activity row 17:63, mode row 17:100, panels 20:156 and 22:369), window 50:707 (sidebar 18:129 / 18:128, picture choice 18:147, space option 18:176, form row 19:160, table 19:161 / 19:197, unsaved bar 19:198, history row 36:445, preset card 36:475), desktop and app icon 50:708 |
| Menu bar panel | page 8:6 — two displays 23:557, one display 23:818, All Resolutions 23:1079, waiting 24:1157, mirroring 24:1435, light 24:1754, classic menu 25:1842, status item states 25:2439, first close 25:2477 |
| Hidden-mode trial | page 8:7 — dialog 28:5, agent request 28:82, quit while waiting 28:132, switched back 29:68, kept 29:78, terminal 29:94 |
| Window | page 8:8 — Resolution 31:5, Custom Resolutions 34:332, Picture & Name 34:866, Add Resolution 35:784, Restore Backup 35:1103, Remove Override 35:1414, not connected 37:1480, History 37:1957, Presets 37:2289, light 38:3760 |
| Settings and onboarding | page 8:9 — Welcome 40:5, General 40:149, Command Line & Agents 42:295, About 42:789 |
| System integrations | page 8:10 — Dock menu 44:76, Control Center 44:755, Shortcuts 45:262, Spotlight 45:442 |
| App icon | page 8:11 — master 46:5, appearances 46:15, menu bar icon 46:104 |
| Sharp Scaling | page 60:543 — panel before 60:547 / after 60:873, page off 62:1020, setup sheet 66:1271, saved 67:1585, ready 67:2175, terminal 68:2029, partial 68:2089 |

## Behavior the design adds

- **Panel.** One card per display, the one in use first: picture, current mode, five
  "Larger Text ↔ More Space" stops that switch at once, refresh rates in one row, All
  Resolutions (every mode, HiDPI and 1× tabs, hidden modes on request or with ⌥, each
  tried for the trial length first). Presets, the last outside change with Undo, Mirror
  Displays, Custom Resolutions…, Settings… (⌘,), Quit Resolute (⌘Q). Mirroring shares one
  card; a revert waiting for its display shows on its card with Stop Waiting.
- **Status item.** A template `display` symbol; orange with a countdown on every display
  during a trial; an optional resolution next to it; a waiting state.
- **Window.** One page per display (Resolution, Custom Resolutions, Picture & Name), not
  connected displays with overrides, Presets, History, Settings. Resolute is in the Dock
  and ⌘Tab while the window is open; ⌘Q closes the window and Quit in the panel quits
  (⌃⌥⌘Q too). The first close points at the menu bar icon once.
- **Trial.** Keep/Revert on the display being tried, the trial length (15 s by default)
  with a progress bar, Revert the default button (Return and Esc revert). A HUD says
  "Switched back" or "Kept" for two seconds. Requests from `resolute` show the same dialog
  and name who asked; only a person can keep.
- **Presets.** A mode for every display (and mirroring), applied from the panel, the Dock,
  a shortcut, or `resolute preset apply`. Listed modes only.
- **History.** Every switch from the panel, menu, window, Dock, command line and agents,
  kept 7 days, with Undo. The command line writes it too.
- **Picture & Name.** A picture ("skin") and name written to the display's override
  file with its custom resolutions.
- **Sharp Scaling.** Retina-style sizes for standard 1080p and 1440p monitors, written to
  the override file, checked after the display reconnects; `resolute scaling`.
- **Settings.** General (Launch at Login, menu bar, panel shortcut, low-resolution and
  hidden modes, trial length), Command Line & Agents (install `resolute`, agent rules,
  instructions to give an agent), About. **Welcome** on the first deliberate launch.

## Decisions made while building

- **One model, many views.** `AppModel` (App/AppModel*.swift) owns the displays, every switch
  (through `ModeChangeCoordinator`), presets, History and presentation (`facts`, `stops`,
  `skin`); views pass where a request came from (`from: .panel`, `.window`, `.menu`, `.dock`,
  `.keyboard`, `.shortcuts`) so History can say it.
- **Kept means until logout.** A hidden mode kept from the app or the command line lasts until
  logout; it is never saved for good, as the Kept notice says.
- **⌥ held while clicking the menu bar icon** shows hidden modes once and adds mode numbers
  and pixel sizes to All Resolutions, so both Settings' and the panel's wording hold. Only a
  click counts: the panel's shortcut (⌃⌥R by default) holds ⌥ itself, so Settings and the
  panel say "clicking the menu bar icon" where Figma says "opening the panel".
- **The classic menu** (25:1842): each display's sizes at hand (a Retina display's Larger Text ↔
  More Space stops; another display's default and native sizes, and the one in use), More
  Resolutions, Refresh Rate: N Hz; then Mirror Displays, Open Resolute, Settings… and Quit
  Resolute. No item images; hidden modes carry a "Hidden" badge.
- **Custom Resolutions is a tab**, with Picture & Name on the same draft: `DisplayEditors`
  keeps one editor per display while the app runs, so unsaved changes survive page switches,
  closing the window and unplugging, and quitting asks about them.
- **Agents.** `resolute set --allow-hidden` asks the app over the agent channel; the app shows
  the trial dialog naming the agent, and only a person can keep. Settings › Command Line &
  Agents › Don't allow turns the command away at `hello`, before anything changes, and turns
  a request away too. While a request's dialog is up, the app starts no trial of its own,
  and the other way round. A command killed with its dialog up has its previous mode put
  back for the session, as its own revert would: else the display's default mode, never the
  mode on trial, and a display that is away is waited for as the app's own trials are.
  History says how its trial ended.
- **Nothing over the countdown.** An alert, or a switch of its own, opened over the modal
  Keep/Revert dialog would hold up its revert until closed. So while a switch is under way,
  alerts, Sharp Scaling's switch after a reconnect, the restore for a vanished command and a
  notification's Undo wait (`ModeChangeCoordinator.afterSwitch`) and run once it is over.
- **Every trial in History.** A trial whose display went dark is recorded once its revert
  stops waiting, however that ends: the display back, Stop Waiting, given up, replaced by
  a new choice or a preset, or Resolute quitting. A display that takes the ID of one still
  away keeps that one's revert waiting. Undo from a notification follows the panel's rule:
  not once the display was changed again.
- **One override write at a time.** Custom Resolutions, Picture & Name and Sharp Scaling
  each ask for the administrator password; while one write is under way the others write
  nothing and say why, and quitting is refused.
- **All Modes and the keyboard.** Choosing a row switches the display, so ↑ and ↓ only
  highlight a row and Return or Space chooses it (`DataTable(choosesWithReturn:)`).
- **What Settings can't promise.** The JSON row says most commands take `--json` (`mirror`
  and the commands that write overrides or Sharp Scaling don't), and the agent instructions
  say every command they list but `mirror` does. Show Resolute in the menu bar doesn't say
  "On": macOS lets people hide the item, and Resolute can't read whether they did.
- **Orange text.** Text in the warning color (Unsaved, Failed, Hidden) uses
  `Palette.warningText`, darker than Figma's orange in Light so it reads at 4.5:1 or more;
  symbols keep the system orange.
- **System integrations.** Shortcuts and Spotlight (App Intents) need metadata a pure SwiftPM
  build doesn't produce yet, and Control Center needs a sandboxed widget extension SwiftPM can't
  package; the findings and the build changes they would need are in
  `Sources/ResoluteApp/Integrations/README.md`. Until then no copy offers them, and
  History's Shortcuts filter shows only once History has a change from Shortcuts.
