# JSON output

The commands that take `--json` print one JSON value to standard output. Every key listed here is always present. A value that is unknown or does not apply is `null`; keys are never left out. Later versions may add keys, but a key keeps its meaning.

## `resolute displays --json`

An array with one object per online display, in the order `resolute displays` lists them.

| Key | Type | Meaning |
|---|---|---|
| `index` | number | Position in the list, as `-d <index>` takes it. |
| `id` | number | CoreGraphics display ID, as `-d id:<id>` takes it. |
| `name` | string | The display's name. When two displays share a name, " (1)", " (2)" and so on tell them apart. |
| `vendorID`, `productID` | string | Hexadecimal, as `--vendor`, `--product` and override file names use them. |
| `serialNumber` | number | 0 when the display reports none. |
| `isMain`, `isBuiltin`, `isInMirrorSet` | boolean | |
| `currentMode` | mode or null | See [Modes](#modes). Null when macOS reports a mode Resolute cannot find. |
| `modeCount` | number | Every mode, hidden ones included. |
| `hiddenModeCount` | number | Modes only the private SkyLight list has. |
| `hiddenModes` | string | `available`, `unavailable`, or `ignored: <reason>` when the private records do not agree with CoreGraphics. |

## `resolute modes --json`

An object:

| Key | Type | Meaning |
|---|---|---|
| `display` | string | The display's name. |
| `displayID` | number | |
| `currentModeID` | number or null | |
| `hiddenModes` | string | As in `displays`. |
| `modes` | array of modes | Hidden modes only with `--all`. |

### Modes

| Key | Type | Meaning |
|---|---|---|
| `modeID` | number | IO display mode ID, as `resolute set --mode-id` takes it. |
| `privateIndex` | number or null | Position in SkyLight's list, when its records are trusted. |
| `width`, `height` | number | Size in points. |
| `pixelWidth`, `pixelHeight` | number | Size in pixels: twice the points for HiDPI modes. |
| `refreshRate` | number | Hertz, rounded to thousandths; 0 when the display reports none. |
| `bitsPerSample` | number or null | Bits per colour component, when the private record confirms it. |
| `ioFlags` | number | IOKit mode flags: 0x4 marks the default mode and 0x2000000 the native one. |
| `origin` | string | `system` when CoreGraphics lists the mode, `hidden` when only SkyLight does. |

## `resolute set --json`

An object, printed once the change is over: at once for a listed mode, and after the trial for a hidden one. A hidden mode needs a person to keep it. When the Resolute app is running, it asks in a dialog on the display, and the command waits for the answer; otherwise the command asks in the terminal, and without one it changes nothing and fails.

Standard output carries only this object. What the command is doing, such as `Waiting up to 15 s for someone at the display to keep it…`, goes to standard error, and so does the terminal's Keep prompt when standard output is not a terminal. A command that fails prints no JSON, so check the exit status first.

| Key | Type | Meaning |
|---|---|---|
| `display` | string | The display's name. |
| `mode` | string | The mode asked for, as `WIDTHxHEIGHT` in points. |
| `hidden` | boolean | Whether the mode is hidden, so a person had to keep it. |
| `result` | string or null | `applied` when the display switched without a trial, or already used the mode; `kept` when a person kept the hidden mode on trial; `reverted` when the previous mode is back. Null with `--dry-run`, which changes nothing. |
| `keptBy` | string or null | `person` when a person kept the mode: in the app's dialog on the display, or by typing y in the terminal. Null otherwise. |
| `until` | string or null | `logout` when the mode lasts until you log out: every kept hidden mode, and a listed mode with `--session`. Null for a mode saved like a change in System Settings, and when nothing changed. |
| `reason` | string or null | Why the mode was reverted, in words: `no answer in 15 s`, `reverted by person`, `interrupted` (Ctrl-C, a closed terminal or a request to quit), `not kept` (answered in the terminal), or a problem with the app. Null unless `result` is `reverted`. Scripts should rely on `result`; the words may change. |
| `restored` | string or null | After a revert, the mode the display is back in, as `WIDTHxHEIGHT`. Null when it is unknown, or nothing was reverted. |

## `resolute overrides list --json` and `show --json`

`list` prints an array of overrides; `show` prints one.

| Key | Type | Meaning |
|---|---|---|
| `vendorID`, `productID` | string | Hexadecimal. |
| `path` | string | The file: the installed one, the one macOS ships, or where one would be installed. |
| `source` | string | `installed`, `system` (only the file macOS ships) or `missing`. |
| `connectedDisplay` | string or null | The connected display the override belongs to. |
| `connectedDisplayID` | number or null | |
| `productName` | string or null | The name the override gives the display. |
| `entries` | array of entries | In the file's order. |
| `problem` | string or null | Why the file cannot be read. |

### Entries

| Key | Type | Meaning |
|---|---|---|
| `kind` | string | `hidpi`, `standard` (1×), or `preserved` for an element that names no mode. |
| `width`, `height` | number or null | Points for HiDPI entries, pixels for 1× ones. |
| `pixelWidth`, `pixelHeight` | number or null | The pixels macOS renders. |
| `flags` | string or null | A HiDPI entry's two flag words, such as `00000009 00a00000`. Null for other kinds and for Apple's 12-byte entries. |
| `keptAsIs` | boolean | True for an element Resolute writes back byte for byte because it does not write that form itself. |
| `summary` | string | The line `overrides show` prints. |

## `resolute overrides backups --json`

An array of the display's backups, newest first.

| Key | Type | Meaning |
|---|---|---|
| `number` | number | 1 for the newest, as `overrides restore` takes it. |
| `date` | string | When the backup was made: ISO 8601, in UTC. |
| `fileName`, `path` | string | |
| `entries` | number or null | How many entries it holds; null when Resolute cannot read them. |
| `productName` | string or null | |
| `problem` | string or null | Why its entries cannot be read. `restore` still writes such a backup back as it is when it holds a property list, as a file that lists several overrides does. |

## `resolute preset list --json`, `show`, `save`, `delete` and `rename`

`list` prints an array of presets in their saved order; the others print one preset (`delete`
the one it deleted). Each also says what applying it would do with the displays connected now.

| Key | Type | Meaning |
|---|---|---|
| `id` | string | The preset's UUID. |
| `name` | string | Unique among presets, ignoring case. |
| `summary` | string | The line on the preset's card, such as `Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz`. |
| `shortcut` | string or null | The keyboard shortcut as menus show it, such as `⌃⌥1`. |
| `mirroring` | boolean or null | Whether the preset turns mirroring on or off; null when it leaves mirroring as it is. |
| `mirroringStatus` | string | `leftAlone`, `inUse` (already as the preset says), `turns` (applying turns it on or off) or `notPossible` (on, with fewer than two displays). |
| `isActive` | boolean | True when the current setup matches: every display the preset names is connected and in its mode, and mirroring is as it says. |
| `displays` | array of settings | In the preset's order. |

### Preset settings

| Key | Type | Meaning |
|---|---|---|
| `name` | string | The display's name when the preset was saved. |
| `vendorID`, `productID` | string | Hexadecimal, as in `displays --json`. |
| `serialNumber` | number | 0 when the display reports none. |
| `isBuiltin` | boolean | |
| `width`, `height` | number or null | The resolution in points; null when the preset keeps the display's current one. |
| `pixelWidth`, `pixelHeight` | number or null | The pixels it is drawn with, twice the points for HiDPI; null when either scale will do. |
| `refreshRate` | number or null | Hertz; null when the preset keeps the current rate (or takes the fastest, when the resolution changes). |
| `summary` | string | Such as `DELL U2723QE 2560 × 1440 at 60 Hz`. |
| `connectedDisplay` | string or null | The connected display the setting is for: the same unit by serial number, else the same model, else the built-in display or one with the same name. |
| `connectedDisplayID` | number or null | |
| `currentMode` | mode or null | That display's mode now. See [Modes](#modes). |
| `mode` | mode or null | The mode applying would use: the saved size, pixel size and rate, else the closest rate at that size. Always one macOS lists, never a hidden one. Null when the setting can't apply. |
| `status` | string | `inUse`, `switches`, or why it can't apply: `notConnected`, `resolutionNotOffered`, `currentModeUnknown` or `currentResolutionHidden`. |
| `reason` | string or null | Why it can't apply, in words. |

## `resolute preset apply --json`

An object. With `--dry-run`, the preset as `show --json` prints it, and nothing changes.

| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `succeeded` | boolean | False when a switch or mirroring failed, or when nothing in the preset applies to the displays connected now; the command then exits with status 1. |
| `changed` | boolean | Whether anything changed. |
| `mirroring` | boolean or null | As in the preset. |
| `mirroringResult` | string | `leftAlone`, `alreadyInUse`, `turned`, `notPossible` or `failed`. |
| `mirroringReason` | string or null | Why mirroring was not changed, or what failed. |
| `displays` | array | One object per setting: its keys from `name` to `refreshRate`, `summary`, `connectedDisplay`, `connectedDisplayID`, `result`, `reason`, `previousMode` and `mode`. |

`result` is `switched`, `alreadyInUse`, a `status` reason from above, `failed`, `wentAway` (switched,
but the display went away before it could be checked) or `showsOtherMode` (macOS accepted the
switch, but the display shows another mode). `previousMode` is the mode before; `mode` is the one
switched to, or already in use.

## `resolute history --json`

An array of the changes History lists, newest first, after `--source` and `--limit`. An Undo is the `undone` status of the change it undid, not an item of its own.

| Key | Type | Meaning |
|---|---|---|
| `id` | string | The change's ID. |
| `date` | string | When the change ended: ISO 8601, in UTC. |
| `source` | string | Where it was asked for: `panel`, `menu`, `window`, `dock`, `keyboard` (a shortcut that works from anywhere), `terminal` (a person running `resolute`), `agent` or `shortcuts`. |
| `agent` | string or null | The agent that ran `resolute`, such as `Claude Code`. |
| `app` | string or null | The terminal or app `resolute` ran in, such as `Terminal`. |
| `preset` | string or null | The preset that made the change. |
| `change` | string | `mode` or `mirroring`. |
| `display`, `displayID` | string or null, number or null | The display a mode change was on, as it was named and numbered then. |
| `from`, `to` | history mode or null | A mode change's mode before (null when unknown) and after. |
| `mirroring` | boolean or null | True when mirroring was turned on, false when off; null for a mode change. |
| `mirroredDisplays` | array of strings or null | The displays a mirroring change involved. |
| `hiddenMode` | boolean | True when the change switched to a hidden mode. |
| `outcome` | string | `applied`, `kept`, `keptForSession`, `reverted`, `failed`, or `undone` for an Undo whose change is no longer in History. |
| `reason` | string or null | Why a reverted change was put back: `noAnswer`, `declined`, `displayWentDark`, `displayChanged` or `unspecified`. |
| `message` | string or null | Why a failed change did not happen. |
| `status` | string | What History shows: `kept`, `reverted`, `undone` or `failed`. |
| `canUndo` | boolean | Whether History offers Undo for it. |
| `undoneAt`, `undoneFrom` | string or null | When it was undone (ISO 8601, UTC) and from where, as `source` names it. |
| `undoes` | string or null | For an Undo whose change is no longer in History: that change's ID. |
| `title`, `detail` | string | The two lines History shows. |

### History modes

| Key | Type | Meaning |
|---|---|---|
| `modeID` | number | The mode ID then; it can change when the display reconnects. |
| `width`, `height` | number | Size in points. |
| `pixelWidth`, `pixelHeight` | number | Size in pixels. |
| `refreshRate` | number | Hertz, rounded to thousandths; 0 when the display reports none. |
| `hidden` | boolean | True for a mode only SkyLight lists. |

## `resolute scaling plan --json` and `status --json`

One line of JSON with its keys in the order shown, as the Sharp Scaling design prints them.
Sizes are written `WIDTHxHEIGHT` in points, as `resolute set` takes them.

`plan --json`:

| Key | Type | Meaning |
|---|---|---|
| `display` | string | The display's name. |
| `panel` | string | The panel's own size in pixels, the last of the sharp sizes. |
| `limit` | object or null | The widest and tallest image this Mac draws for the display (`width`, `height`); null when macOS publishes no limit. |
| `sizes` | array | From Larger Text to More Space: `size`, `drawn` (the pixels it is drawn with, twice the size), `textLarger` (percent) and `fits` (false when it is past the limit and left out). |

`status --json`:

| Key | Type | Meaning |
|---|---|---|
| `display` | string | The display's name. |
| `scaling` | string | `off`, `waiting` (saved, waiting for the display to reconnect), `on` or `partial` (macOS skipped some sizes). |
| `saved` | number | How many sharp sizes the override holds. |
| `available` | number | How many of them macOS offers now. |
| `skipped` | array of strings | The sizes macOS left out after reading the file. |
| `current` | string or null | The display's size now. |
| `hidpi` | boolean or null | Whether the size in use is drawn at 2×. |

## `resolute doctor --json`

An object:

| Key | Type | Meaning |
|---|---|---|
| `version` | string | Resolute's version. |
| `macOS` | string | Such as `27.0 (26A428)`. |
| `model` | string | Such as `Mac14,10`. |
| `architecture` | string | `arm64` or `x86_64`. |
| `translated` | boolean | True when an Intel build runs under Rosetta. |
| `privateModeFunctions` | boolean | Whether the private SkyLight mode functions exist. |
| `displays` | array | One object per display: `display` (as in `displays --json`, without `serialNumber`, since people paste this report into public bug reports), `override` (`source`, `path`, `entries`, `problem`, as above) and `backups` (a count). |
| `otherOverrides` | array | Installed overrides for displays that are not connected: `vendorID`, `productID`, `path`, `entries`, `problem` and `backups`. |
