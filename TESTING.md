# Testing Resolute

## Automated

```sh
make test        # the library, the command line and the editor's model, against fakes
make lint        # shellcheck on the scripts
make live-test   # also switches the main display's refresh rate for a moment and back
```

## By hand

The automated tests can't see the screen, so these checks need a person, and some need an external display. Run them after `make install`, with RDM quit and removed from Login Items.

### Menu

- [ ] The menu-bar icon opens a menu listing each display with its resolution and refresh rate.
- [ ] Choosing another HiDPI resolution switches to it, and the menu then shows it checked.
- [ ] Choosing another refresh rate keeps the resolution.
- [ ] **Show Low-Resolution Modes** adds and removes the 1× section. The native size (3456 × 2234 on a 16-inch MacBook Pro) switches and comes back.
- [ ] Holding ⌥ while opening the menu shows mode IDs and pixel sizes, plus hidden modes when the display has any.
- [ ] **Launch at Login** shows up in System Settings › General › Login Items and survives a restart.
- [ ] **About Resolute** shows the version, and **Quit Resolute** (⌘Q) quits.

### Two displays

- [ ] Both displays are listed, each with its own submenus.
- [ ] **Mirror Displays** mirrors them and turns mirroring off again.
- [ ] `resolute displays` lists both, and `resolute set <size> -d <part of the name>` switches the external one.

### Hidden modes (only displays that have them)

- [ ] With ⌥ held, a hidden mode (marked ⚠) switches and shows "Keep this display mode?" with a countdown.
- [ ] Doing nothing, pressing Return or pressing Escape brings the previous mode back. Keep keeps the new mode.
- [ ] A mode the display can't show comes back by itself when the countdown ends.
- [ ] A display that drops off during the countdown and reconnects comes back in its previous mode, with no alert while it is away. The app waits up to two minutes for it; `resolute set` says it is waiting and gives up after 30 seconds.
- [ ] `resolute modes --all --raw` lists the hidden modes. `resolute set --mode-id <id> --allow-hidden` asks in the terminal: `y` keeps the mode, anything else or 15 seconds reverts it.
- [ ] After Keep, log out and back in. Note whether the hidden mode is still in use: macOS saves modes by size and refresh rate, and may not bring back one it does not list.

### Custom resolutions (an external display; Apple silicon may ignore scaled ones)

- [ ] **Custom Resolutions…** opens the editor on the display chosen in the menu.
- [ ] Adding a HiDPI resolution also adds its 1× partner row, unless the list has one. Revert undoes both.
- [ ] **Save…** asks for the administrator password, and the dialog names Resolute. Cancel leaves everything as it was.
- [ ] After a save, reconnecting the display or restarting shows the new resolution in the menu.
- [ ] **Remove Override…** deletes the file. A copy is in `/Library/Application Support/Resolute/Backups`.
- [ ] Selecting rows and pressing Delete removes exactly those rows; Revert brings them back and clears the selection.
- [ ] A display whose override file can't be read shows why, with Show in Finder, and Remove Override… when it is a file.
- [ ] Switching displays, or quitting, with unsaved changes asks first.
- [ ] At the window's smallest size every button title is whole: Revert and **Save…** move to a second row.
- [ ] With the editor open, run `sudo resolute overrides add 1920x1080 -d <display>` in Terminal and come back: the editor shows the new entry. With unsaved changes it keeps them under a banner instead, and **Save…** first asks whether to save anyway, discard the changes or cancel.
- [ ] Removing a 1× row that a HiDPI row renders at shows a note under the table. **Add 1× Entry** puts the row back.
- [ ] **Restore Backup…** lists the backups newest first, in local time, with what each holds. It is greyed while there are unsaved changes. Restoring one asks for the password, and the backups then include the file it replaced.
- [ ] With VoiceOver on (⌘F5), an editor row reads as one line, such as "1280 by 800, HiDPI, rendered at 2560 by 1600", and a hidden mode in the menu (with ⌥ held) is read as "Hidden mode".
- [ ] `sudo resolute overrides add 2560x1080 -d <display>` and `… remove …` behave the same, and `resolute overrides list` shows the result.
- [ ] `resolute overrides backups -d <display>` lists the backups with local times. `sudo resolute overrides restore 1 -d <display>` puts the newest back, and `sudo resolute overrides prune --keep 1` deletes the others.
- [ ] Removing a 1× entry that a HiDPI entry renders at (`sudo resolute overrides remove 2560x1440@1x` after adding 1280x720) says so and how to put it back.

### Install and uninstall

- [ ] `make install` with the old app running replaces it and opens the new one.
- [ ] If the old app is asking about unsaved custom resolutions, `make install` stops and says so.
- [ ] `make uninstall` turns off Launch at Login and removes the app and the `resolute` link. Overrides and backups stay.

If something misbehaves, include the output of `resolute doctor` (and `resolute modes --all --raw` for mode problems) when you report it, and what Resolute logged: `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h`.
