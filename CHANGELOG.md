# Changelog

## Unreleased

### Fixed

- Ctrl-C at `resolute set`'s Keep prompt ended the command and left the hidden mode in place until you logged out, which is worst when the mode shows nothing. Ctrl-C now counts as no and reverts. While `set` waits for a display that went away, Ctrl-C stops the wait after one last try and prints the command that puts the previous mode back.
- When a hidden mode never showed and its display went away and came back, `resolute set` reported the error before saying how the display came back.
- An alert opened over the Keep/Revert countdown was closed by the countdown's timer in place of the countdown, which then stayed on screen without reverting. The countdown now waits for that alert to close, then reverts.

## 0.3.0 — 2026-09-25

### Added

- Backups: `resolute overrides backups` lists a display's backups with their local dates, `restore` puts one back byte for byte (backing up the file it replaces) and `prune` deletes all but the newest. In the app, **Restore Backup…** in the editor does the same, showing what each backup holds.
- The editor notices when its override changed on disk, through another app or the `resolute` command. It reads the file again when you come back to it, keeps unsaved changes under a banner, and asks before saving over the new version.
- A note when an edit leaves a HiDPI entry without the 1× entry at its pixel size, which Resolute and RDM add with each HiDPI entry. The editor offers **Add 1× Entry**; `resolute overrides remove` prints the command that puts it back.
- `resolute doctor`: a read-only report for bug reports, with versions, displays, modes, overrides and backups, also as JSON. It leaves out serial numbers.
- Logging: each mode switch and each change to an override file, or why it failed. `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h` shows the last hour.
- VoiceOver: an editor row reads as one line, such as "1280 by 800, HiDPI, rendered at 2560 by 1600", the display list says which displays are connected and have an override, and the menu names hidden modes.
- `docs/json.md` documents every key of the JSON output, and `docs/new-macos-release.md` what to check on each new macOS release.

### Fixed

- A display can drop off while it tries a hidden mode it cannot show. Resolute then reported a failed revert, and the display could come back in that mode. Now the revert waits for the display and puts the previous mode back when it returns: up to two minutes in the app, which shows nothing meanwhile and tries a refused mode again every second, and 30 seconds in `resolute set`. A display that comes back in another mode is left alone, as is one you have picked a new mode for.
- Keep saved the mode on trial even when, by the time you answered, the display had come back in another mode or been switched elsewhere, which switched it back to a mode that may have made it drop off. Keep and Revert now go by what the display shows when you answer: a display showing another mode keeps it.
- After a revert that failed, Resolute suggested `resolute set --default`, which saves the default mode over the one you had. It now says that logging out brings back the mode macOS saved, and `resolute set` prints the command that puts the previous mode back.
- Resolute could ask the private SkyLight functions about a display that had just gone away. Each call now checks first that the display is still online.
- The command line read screen names from AppKit off the main thread.
- Next to a display really named "Studio (1)", two displays named "Studio" could both be called "Studio (1)".
- Saving a copy of Apple's override re-sorted its entries. 167 of the 251 files macOS 27 ships that list resolutions use an order of their own; Resolute now keeps each file's order.
- The app and `sudo resolute overrides …` could both edit an override at the same time, and a save in one silently replaced a change made in the other. Every change now checks that the file is still what it was based on, and the app takes the command line's lock.
- Under a strict umask, the first `sudo resolute overrides …` made `/Library/Application Support/Resolute` readable only by root, which hid the backups from the app. It is now made readable by everyone. A folder made that way keeps its permissions; `sudo chmod 755 "/Library/Application Support/Resolute"` fixes it.
- `@0x3c`, `--refresh 6e1` and other non-decimal numbers were read as rates and scales (0x3c is 60).
- `resolute set 2992x1934@2x` did not suggest 1496 × 967 HiDPI, the mode that renders at that size.
- On a case-sensitive volume, an override folder named in uppercase, which macOS does not read, was listed.
- An override entry with a size a file cannot hold crashed instead of reporting an error.
- A failed privileged script reported osascript's wrapper ("0:204: execution error: … (1)") instead of its own message.

### Changed

- Keep, chosen after the display went away during the countdown, now says the mode was not saved and lasts at most until you log out.
- A mode chosen in the menu while the Keep/Revert countdown is up is ignored: its own alert or countdown would have stopped the first one from reverting.
- JSON output always has every documented key, with `null` for a missing value.
- `resolute modes` labels a resolution Default or Native, like the menu, instead of listing both.
- The ⌥ hint in the menu counts the resolutions it reveals, not every hidden mode.
- `resolute overrides reset` says how to undo it.
- At its smallest size the editor moves Revert and Save… to a second row instead of cutting button titles short.
- `make release` builds the zip, the disk image and their checksums, with the version's notes for a GitHub release, and `SIGN_IDENTITY` signs with a real certificate. CI lints and tests on the oldest and newest supported Xcode.

