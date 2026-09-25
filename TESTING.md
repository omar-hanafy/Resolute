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
- [ ] `resolute modes --all --raw` lists the hidden modes. `resolute set --mode-id <id> --allow-hidden` asks in the terminal: `y` keeps the mode, anything else or 15 seconds reverts it.
- [ ] Unplugging the display during the countdown and plugging it back in brings the previous mode back, in the menu and in the terminal.
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
- [ ] `sudo resolute overrides add 2560x1080 -d <display>` and `… remove …` behave the same, and `resolute overrides list` shows the result.
- [ ] `resolute overrides backups -d <display>` lists the backups with local times. `sudo resolute overrides restore 1 -d <display>` puts the newest back, and `sudo resolute overrides prune --keep 1` deletes the others.
- [ ] Removing a 1× entry that a HiDPI entry renders at (`sudo resolute overrides remove 2560x1440@1x` after adding 1280x720) says so and how to put it back.

### Install and uninstall

- [ ] `make install` with the old app running replaces it and opens the new one.
- [ ] If the old app is asking about unsaved custom resolutions, `make install` stops and says so.
- [ ] `make uninstall` turns off Launch at Login and removes the app and the `resolute` link. Overrides and backups stay.

If something misbehaves, include the output of `resolute doctor` (and `resolute modes --all --raw` for mode problems) when you report it.
