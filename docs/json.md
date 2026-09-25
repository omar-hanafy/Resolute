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
| `entries` | number or null | How many entries it holds; null when it cannot be read. |
| `productName` | string or null | |
| `problem` | string or null | Why it cannot be read. |

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
| `displays` | array | One object per display: `display` (as in `displays --json`), `override` (`source`, `path`, `entries`, `problem`, as above) and `backups` (a count). |
| `otherOverrides` | array | Installed overrides for displays that are not connected: `vendorID`, `productID`, `path`, `entries`, `problem` and `backups`. |
