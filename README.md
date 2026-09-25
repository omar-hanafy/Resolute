# Resolute

Pick any resolution and refresh rate for your Mac's displays from the menu bar, including the modes System Settings hides.

Resolute is a ground-up successor to [RDM](https://github.com/avibrazil/RDM). On current macOS, RDM misreads refresh rates (it shows 0 Hz and switches to 47.95 Hz when you pick a resolution) and cannot name displays on Apple silicon.

## What it does

- **Every mode in one menu.** HiDPI ("looks like") resolutions, low-resolution 1× modes such as your panel's full native resolution, and, while you hold ⌥, modes macOS lists nowhere.
- **Refresh rates.** Switch between 120, 60, 59.94, 50, 48 and 47.95 Hz, or whatever your display offers, without changing the resolution.
- **Safe hidden modes.** A hidden mode is tried for the current session and reverts after 15 seconds unless you choose Keep (in the menu) or type `y` (in the terminal), so a mode your display cannot show undoes itself.
- **Mirroring** on or off with one click.
- **Custom HiDPI resolutions** through display override files, like RDM's editor, with backups you can restore.
- **A command-line tool,** `resolute`, for scripts and shortcuts, with [JSON output](docs/json.md) and a `resolute doctor` report for bug reports.
- **Launch at Login.**

## Requirements

- macOS 14 Sonoma or later. Developed and tested on macOS 27 on Apple silicon; the Intel build is checked under Rosetta.
- To build: Xcode 16 or later (the package needs Swift 6.0). Only Xcode 27 (Swift 6.4) has been tested so far.

## Install

```sh
git clone https://github.com/omar-hanafy/Resolute.git
cd Resolute
make install
```

`make install` builds `dist/Resolute.app` (universal, signed ad hoc), copies it to `/Applications`, links the `resolute` command into `/usr/local/bin` when that folder is writable, and opens the app. `make app` only builds; the results are in `dist/`.

`make release` builds the universal app and packages `dist/Resolute-<version>.zip`, `dist/Resolute-<version>.dmg` and `dist/SHA256SUMS`. `SIGN_IDENTITY` sets the codesigning identity for `make app` and `make release` (default `-`, ad hoc; a real identity also turns on the hardened runtime). `NOTARY_PROFILE` names a keychain profile created with `xcrun notarytool store-credentials`; with it set, `make release` notarizes and staples the zip and dmg, which needs a Developer ID Application `SIGN_IDENTITY`. Without `NOTARY_PROFILE` the build is signed but not notarized, so macOS blocks a downloaded copy until you allow it in System Settings › Privacy & Security (Open Anyway).

If you used RDM, quit it and remove it from System Settings › General › Login Items. Resolute reads the override files RDM wrote.

To uninstall, run `make uninstall`. It quits the app, turns off Launch at Login, then removes the app and the command-line link. (An app older than 0.2 can't turn Launch at Login off for it, so the script says where to do that.)

## The menu

Click the display icon in the menu bar. Each display shows its current resolution and refresh rate; both open a submenu.

- **HiDPI** resolutions look sharp: macOS draws them at twice the size and scales the result to your panel.
- **Low Resolution (1×)** modes draw one pixel per point. On a Retina display this is how you get the panel's full native resolution (3456 × 2234 on a 16-inch MacBook Pro), at the cost of very small text. Turn the section off with **Show Low-Resolution Modes**.
- **Default** marks macOS's default mode and **Native** the panel's native size.
- Hold **⌥** while opening the menu to see hidden modes, mode IDs and pixel sizes. macOS may keep a hidden mode only until you log out, even after you choose Keep.

## The command line

```text
$ resolute
0  Built-in Retina Display  (id 1, vendor 610, product a050, main, built-in)
   1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54

$ resolute modes                  # grouped; --raw lists every mode, --all adds hidden ones
$ resolute set 1496x967           # keeps the current refresh rate
$ resolute set 3456x2234@1x       # the native resolution at 1×
$ resolute set --refresh 60       # keeps the resolution
$ resolute set --default
$ resolute set 1920x1080 -d DELL --session   # another display, until you log out
$ resolute set --mode-id <id> --allow-hidden  # a hidden mode from `resolute modes --all --raw`: kept only if you type y
$ resolute mirror toggle
$ resolute displays --json
$ resolute doctor                 # versions, displays, modes and overrides, for a bug report
```

`-d` takes `main`, an index from `resolute displays`, `id:<number>`, or part of a display's name. `resolute help <command>` explains the rest.

With `--json`, every key is always present, with `null` when there is no value; [docs/json.md](docs/json.md) lists them. Vendor and product IDs are hex strings, the way `--vendor` and `--product` take them. `resolute --generate-completion-script zsh` (or `bash`, `fish`) prints shell completions.

## Custom resolutions

macOS reads per-display override files from `/Library/Displays/Contents/Resources/Overrides`. The **Custom Resolutions…** window, and `resolute overrides`, edit the `scale-resolutions` list in those files, so you can add modes a display does not offer, such as 2560 × 1080 HiDPI on a 5120 × 2160 monitor.

- The list shows every entry in the file, in the file's order. Adding a HiDPI resolution also adds a 1× entry at its rendered size, as RDM did, unless the list has one; removing the HiDPI entry removes that 1× entry only if it was added with it in the same edit. Removing a 1× entry that a HiDPI entry renders at gets a note, with a way to put it back.
- Saving asks for an administrator password. The file being replaced is first copied to `/Library/Application Support/Resolute/Backups`. **Restore Backup…** (or `sudo resolute overrides restore`) puts one back, and `sudo resolute overrides prune` deletes old ones.
- If the file changed after you opened it, for example through `resolute overrides`, Resolute reads it again or, when you have unsaved changes, asks before saving over it.
- New modes appear after you reconnect the display or restart the Mac.
- On Apple silicon Macs, macOS may ignore custom scaled resolutions for some displays.
- **Remove Override…** (or `sudo resolute overrides reset -d <display>`) deletes the file and returns the display to its defaults.

```sh
resolute overrides list
sudo resolute overrides add 2560x1080 -d DELL              # HiDPI, looks like 2560 × 1080
sudo resolute overrides add 3440x1440 --standard -d DELL   # a 1× mode
sudo resolute overrides remove 2560x1080 -d DELL
sudo resolute overrides reset -d DELL
resolute overrides backups -d DELL                      # newest first
sudo resolute overrides restore 1 -d DELL               # puts the newest back
sudo resolute overrides prune --keep 5 --all            # deletes older backups
```

## How it works

Resolute asks CoreGraphics for every mode, including the low-resolution duplicates it usually hides. It also reads the private SkyLight mode list that RDM relied on, which can include modes CoreGraphics leaves out. Before trusting that list, Resolute decodes every record and checks it against CoreGraphics; if the record layout changes in a future macOS, hidden modes disappear instead of showing wrong values. Listed modes are switched with the public `CGConfigureDisplayWithDisplayMode`; only hidden ones use `CGSConfigureDisplayMode`.

The macOS 27 record layout is documented in [docs/design/2026-09-25-resolute-design.md](docs/design/2026-09-25-resolute-design.md). [docs/new-macos-release.md](docs/new-macos-release.md) lists what to check on each new macOS release, starting with `swift Scripts/capture-mode-fixture.swift`, which dumps a display's raw records.

## Development

```sh
make build       # swift build
make test        # unit tests (Swift Testing): the library, the command line and the editor
make lint        # shellcheck on the scripts
make live-test   # also switches the main display's refresh rate for a moment and back
make app         # dist/Resolute.app and dist/resolute
make release     # dist/Resolute-<version>.zip, .dmg and SHA256SUMS
make icon        # regenerates Resources/AppIcon.icns
```

[TESTING.md](TESTING.md) lists the checks that need a person and a screen. [CHANGELOG.md](CHANGELOG.md) lists what changed in each version.

CI (`.github/workflows/ci.yml`) lints and runs the tests on every push and pull request, but only while the repo is public; while it's private, a run only happens when a maintainer starts one by hand.

`Resolute.app/Contents/MacOS/Resolute --dump-menu` prints the menu as it would appear, and `--render-editor file.png` captures the Custom Resolutions window without showing it (the terminal needs the Screen Recording permission).

## Credits

Resolute is new code. The idea and the override-file format come from RDM by Avi Alkalay and its forks, including usr-sse2's resolution editor; display mirroring follows fcanas/mirror-displays.

## License

MIT. See [LICENSE](LICENSE).
