# Changelog

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