## 0.2.0 — 2026-09-25

### Fixed

- Crashes on sizes, rates and scales no display has, such as `resolute set 9223372036854775807x2`, `@1e300` or `--scale inf`. Sizes up to 65535, rates from 1 Hz to 10 kHz and scales up to 8 are accepted.
- Custom resolutions: adding a HiDPI entry and removing it again could delete a 1× entry the file already had, such as Apple's native 3456 × 2234 for the built-in panel. The list now shows every entry in the file.
- Apple's own HiDPI modes, which its file for the built-in panel writes as 12-byte entries, could be added a second time, and `remove` could not find them. They now count as the modes they name and are still written back byte for byte.
- Saving a copy of Apple's file added `target-default-ppmm` 10.01. Apple's file for the built-in panel has no such key, and it can change which mode macOS makes the default. Only overrides created from scratch get it now. If you saved a copy of Apple's file with 0.1.0, Remove Override… (or `sudo resolute overrides reset`) goes back to macOS's own.
- A hidden mode the display refused still showed the Keep/Revert countdown. Resolute now gives the display half a second to switch, and if it doesn't, puts the previous mode back and says so.
- `resolute set --allow-hidden --session` kept a hidden mode without asking. The prompt now runs for every hidden mode; `--session` only limits how long a confirmed one lasts.
- Keeping a hidden mode in the terminal warned that macOS reported a different mode.
- Waiting for the administrator password held a thread that other work needed.
- Only osascript's own "User canceled. (-128)" counts as a cancelled password prompt.
- An override file that can't be read (permissions, or a folder in its place) was reported as an invalid property list.
- Override folders named with leading zeros, which macOS never reads, were listed under another path.
- Backups made by overlapping saves could overwrite each other, and overlapping `resolute overrides` commands could lose each other's entries. A backup that could not be made failed with only "status 1", and a failed copy left an empty backup.
- `resolute overrides reset` said it removed an override that didn't exist.
- `resolute set` accepted contradictory options (`--mode-id` with a resolution, `--refresh` next to `@60`, `@60@50`) and implausible ones (`--refresh 0`), and a mistyped option was reported as "Give a resolution". These are now usage errors, reported before anything changes. Every command-line mistake now exits with status 64 and shows the command's usage.
- Invalid `--vendor` or `--product` hex showed the usage of `resolute` instead of the subcommand's.
- The editor: row selection followed positions, so after Revert, Remove could delete a different entry. An unreadable override left the editor on "No Display Selected". The hidden flags field could block adding a 1× entry.
- The app started the menu-bar agent for `--details` and other unknown diagnostic flags.
- `install.sh` could open the new app before the old one had quit, and install and uninstall could sit silent for two minutes while the app asked about unsaved changes. The `sudo ln` hint failed when `/usr/local/bin` didn't exist.

### Changed

- The password dialog says "Resolute wants to change a display override in /Library/Displays." instead of naming osascript.
- Adding a HiDPI custom resolution also adds its 1× partner as a visible row, unless the list has one. Removing the HiDPI entry removes that partner only when the same edit added it.
- Error messages name what was kept and what is on offer: "1728 × 1117 HiDPI has no 55 Hz mode. It offers 120 Hz and 60 Hz."
- `resolute overrides` messages name the display they change and say when the change takes effect. `remove` works on a display whose override is still the one macOS ships, as `add` does, and never suggests removing an entry that file lists.
- A mistyped command gets a suggestion: `resolute mode` → `resolute modes`, `resolute reset` → `resolute overrides reset`, `resolute overrides ad` → `add`.
- A command waiting for another one to finish editing overrides says so, and gives up after a minute.
- JSON: vendor and product IDs are hex strings everywhere. `modes --json` is an object with the display, its current mode ID and the modes. Override `source` is `installed`, `system` or `missing`, with the connected display's ID.
- In the Keep/Revert countdown, Escape reverts like Return. In the editor, Delete removes the selected rows.
- `make uninstall` quits the app, turns off Launch at Login (an app older than 0.2 can't, so the script says where to do it) and removes the app. `make lint` runs shellcheck on the scripts.

## 0.1.0 — 2026-09-25

First release: a menu-bar app and the `resolute` command-line tool for macOS 14 and later, rebuilt from scratch to replace RDM on macOS 27.
