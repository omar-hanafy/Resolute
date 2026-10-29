# Testing Resolute

## Automated

```sh
make test        # the library, the command line and the editor's model, against fakes
make lint        # shellcheck on the scripts
make live-test   # also switches the main display's refresh rate for a moment and back
```

Target an external display explicitly; the main screen may still be the built-in one:

```sh
RESOLUTE_LIVE_DISPLAY=GM34-CWQ make live-test
RESOLUTE_LIVE_DISPLAY=GM34-CWQ RESOLUTE_LIVE_SCALES=2752x1152,2408x1008 make live-test
```

The optional scale list selects each listed size without specifying a refresh rate, checks that the original rate is retained, and reverts after each trial. `RESOLUTE_LIVE_HIDDEN_MODE=<fresh-mode-id>` opts into one inspected hidden mode; this requires a second unmirrored display. Read `resolute modes -d <display> --all --raw` immediately before selecting an ID. Do not reuse IDs across connections. All live tests use process-lifetime configuration and return to the captured starting mode.

## By hand

See [the current production review](docs/production-readiness.md) for checks actually completed and remaining release gates. Apple silicon is the primary test target; `UNIVERSAL=1` is optional compatibility packaging.

The automated tests can't see the screen, so these checks need a person, and some need an external display. Run them after `make install`, with RDM quit and removed from Login Items.

### The panel and the menu bar icon

- [ ] Clicking the icon opens the panel under it; clicking elsewhere, Esc or another app closes it. ⌃⌥R opens it from anywhere.
- [ ] Each display has a card with its picture; a stop under Larger Text ↔ More Space switches at once and becomes the selected one. A refresh rate switches without changing the size.
- [ ] All Resolutions lists the HiDPI and Low Resolution (1×) sizes; Back returns to the cards. Holding ⌥ while clicking the menu bar icon shows hidden modes once, with pixel sizes and mode numbers; opening the panel with ⌃⌥R does not.
- [ ] A preset chip applies the preset; **+** saves the current setup as a new one.
- [ ] After `resolute set <size> -d <display>` in Terminal, the panel shows that change with Undo, and Undo puts the previous mode back.
- [ ] Right-click and Control-click open the classic menu: sizes at hand, More Resolutions, Refresh Rate, Mirror Displays, Open Resolute, Settings… (⌘,), Quit Resolute (⌘Q).
- [ ] Settings › General › Show the resolution next to the icon shows it in the menu bar.
- [ ] VoiceOver reads the icon, each card, stop and row; the icon's Actions menu offers the classic menu.

### The window

- [ ] The panel's title, a card and Settings… open the window on the right page; Resolute is in the Dock and ⌘Tab only while it is open. ⌘Q closes it, and Quit Resolute or ⌃⌥⌘Q quits.
- [ ] The first time the window closes, a note points at the menu bar icon; it doesn't come back.
- [ ] The sidebar lists the displays, displays that aren't connected but have an override file, Presets, History and Settings.
- [ ] Welcome shows on the first launch from Finder, not at login.
- [ ] The Dock icon's menu (while the window is open) applies presets and switches sizes.
- [ ] In a display page's All Modes, after clicking a row, ↑ and ↓ outline the next row without switching; Return or Space switches to it.

### Two displays

- [ ] Both displays have a card and a sidebar page; **Mirror Displays** mirrors them into one card and turns mirroring off again.
- [ ] `resolute displays` lists both, and `resolute set <size> -d <part of the name>` switches the external one.

### Hidden modes (only displays that have them)

- [ ] A hidden mode chosen in the panel or the window shows "Keep this display setting?" on that display, with a countdown and the previous mode named. Doing nothing, Return or Esc brings the previous mode back and shows "Switched back"; Keep keeps it and shows "Kept".
- [ ] A mode the display can't show comes back by itself when the countdown ends.
- [ ] A display that drops off during the countdown and reconnects comes back in its previous mode, with no alert while it is away; the panel shows Waiting with Stop Waiting, and the icon a waiting state. The app waits up to two minutes for it; `resolute set` says it is waiting and gives up after 30 seconds.
- [ ] With the app running, `resolute set --mode-id <id> --allow-hidden` from an agent's shell shows the same dialog naming the agent and its terminal; Keep, Revert, no answer and Ctrl-C in the agent's shell each end it, and `--json` says how. With Settings › Command Line & Agents set to Don't allow, the command changes nothing.
- [ ] `kill -9` of that command while its dialog is up puts the previous mode back for the session, and History says the trial was switched back. With the display unplugged meanwhile, the panel shows Waiting, and the mode comes back once the display does.
- [ ] Without the app, `resolute set --mode-id <id> --allow-hidden` asks in the terminal: `y` keeps the mode; anything else, Ctrl-C or 15 seconds reverts it. With neither the app nor a terminal, nothing changes.
- [ ] After Keep, log out and back in: the hidden mode is gone, as the Kept notice says.
- [ ] Quit Resolute with a pending restore asks first (Keep Running is the default); after Quit Anyway, History says the previous mode was not put back.
- [ ] While a countdown is up, an alert from elsewhere (an agent notification's Undo, a failed Sharp Scaling write) waits until the countdown is over.
- [ ] A display reconnected with changed display/mode IDs restores only a uniquely identified matching display and mode. Another monitor reusing an ID is not changed.

### Presets, History and shortcuts

- [ ] Presets: New Preset from Current Setup, Apply, Rename…, Delete… and a shortcut that applies the preset from anywhere. `resolute preset list` shows the same presets. After `resolute preset delete <name>`, the deleted preset's shortcut applies nothing and says why.
- [ ] History lists switches from the panel, the window, the classic menu, the Dock, Terminal and agents, with who asked; Undo puts back what a change replaced; `resolute history` agrees.

### Shortcuts and Spotlight (the app built by `Scripts/build-app.sh`, in /Applications)

- [ ] The Shortcuts app lists Resolute's actions: Apply Preset, Set Resolution, Set Refresh Rate, Mirror Displays, Get Displays and Open Resolute, worded as in Figma (Apply Resolute preset *Coding*, Set resolution of *display* to *size*, …).
- [ ] Each runs: a preset applies, a size and a rate switch the display named, mirroring turns on and off, Get Displays returns both displays with their modes, Open Resolute opens the window. With Resolute not running, the first action launches it and runs.
- [ ] Set Resolution offers only the sizes the chosen display lists, never its hidden ones; Set Refresh Rate only the rates at its current size.
- [ ] History shows each change from Shortcuts with Shortcuts as the source, its Shortcuts filter appears, and Undo puts the change back.
- [ ] While a hidden mode's Keep/Revert countdown is up, running an action fails with "Resolute is asking whether to keep a display setting…" and changes nothing.
- [ ] On macOS 26 or later, Spotlight shows Resolute's actions; typing a size (such as 1496) offers "Set 1496 × 967", which switches the display that has it. Siri runs "Apply Coding with Resolute".

### Sharp Scaling (a standard 1080p or 1440p monitor)

- [ ] The monitor's panel card offers Set Up Sharp Scaling…; its × hides the offer for that monitor only.
- [ ] The setup sheet lists five sizes and what this Mac can draw; Add N Sizes… asks for the password and writes the override with a backup. The page then says it is saved and waits for a reconnect.
- [ ] After reconnecting, the page says Sharp Scaling is ready (or which sizes macOS skipped), the card shows Larger Text ↔ More Space with the Sharp badge, and with "Switch to the sharp … when it's ready" the monitor switched once, with Undo in the panel.
- [ ] Remove… (or Undo Setup… before the reconnect) puts the file from before back. `resolute scaling status -d <monitor>` agrees with the page at each step.

### Settings

- [ ] Launch at Login shows up in System Settings › General › Login Items and survives a restart.
- [ ] Command Line & Agents › Install… links `resolute` into `/usr/local/bin`, asking for the password only when needed; Uninstall… removes only Resolute's link.
- [ ] About shows the version.

### Custom resolutions (an external display; Apple silicon may ignore scaled ones)

- [ ] **Custom Resolutions…** in the panel opens the main display's Custom Resolutions tab; a not connected display's page opens on it.
- [ ] Adding a HiDPI resolution also adds its 1× partner row, unless the list has one. Revert undoes both.
- [ ] **Save…** asks for the administrator password, and the dialog names Resolute. Cancel leaves everything as it was.
- [ ] After a save, reconnecting the display or restarting shows the new resolution in the menu.
- [ ] **Remove Override…** deletes the file. A copy is in `/Library/Application Support/Resolute/Backups`.
- [ ] Selecting rows and pressing Delete removes exactly those rows; Revert brings them back and clears the selection.
- [ ] A display whose override file can't be read shows why, with Show in Finder, and Remove Override… when it is a file.
- [ ] Unsaved changes stay while you switch pages, tabs and displays, and quitting with them asks first.
- [ ] Picture & Name: choosing a picture and a name and saving writes them with the custom resolutions; after reconnecting, System Settings › Displays shows that picture and name.
- [ ] With the editor open, run `sudo resolute overrides add 1920x1080 -d <display>` in Terminal and come back: the editor shows the new entry. With unsaved changes it keeps them under a banner instead, and **Save…** first asks whether to save anyway, discard the changes or cancel.
- [ ] Removing a 1× row that a HiDPI row renders at shows a note under the table. **Add 1× Entry** puts the row back.
- [ ] **Restore Backup…** lists the backups newest first, in local time, with what each holds. It is greyed while there are unsaved changes. Restoring one asks for the password, and the backups then include the file it replaced.
- [ ] With VoiceOver on (⌘F5), an editor row reads as one line, such as "1280 by 800, HiDPI, rendered at 2560 by 1600", and a hidden mode in the classic menu (with ⌥ held) is read with its "Hidden" badge.
- [ ] `sudo resolute overrides add 2560x1080 -d <display>` and `… remove …` behave the same, and `resolute overrides list` shows the result.
- [ ] `resolute overrides backups -d <display>` lists the backups with local times. `sudo resolute overrides restore 1 -d <display>` puts the newest back, and `sudo resolute overrides prune --keep 1` deletes the others.
- [ ] Removing a 1× entry that a HiDPI entry renders at (`sudo resolute overrides remove 2560x1440@1x` after adding 1280x720) says so and how to put it back.

### Install and uninstall

- [ ] `make install` with the old app running replaces it and opens the new one.
- [ ] If the old app is asking about unsaved custom resolutions, `make install` stops and says so.
- [ ] `make uninstall` turns off Launch at Login and removes the app and the `resolute` link. Overrides and backups stay.

If something misbehaves, include the output of `resolute doctor` (and `resolute modes --all --raw` for mode problems) when you report it, and what Resolute logged: `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h`.
