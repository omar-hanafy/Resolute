# Resolute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Resolute, a menu-bar display-mode switcher and CLI for macOS 14+ (verified on macOS 27) that replaces the abandoned RDM, and publish it privately under `omar-hanafy`.

**Architecture:** One Swift package. `ResoluteKit` holds all logic: mode discovery through public CoreGraphics plus a runtime-validated private SkyLight decoder, mode grouping, a pure menu model, CLI query parsing, and the display-override file codec and installer. The thin `resolute` CLI (swift-argument-parser) and `ResoluteApp` (AppKit status item + SwiftUI editor) sit on top. A script assembles and ad-hoc signs `Resolute.app`.

**Tech Stack:** Swift 6.4 toolchain (language mode 6), SwiftPM, CoreGraphics, AppKit, SwiftUI, ServiceManagement, swift-argument-parser 1.5+, Swift Testing.

**Spec:** `docs/design/2026-09-25-resolute-design.md`

## Global Constraints

- `swift-tools-version: 6.0`; `platforms: [.macOS(.v14)]`; Swift 6 language mode with strict concurrency, no warnings suppressed.
- Names: product **Resolute**, bundle id `com.omarhanafy.Resolute`, CLI `resolute`, library `ResoluteKit`, version `0.1.0` (single source: `Sources/ResoluteKit/Version.swift`).
- Private API use is limited to `CGSGetNumberOfDisplayModes`, `CGSGetDisplayModeDescriptionOfLength`, `CGSGetCurrentDisplayMode`, `CGSConfigureDisplayMode` (resolved with `dlsym`) and `CoreDisplay_DisplayCreateInfoDictionary` (names only).
- Private records are used only after `PrivateModeValidator` trusts them; otherwise the app behaves as public-API-only.
- Override files: `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>` (lowercase hex, no padding); backups in `/Library/Application Support/Resolute/Backups`.
- New HiDPI entries use flags `00000009 00a00000`; empty product names are omitted; `target-default-ppmm` defaults to `10.01` when resolutions exist.
- Live tests touch only the refresh rate, always restore it, and run only with `RESOLUTE_LIVE_TESTS=1`.
- Commit messages describe the change only — no tool or assistant attribution.

## Review Focus

1. **Current mode missing from the mode list** (hidden or unknown current mode): the menu must render with no checkmark and no crash — pinned in Task 5 (`MenuModelTests.rendersWithoutACurrentMode`).
2. **Displays that report 0 Hz for every mode** (some virtual and older panels): no "0 Hz" text and no refresh submenu — pinned in Task 5 (`MenuModelTests.omitsRefreshRateWhenUnknown`) and Task 1 (`formatsRefreshRates`).
3. **Two identical monitors**: names must be told apart ("DELL U2720Q (1)", "(2)") — pinned in Task 2 (`DisplayNamesTests.disambiguatesIdenticalNames`).
4. **Malformed override files** (not a plist, or `scale-resolutions` of the wrong type): readable error, nothing dropped or overwritten silently — pinned in Task 6 (`DisplayOverrideTests.keepsAWrongTypedResolutionsKey`, `OverrideStoreTests.reportsUnreadableFiles`).
5. **Paths containing spaces or quotes** in the staging, backup or override locations: the installer's shell script must still target the right files — pinned in Task 7 (`OverrideInstallerTests.handlesPathsWithQuotesAndSpaces`).

## File Structure

```
Package.swift
Sources/ResoluteKit/
  Version.swift                       version string
  Model/DisplayMode.swift             DisplayMode, RefreshRate
  Model/Display.swift                 Display, PrivateModeStatus
  Model/ResoluteError.swift           ResoluteError, CGErrorName
  Model/ModeCatalog.swift             ResolutionGroup, ResolutionSection, RefreshOption, ModeCatalog
  Model/ModeQuery.swift               ModeQuery (CLI/mode matching)
  Model/DisplaySelector.swift         DisplaySelector
  Model/MenuModel.swift               MenuAction, MenuItem, MenuNode, MenuSettings, LaunchAtLoginState, MenuModel
  Model/AspectRatio.swift             AspectRatio
  Model/RevertCountdown.swift         RevertCountdown
  System/PrivateModeRecord.swift      PrivateModeRecord, PrivateModeValidation, PrivateModeValidator
  System/SkyLight.swift               SkyLight (dlsym bridge)
  System/ConfigurationScope.swift     ConfigurationScope
  System/MirroringPlan.swift          MirroringPlan
  System/DisplayNames.swift           DisplayNames
  System/SystemDisplayService.swift   DisplayControlling, SystemDisplayService
  Overrides/ScaleResolution.swift     HiDPIFlags, ScaleResolution, PreservedEntry, ScaleResolutionCodec
  Overrides/DisplayOverride.swift     OverrideKey, PropertyListDictionary, DisplayOverride
  Overrides/OverrideStore.swift       OverrideLocations, OverrideStore
  Overrides/CommandRunning.swift      CommandRunning, ShellCommandRunner, AdminCommandRunner, Shell, AppleScript
  Overrides/OverrideInstaller.swift   OverrideInstaller
  Overrides/OverrideDraft.swift       OverrideDraft
Sources/resolute/                     CLI: ResoluteCommand, DisplaysCommand, ModesCommand, SetCommand,
                                      MirrorCommand, OverridesCommand, Output
Sources/ResoluteApp/                  main, AppDelegate, StatusMenuController, MenuRenderer,
                                      ModeChangeCoordinator, ConfirmationPanel, LoginItemController,
                                      Preferences, Alerts, AboutPanel, Diagnostics,
                                      CustomResolutions/{Model, View, WindowController, Snapshot}
Tests/ResoluteKitTests/               Swift Testing suites + Support/TestData.swift + Fixtures/*.json
Resources/                            Info.plist (template), AppIcon.icns
Scripts/                              capture-mode-fixture.swift, make-icon.swift, build-app.sh,
                                      install.sh, uninstall.sh
Makefile, README.md, LICENSE, .gitignore
```

Code blocks that create files are preceded by an HTML comment `<!-- file: PATH | task: N | kind: test|impl -->`
so they can be materialised mechanically; the visible text above each block names the file too.

---
### Task 1: Package scaffold, core value types, captured fixture

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/ResoluteKit/Version.swift`, `Sources/ResoluteKit/Model/DisplayMode.swift`, `Sources/ResoluteKit/Model/Display.swift`, `Sources/ResoluteKit/Model/ResoluteError.swift`, `Scripts/capture-mode-fixture.swift`, `Tests/ResoluteKitTests/Fixtures/m2pro-builtin-macos27.json` (generated), `Tests/ResoluteKitTests/Support/TestData.swift`
- Test: `Tests/ResoluteKitTests/DisplayModeTests.swift`

**Interfaces:**
- Produces: `ResoluteVersion.string`; `DisplayMode` (`modeID: Int32`, `privateIndex: Int32?`, `width/height/pixelWidth/pixelHeight: Int`, `refreshRate: Double`, `bitsPerSample: Int?`, `ioFlags: UInt32`, `origin: .system | .hidden`, derived `scale`, `isHiDPI`, `isDefault`, `isNative`, `refreshKey`, `sizeText`, `pixelSizeText`); `RefreshRate.key(_:) -> Int`, `RefreshRate.format(_:) -> String`; `Display` (`id`, `name`, `vendorID`, `productID`, `serialNumber`, `isBuiltin`, `isMain`, `mirrorSourceID`, `isInMirrorSet`, `currentModeID`, `modes`, `privateModes`, derived `currentMode`, `hiddenModeCount`); `PrivateModeStatus` (`.unavailable`, `.untrusted(reason:)`, `.trusted`); `ResoluteError` (cases listed in the file) conforming to `LocalizedError`; `CGErrorName.name(for:)`. Test helpers `CapturedDisplay.load()`, `.records`, `.modes`, `.display(currentModeID:)`, `TestData.mode(...)`, `TestData.fullHD(...)`, `TestData.uhd(...)`, `TestData.bytes(hex:)`.

- [ ] **Step 1: Create the package manifest and ignore file**

Create `Package.swift` (the CLI and app targets are added in Tasks 8 and 9):

<!-- file: Package.swift | task: 1 | kind: impl -->
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Resolute",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResoluteKit", targets: ["ResoluteKit"]),
    ],
    targets: [
        .target(name: "ResoluteKit"),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

Create `.gitignore`:

<!-- file: .gitignore | task: 1 | kind: impl -->
```gitignore
.build/
.swiftpm/
dist/
xcuserdata/
*.xcodeproj
.DS_Store
```

- [ ] **Step 2: Capture the mode fixture from this Mac**

Create `Scripts/capture-mode-fixture.swift`:

<!-- file: Scripts/capture-mode-fixture.swift | task: 1 | kind: impl -->
```swift
#!/usr/bin/env swift
// Captures the main display's public modes and raw private SkyLight mode records as
// JSON, for Resolute's decoder tests. Read-only: it never changes a display.
//
//   swift Scripts/capture-mode-fixture.swift > Tests/ResoluteKitTests/Fixtures/<name>.json
import CoreGraphics
import Foundation

typealias ModeCount = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
typealias ModeDescription = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void

let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
guard let countSymbol = dlsym(everyImage, "CGSGetNumberOfDisplayModes"),
      let descriptionSymbol = dlsym(everyImage, "CGSGetDisplayModeDescriptionOfLength")
else {
    FileHandle.standardError.write(Data("The SkyLight mode functions are unavailable.\n".utf8))
    exit(1)
}
let modeCount = unsafeBitCast(countSymbol, to: ModeCount.self)
let modeDescription = unsafeBitCast(descriptionSymbol, to: ModeDescription.self)

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []

var count: Int32 = 0
modeCount(display, &count)
var records: [String] = []
for index in 0..<count {
    var buffer = [UInt8](repeating: 0, count: 0x100)
    buffer.withUnsafeMutableBytes { modeDescription(display, index, $0.baseAddress!, 0xD4) }
    records.append(buffer.prefix(0xD4).map { String(format: "%02x", $0) }.joined())
}

var modelSize = 0
sysctlbyname("hw.model", nil, &modelSize, nil, 0)
var modelBytes = [CChar](repeating: 0, count: modelSize)
sysctlbyname("hw.model", &modelBytes, &modelSize, nil, 0)
let model = modelBytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }

let fixture: [String: Any] = [
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
    "model": model,
    "currentModeID": CGDisplayCopyDisplayMode(display)?.ioDisplayModeID ?? -1,
    "systemModes": modes.sorted { $0.ioDisplayModeID < $1.ioDisplayModeID }.map { mode -> [String: Any] in
        [
            "modeID": mode.ioDisplayModeID,
            "width": mode.width,
            "height": mode.height,
            "pixelWidth": mode.pixelWidth,
            "pixelHeight": mode.pixelHeight,
            "refreshRate": (mode.refreshRate * 1_000).rounded() / 1_000,
            "ioFlags": mode.ioFlags,
        ]
    },
    "privateRecords": records,
]
let json = try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
```

Run:

```bash
mkdir -p Tests/ResoluteKitTests/Fixtures
swift Scripts/capture-mode-fixture.swift > Tests/ResoluteKitTests/Fixtures/m2pro-builtin-macos27.json
python3 -c "import json;d=json.load(open('Tests/ResoluteKitTests/Fixtures/m2pro-builtin-macos27.json'));print(d['model'],d['currentModeID'],len(d['systemModes']),len(d['privateRecords']))"
```

Expected: `Mac14,10 54 132 132`.

- [ ] **Step 3: Write the failing tests**

Create `Tests/ResoluteKitTests/Support/TestData.swift`:

<!-- file: Tests/ResoluteKitTests/Support/TestData.swift | task: 1 | kind: test -->
```swift
import CoreGraphics
import Foundation
@testable import ResoluteKit

/// Modes captured from the built-in display of a MacBook Pro 16" (M2 Pro) on macOS 27.0
/// with `Scripts/capture-mode-fixture.swift`.
struct CapturedDisplay: Decodable {
    struct SystemMode: Decodable {
        let modeID: Int32
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Double
        let ioFlags: UInt32
    }

    let macOS: String
    let model: String
    let currentModeID: Int32
    let systemModes: [SystemMode]
    /// Raw private records in list order, hex encoded.
    let privateRecords: [String]

    static func load() throws -> CapturedDisplay {
        guard let url = Bundle.module.url(
            forResource: "m2pro-builtin-macos27", withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw FixtureError.missing
        }
        return try JSONDecoder().decode(CapturedDisplay.self, from: Data(contentsOf: url))
    }

    var records: [[UInt8]] { privateRecords.map(TestData.bytes(hex:)) }

    var modes: [DisplayMode] {
        systemModes.map {
            DisplayMode(
                modeID: $0.modeID, width: $0.width, height: $0.height,
                pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                refreshRate: $0.refreshRate, ioFlags: $0.ioFlags
            )
        }
    }

    /// The capture as a snapshot, with private indexes and bit depth filled in the way
    /// the live service does.
    func display(currentModeID: Int32? = nil) -> Display {
        Display(
            id: 1, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050,
            isBuiltin: true, isMain: true,
            currentModeID: currentModeID ?? self.currentModeID,
            modes: modes.map { mode in
                var mode = mode
                mode.privateIndex = mode.modeID
                mode.bitsPerSample = 10
                return mode
            },
            privateModes: .trusted
        )
    }
}

enum FixtureError: Error {
    case missing
}

enum TestData {
    static func bytes(hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }

    static func mode(
        _ id: Int32, _ width: Int, _ height: Int, scale: Int = 1, hz: Double = 60,
        flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system
    ) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height,
            pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, ioFlags: flags, origin: origin
        )
    }

    /// A 1080p monitor without HiDPI modes (60 and 50 Hz) and two hidden modes.
    static func fullHD(id: CGDirectDisplayID = 2, currentModeID: Int32 = 1) -> Display {
        Display(
            id: id, name: "Full HD Monitor", vendorID: 0x10AC, productID: 0x1234,
            currentModeID: currentModeID,
            modes: [
                mode(1, 1920, 1080, hz: 60, flags: 0x0200_0007),
                mode(2, 1920, 1080, hz: 50, flags: 0x0200_0003),
                mode(3, 1280, 720, hz: 60),
                mode(4, 1024, 768, hz: 60),
                mode(90, 1920, 1080, hz: 75, flags: 0x1, origin: .hidden),
                mode(91, 2560, 1440, hz: 30, flags: 0x1, origin: .hidden),
            ],
            privateModes: .trusted
        )
    }

    /// A 4K monitor: 1920×1080 HiDPI (default) and 2560×1440 HiDPI, plus 1× modes.
    static func uhd(id: CGDirectDisplayID = 3, currentModeID: Int32 = 10) -> Display {
        Display(
            id: id, name: "4K Monitor", vendorID: 0x1E6D, productID: 0x5B09,
            currentModeID: currentModeID,
            modes: [
                mode(10, 1920, 1080, scale: 2, hz: 60, flags: 0x7),
                mode(11, 1920, 1080, scale: 2, hz: 30),
                mode(12, 2560, 1440, scale: 2, hz: 60),
                mode(20, 3840, 2160, hz: 60, flags: 0x0200_0003),
                mode(21, 1920, 1080, hz: 60),
                mode(22, 2560, 1440, hz: 60),
            ],
            privateModes: .trusted
        )
    }
}
```

Create `Tests/ResoluteKitTests/DisplayModeTests.swift`:

<!-- file: Tests/ResoluteKitTests/DisplayModeTests.swift | task: 1 | kind: test -->
```swift
import Testing
@testable import ResoluteKit

@Suite struct DisplayModeTests {
    @Test func hiDPIModeReportsScaleAndFlags() {
        let mode = DisplayMode(
            modeID: 54, width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234,
            refreshRate: 120, ioFlags: 0x0200_0007
        )
        #expect(mode.scale == 2)
        #expect(mode.isHiDPI)
        #expect(mode.isDefault)
        #expect(mode.isNative)
        #expect(mode.sizeText == "1728 × 1117")
        #expect(mode.pixelSizeText == "3456 × 2234")
        #expect(mode.id == 54)
    }

    @Test func lowResolutionModeIsNotHiDPI() {
        let mode = DisplayMode(
            modeID: 126, width: 3456, height: 2234, pixelWidth: 3456, pixelHeight: 2234,
            refreshRate: 120, ioFlags: 0x0200_0003
        )
        #expect(mode.scale == 1)
        #expect(!mode.isHiDPI)
        #expect(!mode.isDefault)
        #expect(mode.isNative)
    }

    @Test(arguments: [
        (120.0, "120 Hz"), (59.94, "59.94 Hz"), (47.95, "47.95 Hz"),
        (59.900001, "59.9 Hz"), (0.0, ""),
    ])
    func formatsRefreshRates(hertz: Double, expected: String) {
        #expect(RefreshRate.format(hertz) == expected)
    }

    @Test func refreshKeysIgnoreFloatingPointNoise() {
        #expect(RefreshRate.key(59.940000244) == RefreshRate.key(59.94))
        #expect(RefreshRate.key(60) != RefreshRate.key(59.94))
    }

    @Test func displayFindsItsCurrentMode() {
        let display = TestData.fullHD(currentModeID: 2)
        #expect(display.currentMode?.refreshRate == 50)
        #expect(display.hiddenModeCount == 2)
        #expect(TestData.fullHD(currentModeID: 999).currentMode == nil)
    }

    @Test func errorsNameCoreGraphicsCodes() {
        let error = ResoluteError.coreGraphics(code: 1001, operation: "apply the display mode")
        #expect(error.errorDescription == "CoreGraphics could not apply the display mode: illegal argument (1001).")
    }

    @Test func capturedFixtureLoads() throws {
        let capture = try CapturedDisplay.load()
        #expect(capture.systemModes.count == 132)
        #expect(capture.records.count == 132)
        #expect(capture.records.allSatisfy { $0.count == 0xD4 })
        #expect(capture.display().currentMode?.sizeText == "1728 × 1117")
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test --filter DisplayModeTests`
Expected: build failure — `cannot find 'DisplayMode' in scope` (the library has no sources yet).

- [ ] **Step 5: Write the implementation**

Create `Sources/ResoluteKit/Version.swift`:

<!-- file: Sources/ResoluteKit/Version.swift | task: 1 | kind: impl -->
```swift
/// The Resolute version shared by the app, the CLI and the build scripts.
public enum ResoluteVersion {
    public static let string = "0.1.0"
}
```

Create `Sources/ResoluteKit/Model/DisplayMode.swift`:

<!-- file: Sources/ResoluteKit/Model/DisplayMode.swift | task: 1 | kind: impl -->
```swift
import Foundation

/// A display mode: its size in points and pixels, refresh rate, and where it was found.
public struct DisplayMode: Hashable, Sendable, Codable, Identifiable {
    /// Where a mode came from.
    public enum Origin: String, Hashable, Sendable, Codable {
        /// Listed by the public CoreGraphics API.
        case system
        /// Listed only by the private SkyLight API; macOS normally hides it.
        case hidden
    }

    /// Bits of `ioFlags` that Resolute reads (see IOGraphicsTypes.h).
    public enum Flag {
        public static let valid: UInt32 = 0x0000_0001
        public static let safe: UInt32 = 0x0000_0002
        public static let defaultMode: UInt32 = 0x0000_0004
        public static let native: UInt32 = 0x0200_0000
    }

    /// The IO display mode ID (`CGDisplayModeGetIODisplayModeID`).
    public var modeID: Int32
    /// Position in the private SkyLight mode list, when known.
    public var privateIndex: Int32?
    /// Width in points.
    public var width: Int
    /// Height in points.
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Refresh rate in hertz, or 0 when the display does not report one.
    public var refreshRate: Double
    /// Bits per colour component (8, 10, …), when known.
    public var bitsPerSample: Int?
    public var ioFlags: UInt32
    public var origin: Origin

    public var id: Int32 { modeID }

    public init(
        modeID: Int32,
        privateIndex: Int32? = nil,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        bitsPerSample: Int? = nil,
        ioFlags: UInt32 = 0,
        origin: Origin = .system
    ) {
        self.modeID = modeID
        self.privateIndex = privateIndex
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
        self.ioFlags = ioFlags
        self.origin = origin
    }

    /// Pixels per point along the horizontal axis (2 for HiDPI modes).
    public var scale: Double {
        width > 0 ? Double(pixelWidth) / Double(width) : 1
    }

    /// True when the mode renders more pixels than points (a Retina/HiDPI mode).
    public var isHiDPI: Bool { pixelWidth > width }

    /// True when macOS marks the mode as the display's default.
    public var isDefault: Bool { ioFlags & Flag.defaultMode != 0 }

    /// True when the mode uses the panel's native pixel size.
    public var isNative: Bool { ioFlags & Flag.native != 0 }

    /// The refresh rate in hundredths of a hertz, for comparisons.
    public var refreshKey: Int { RefreshRate.key(refreshRate) }

    /// "1728 × 1117"
    public var sizeText: String { "\(width) × \(height)" }

    /// "3456 × 2234"
    public var pixelSizeText: String { "\(pixelWidth) × \(pixelHeight)" }
}

/// Comparing and formatting refresh rates.
public enum RefreshRate {
    /// Hundredths of a hertz, so 59.94 and 59.9400024 compare equal.
    public static func key(_ hertz: Double) -> Int {
        Int((hertz * 100).rounded())
    }

    /// "120 Hz", "59.94 Hz", "59.9 Hz"; empty when the rate is unknown.
    public static func format(_ hertz: Double) -> String {
        let key = key(hertz)
        guard key > 0 else { return "" }
        if key % 100 == 0 { return "\(key / 100) Hz" }
        var text = String(format: "%.2f", Double(key) / 100)
        if text.hasSuffix("0") { text.removeLast() }
        return "\(text) Hz"
    }
}
```

Create `Sources/ResoluteKit/Model/Display.swift`:

<!-- file: Sources/ResoluteKit/Model/Display.swift | task: 1 | kind: impl -->
```swift
import CoreGraphics

/// Whether hidden modes from the private SkyLight API can be used for a display.
public enum PrivateModeStatus: Hashable, Sendable, Codable {
    /// The private functions are not available on this system.
    case unavailable
    /// The private records disagree with CoreGraphics, so they are ignored.
    case untrusted(reason: String)
    /// The private records agree with CoreGraphics; hidden modes are listed.
    case trusted
}

/// A snapshot of one online display.
public struct Display: Hashable, Sendable, Codable, Identifiable {
    public var id: CGDirectDisplayID
    public var name: String
    public var vendorID: UInt32
    public var productID: UInt32
    public var serialNumber: UInt32
    public var isBuiltin: Bool
    public var isMain: Bool
    /// The display this one mirrors, when it is a mirror.
    public var mirrorSourceID: CGDirectDisplayID?
    public var isInMirrorSet: Bool
    public var currentModeID: Int32?
    public var modes: [DisplayMode]
    public var privateModes: PrivateModeStatus

    public init(
        id: CGDirectDisplayID,
        name: String,
        vendorID: UInt32 = 0,
        productID: UInt32 = 0,
        serialNumber: UInt32 = 0,
        isBuiltin: Bool = false,
        isMain: Bool = false,
        mirrorSourceID: CGDirectDisplayID? = nil,
        isInMirrorSet: Bool = false,
        currentModeID: Int32?,
        modes: [DisplayMode],
        privateModes: PrivateModeStatus = .unavailable
    ) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.mirrorSourceID = mirrorSourceID
        self.isInMirrorSet = isInMirrorSet
        self.currentModeID = currentModeID
        self.modes = modes
        self.privateModes = privateModes
    }

    /// The mode the display is using, when it is in `modes`.
    public var currentMode: DisplayMode? {
        guard let currentModeID else { return nil }
        return modes.first { $0.modeID == currentModeID }
    }

    /// How many modes only the private API lists.
    public var hiddenModeCount: Int {
        modes.filter { $0.origin == .hidden }.count
    }
}
```

Create `Sources/ResoluteKit/Model/ResoluteError.swift`:

<!-- file: Sources/ResoluteKit/Model/ResoluteError.swift | task: 1 | kind: impl -->
```swift
import Foundation

/// Errors Resolute reports to people.
public enum ResoluteError: Error, Equatable, Sendable {
    case noDisplays
    case displayNotFound(String)
    case ambiguousDisplay(String, matches: [String])
    case modeNotFound(String, suggestions: [String])
    case hiddenModeNeedsConfirmation(String)
    case coreGraphics(code: Int32, operation: String)
    case mirroringNeedsTwoDisplays
    case invalidResolution(String)
    case invalidFlags(String)
    case invalidEntry(String)
    case overrideUnreadable(path: String, reason: String)
    case commandFailed(status: Int32, message: String)
    case cancelled
    case needsRoot
}

extension ResoluteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noDisplays:
            "No online displays were found."
        case .displayNotFound(let selector):
            "No display matches “\(selector)”. Run `resolute displays` to list them."
        case .ambiguousDisplay(let selector, let matches):
            "“\(selector)” matches more than one display: \(matches.joined(separator: ", "))."
        case .modeNotFound(let query, let suggestions):
            suggestions.isEmpty
                ? "No display mode matches \(query)."
                : "No display mode matches \(query). Closest: \(suggestions.joined(separator: ", "))."
        case .hiddenModeNeedsConfirmation(let query):
            "\(query) is a hidden mode that macOS does not list. Pass --allow-hidden to use it."
        case .coreGraphics(let code, let operation):
            "CoreGraphics could not \(operation): \(CGErrorName.name(for: code)) (\(code))."
        case .mirroringNeedsTwoDisplays:
            "Mirroring needs at least two displays."
        case .invalidResolution(let text):
            "“\(text)” is not a resolution. Use WIDTHxHEIGHT, for example 1920x1080."
        case .invalidFlags(let text):
            "“\(text)” is not a flags value. Use two 32-bit hex words, for example 00000009 00a00000."
        case .invalidEntry(let message):
            message
        case .overrideUnreadable(let path, let reason):
            "Could not read \(path): \(reason)"
        case .commandFailed(let status, let message):
            message.isEmpty ? "The command failed with status \(status)." : message
        case .cancelled:
            "The operation was cancelled."
        case .needsRoot:
            "Writing display overrides needs administrator rights. Run the command with sudo, or use the Resolute app."
        }
    }
}

/// Names for CoreGraphics error codes (`CGError`).
public enum CGErrorName {
    public static func name(for code: Int32) -> String {
        switch code {
        case 0: "success"
        case 1000: "failure"
        case 1001: "illegal argument"
        case 1002: "invalid connection"
        case 1003: "invalid context"
        case 1004: "cannot complete"
        case 1006: "not implemented"
        case 1007: "range check"
        case 1008: "type check"
        case 1010: "invalid operation"
        case 1011: "none available"
        default: "error"
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter DisplayModeTests`
Expected: all DisplayModeTests pass.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources Tests Scripts/capture-mode-fixture.swift
git commit -m "Add Resolute package with display mode model and captured macOS 27 fixture"
```

---
### Task 2: Private record decoder, validation, and the live display service

**Files:**
- Create: `Sources/ResoluteKit/System/PrivateModeRecord.swift`, `Sources/ResoluteKit/System/SkyLight.swift`, `Sources/ResoluteKit/System/ConfigurationScope.swift`, `Sources/ResoluteKit/System/MirroringPlan.swift`, `Sources/ResoluteKit/System/DisplayNames.swift`, `Sources/ResoluteKit/System/SystemDisplayService.swift`
- Test: `Tests/ResoluteKitTests/PrivateModeRecordTests.swift`, `Tests/ResoluteKitTests/SystemPlumbingTests.swift`, `Tests/ResoluteKitTests/LiveDisplayTests.swift`

**Interfaces:**
- Consumes: `DisplayMode`, `Display`, `PrivateModeStatus`, `ResoluteError` (Task 1).
- Produces: `PrivateModeRecord(bytes: [UInt8])?` with `index`, `width`, `height`, `pixelWidth`, `pixelHeight`, `refreshRate`, `bitsPerSample`, `ioFlags`, `modeID`, `scale`, `mode(origin:) -> DisplayMode`, `PrivateModeRecord.length == 0xD4`; `PrivateModeValidation` (`.trusted(records:hidden:)`, `.untrusted(reason:)`); `PrivateModeValidator.validate(records: [PrivateModeRecord?], against: [DisplayMode])`; `SkyLight.shared: SkyLight?` with `records(for:)`, `currentModeIndex(for:)`, `configure(_:display:index:)`; `ConfigurationScope` (`.permanent`, `.session`, `.app`); `MirroringPlan.steps(online:main:enable:) -> [MirroringPlan.Step]`; `DisplayNames.disambiguate(_:)`; protocol `DisplayControlling` (`displays()`, `currentModeID(of:)`, `apply(modeID:to:scope:)`, `setMirroring(_:)`); `SystemDisplayService(skyLight:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ResoluteKitTests/PrivateModeRecordTests.swift`:

<!-- file: Tests/ResoluteKitTests/PrivateModeRecordTests.swift | task: 2 | kind: test -->
```swift
import Testing
@testable import ResoluteKit

@Suite struct PrivateModeRecordTests {
    let capture: CapturedDisplay

    init() throws {
        capture = try CapturedDisplay.load()
    }

    @Test func decodesEveryCapturedRecordLikeCoreGraphics() throws {
        let modesByID = Dictionary(uniqueKeysWithValues: capture.modes.map { ($0.modeID, $0) })
        for (position, bytes) in capture.records.enumerated() {
            let record = try #require(PrivateModeRecord(bytes: bytes))
            let mode = try #require(modesByID[record.modeID])
            #expect(record.index == Int32(position))
            #expect(record.width == mode.width)
            #expect(record.height == mode.height)
            #expect(record.pixelWidth == mode.pixelWidth)
            #expect(record.pixelHeight == mode.pixelHeight)
            #expect(record.refreshRate == mode.refreshRate)
            #expect(record.ioFlags == mode.ioFlags)
            #expect(record.scale == mode.scale)
        }
    }

    @Test func decodesTheCurrentModeRecord() throws {
        let record = try #require(PrivateModeRecord(bytes: capture.records[54]))
        #expect(record.index == 54)
        #expect(record.modeID == 54)
        #expect(record.width == 1728)
        #expect(record.height == 1117)
        #expect(record.pixelWidth == 3456)
        #expect(record.pixelHeight == 2234)
        #expect(record.refreshRate == 120)
        #expect(record.bitsPerSample == 10)
        #expect(record.ioFlags == 0x0200_0007)
        #expect(record.scale == 2)
        #expect(record.mode(origin: .hidden).privateIndex == 54)
    }

    @Test func decodesFractionalRefreshRates() throws {
        #expect(try #require(PrivateModeRecord(bytes: capture.records[2])).refreshRate == 59.94)
        #expect(try #require(PrivateModeRecord(bytes: capture.records[5])).refreshRate == 47.95)
    }

    @Test func rejectsRecordsWithoutTheLayoutMarker() {
        var bytes = capture.records[0]
        bytes[0xB8] = 0
        #expect(PrivateModeRecord(bytes: bytes) == nil)
    }

    @Test func rejectsShortRecords() {
        #expect(PrivateModeRecord(bytes: Array(capture.records[0].prefix(0x80))) == nil)
    }

    @Test func rejectsRecordsWithoutAScale() {
        var bytes = capture.records[0]
        for offset in 0xD0..<0xD4 { bytes[offset] = 0 }
        #expect(PrivateModeRecord(bytes: bytes) == nil)
    }
}

@Suite struct PrivateModeValidatorTests {
    let capture: CapturedDisplay
    let records: [PrivateModeRecord?]

    init() throws {
        capture = try CapturedDisplay.load()
        records = capture.records.map(PrivateModeRecord.init(bytes:))
    }

    @Test func trustsRecordsThatMatchCoreGraphics() {
        guard case .trusted(let all, let hidden) = PrivateModeValidator.validate(records: records, against: capture.modes) else {
            Issue.record("expected the captured records to be trusted")
            return
        }
        #expect(all.count == 132)
        #expect(hidden.isEmpty)
    }

    @Test func reportsRecordsMissingFromCoreGraphicsAsHidden() {
        let visible = capture.modes.filter { $0.modeID < 126 }
        guard case .trusted(_, let hidden) = PrivateModeValidator.validate(records: records, against: visible) else {
            Issue.record("expected the captured records to be trusted")
            return
        }
        #expect(hidden.map(\.modeID) == Array(Int32(126)...131))
    }

    @Test func distrustsRecordsThatDisagree() {
        var modes = capture.modes
        modes[55].refreshRate = 75
        guard case .untrusted(let reason) = PrivateModeValidator.validate(records: records, against: modes) else {
            Issue.record("expected a disagreement to be reported")
            return
        }
        #expect(reason.contains("1 of 132"))
    }

    @Test func distrustsUnreadableRecords() {
        var damaged = records
        damaged[3] = nil
        #expect(PrivateModeValidator.validate(records: damaged, against: capture.modes)
            == .untrusted(reason: "record 3 has an unrecognised layout"))
    }

    @Test func distrustsRecordsOutOfOrder() {
        var shuffled = records
        shuffled.swapAt(0, 1)
        #expect(PrivateModeValidator.validate(records: shuffled, against: capture.modes)
            == .untrusted(reason: "record 0 reports index 1"))
    }

    @Test func distrustsEmptyOrUnmatchedLists() {
        #expect(PrivateModeValidator.validate(records: [], against: capture.modes)
            == .untrusted(reason: "SkyLight reported no modes"))
        #expect(PrivateModeValidator.validate(records: records, against: [])
            == .untrusted(reason: "no SkyLight record matches a CoreGraphics mode"))
    }
}
```

Create `Tests/ResoluteKitTests/SystemPlumbingTests.swift`:

<!-- file: Tests/ResoluteKitTests/SystemPlumbingTests.swift | task: 2 | kind: test -->
```swift
import CoreGraphics
import Testing
@testable import ResoluteKit

@Suite struct MirroringPlanTests {
    @Test func mirrorsEveryOtherDisplayToTheMainDisplay() {
        let steps = MirroringPlan.steps(online: [1, 5, 9], main: 5, enable: true)
        #expect(steps == [.init(display: 1, source: 5), .init(display: 9, source: 5)])
    }

    @Test func stopsMirroringWithTheNullDisplay() {
        let steps = MirroringPlan.steps(online: [1, 5], main: 1, enable: false)
        #expect(steps == [.init(display: 5, source: kCGNullDirectDisplay)])
    }
}

@Suite struct DisplayNamesTests {
    @Test func disambiguatesIdenticalNames() {
        #expect(DisplayNames.disambiguate(["DELL U2720Q", "Built-in Retina Display", "DELL U2720Q"])
            == ["DELL U2720Q (1)", "Built-in Retina Display", "DELL U2720Q (2)"])
    }

    @Test func leavesDistinctNamesAlone() {
        #expect(DisplayNames.disambiguate(["A", "B"]) == ["A", "B"])
    }
}

@Suite struct ConfigurationScopeTests {
    @Test func mapsToCoreGraphicsOptions() {
        #expect(ConfigurationScope.permanent.option == .permanently)
        #expect(ConfigurationScope.session.option == .forSession)
        #expect(ConfigurationScope.app.option == .forAppOnly)
    }
}
```

Create `Tests/ResoluteKitTests/LiveDisplayTests.swift` (runs only with `RESOLUTE_LIVE_TESTS=1`; it changes the refresh rate for this process only and restores it):

<!-- file: Tests/ResoluteKitTests/LiveDisplayTests.swift | task: 2 | kind: test -->
```swift
import Foundation
import Testing
@testable import ResoluteKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["RESOLUTE_LIVE_TESTS"] == "1"), .serialized)
struct LiveDisplayTests {
    let service = SystemDisplayService()

    @Test func listsTheMainDisplay() throws {
        let main = try #require(service.displays().first { $0.isMain })
        #expect(!main.name.isEmpty)
        #expect(!main.modes.isEmpty)
        #expect(main.currentMode != nil)
        #expect(service.currentModeID(of: main.id) == main.currentModeID)
    }

    @Test func trustsTheSkyLightRecordsOnThisMac() throws {
        let main = try #require(service.displays().first { $0.isMain })
        #expect(main.privateModes == .trusted)
        #expect(main.modes.filter { $0.origin == .system }.allSatisfy { $0.privateIndex != nil })
    }

    @Test func switchesTheRefreshRateThroughCoreGraphicsAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        try service.apply(modeID: sibling.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(modeID: current.modeID, to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    @Test func switchesTheRefreshRateThroughSkyLightAndBack() throws {
        let (main, current, sibling) = try refreshSibling()
        try service.apply(privateIndex: try #require(sibling.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == sibling.modeID)
        try service.apply(privateIndex: try #require(current.privateIndex), to: main.id, scope: .app)
        #expect(service.currentModeID(of: main.id) == current.modeID)
    }

    /// The main display, its current mode, and a mode with the same size at another refresh rate.
    private func refreshSibling() throws -> (Display, DisplayMode, DisplayMode) {
        let main = try #require(service.displays().first { $0.isMain })
        let current = try #require(main.currentMode)
        let sibling = try #require(main.modes.first {
            $0.origin == .system && $0.width == current.width && $0.height == current.height
                && $0.pixelWidth == current.pixelWidth && $0.refreshKey != current.refreshKey
        })
        return (main, current, sibling)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PrivateMode|MirroringPlan|DisplayNames|ConfigurationScope"`
Expected: build failure — `cannot find 'PrivateModeRecord' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ResoluteKit/System/PrivateModeRecord.swift`:

<!-- file: Sources/ResoluteKit/System/PrivateModeRecord.swift | task: 2 | kind: impl -->
```swift
import Foundation

/// One record from `CGSGetDisplayModeDescriptionOfLength`, decoded with the layout
/// macOS uses today (verified on macOS 27; offsets are listed in docs/design).
public struct PrivateModeRecord: Hashable, Sendable {
    /// The record size Resolute asks for and understands.
    public static let length = 0xD4

    /// Position in the private mode list; the argument `CGSConfigureDisplayMode` takes.
    public var index: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var bitsPerSample: Int
    public var ioFlags: UInt32
    public var modeID: Int32
    public var scale: Double

    /// Decodes a record, or returns nil when the bytes do not have the expected layout.
    public init?(bytes: [UInt8]) {
        guard bytes.count >= Self.length else { return nil }
        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }
        // The record carries its own size; anything else is a layout we do not know.
        guard word(0xB8) == UInt32(Self.length) else { return nil }
        let scale = Double(Float(bitPattern: word(0xD0)))
        let width = Int(word(0x08))
        let height = Int(word(0x0C))
        let pixelWidth = Int(word(0xC8))
        let pixelHeight = Int(word(0xCC))
        guard scale.isFinite, scale > 0, width > 0, height > 0, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        self.index = Int32(bitPattern: word(0x00))
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        // 16.16 fixed point, rounded to the millihertz CoreGraphics reports.
        self.refreshRate = (Double(word(0xBC)) / 65_536 * 1_000).rounded() / 1_000
        self.bitsPerSample = Int(word(0x1C))
        self.ioFlags = word(0xC0)
        self.modeID = Int32(bitPattern: word(0xC4))
        self.scale = scale
    }

    /// The record as a `DisplayMode`.
    public func mode(origin: DisplayMode.Origin) -> DisplayMode {
        DisplayMode(
            modeID: modeID,
            privateIndex: index,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            bitsPerSample: bitsPerSample > 0 ? bitsPerSample : nil,
            ioFlags: ioFlags,
            origin: origin
        )
    }
}

/// The result of checking private records against CoreGraphics.
public enum PrivateModeValidation: Equatable, Sendable {
    /// Every record CoreGraphics also lists agrees with it; `hidden` are the extras.
    case trusted(records: [PrivateModeRecord], hidden: [PrivateModeRecord])
    /// The records cannot be relied on.
    case untrusted(reason: String)
}

/// Decides whether the private mode list can be used.
public enum PrivateModeValidator {
    /// Compares decoded private records (in list order) with the public modes.
    public static func validate(
        records: [PrivateModeRecord?],
        against systemModes: [DisplayMode]
    ) -> PrivateModeValidation {
        guard !records.isEmpty else { return .untrusted(reason: "SkyLight reported no modes") }
        var decoded: [PrivateModeRecord] = []
        for (position, record) in records.enumerated() {
            guard let record else {
                return .untrusted(reason: "record \(position) has an unrecognised layout")
            }
            guard record.index == Int32(position) else {
                return .untrusted(reason: "record \(position) reports index \(record.index)")
            }
            decoded.append(record)
        }
        let systemByID = Dictionary(systemModes.map { ($0.modeID, $0) }, uniquingKeysWith: { first, _ in first })
        var matched = 0
        var mismatched = 0
        var hidden: [PrivateModeRecord] = []
        for record in decoded {
            guard let mode = systemByID[record.modeID] else {
                hidden.append(record)
                continue
            }
            matched += 1
            if !agrees(record, mode) { mismatched += 1 }
        }
        guard matched > 0 else {
            return .untrusted(reason: "no SkyLight record matches a CoreGraphics mode")
        }
        guard mismatched == 0 else {
            return .untrusted(reason: "\(mismatched) of \(matched) SkyLight records disagree with CoreGraphics")
        }
        return .trusted(records: decoded, hidden: hidden)
    }

    static func agrees(_ record: PrivateModeRecord, _ mode: DisplayMode) -> Bool {
        record.width == mode.width
            && record.height == mode.height
            && record.pixelWidth == mode.pixelWidth
            && record.pixelHeight == mode.pixelHeight
            && abs(record.refreshRate - mode.refreshRate) < 0.01
            && abs(record.scale - mode.scale) < 0.01
    }
}
```

Create `Sources/ResoluteKit/System/SkyLight.swift`:

<!-- file: Sources/ResoluteKit/System/SkyLight.swift | task: 2 | kind: impl -->
```swift
import CoreGraphics
import Darwin

/// The private SkyLight display-mode functions, resolved at run time.
///
/// Every function is looked up with `dlsym`. If one is missing the bridge is not created
/// and Resolute uses the public CoreGraphics API alone.
public final class SkyLight: @unchecked Sendable {
    // Immutable after init, so sharing across threads is safe.
    private typealias ModeCountFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias ModeDescriptionFunction = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void
    private typealias CurrentModeFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias ConfigureModeFunction = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> Void

    private let modeCount: ModeCountFunction
    private let modeDescription: ModeDescriptionFunction
    private let currentMode: CurrentModeFunction
    private let configureMode: ConfigureModeFunction

    /// The bridge for this process, or nil when the private functions are unavailable.
    public static let shared: SkyLight? = SkyLight()

    private init?() {
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        func load<Function>(_ name: String, as type: Function.Type) -> Function? {
            guard let symbol = dlsym(everyImage, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard
            let modeCount = load("CGSGetNumberOfDisplayModes", as: ModeCountFunction.self),
            let modeDescription = load("CGSGetDisplayModeDescriptionOfLength", as: ModeDescriptionFunction.self),
            let currentMode = load("CGSGetCurrentDisplayMode", as: CurrentModeFunction.self),
            let configureMode = load("CGSConfigureDisplayMode", as: ConfigureModeFunction.self)
        else { return nil }
        self.modeCount = modeCount
        self.modeDescription = modeDescription
        self.currentMode = currentMode
        self.configureMode = configureMode
    }

    /// Raw records for every mode of `display`, in list order.
    public func rawRecords(for display: CGDirectDisplayID) -> [[UInt8]] {
        var count: Int32 = 0
        modeCount(display, &count)
        guard count > 0, count < 10_000 else { return [] }
        return (0..<count).map { index in
            // Zeroed and larger than requested, in case the system writes past the length.
            var buffer = [UInt8](repeating: 0, count: 0x100)
            buffer.withUnsafeMutableBytes { bytes in
                modeDescription(display, index, bytes.baseAddress!, Int32(PrivateModeRecord.length))
            }
            return Array(buffer.prefix(PrivateModeRecord.length))
        }
    }

    /// Decoded records for every mode of `display`; nil where a record is unreadable.
    public func records(for display: CGDirectDisplayID) -> [PrivateModeRecord?] {
        rawRecords(for: display).map(PrivateModeRecord.init(bytes:))
    }

    /// Index of the current mode in the private list.
    public func currentModeIndex(for display: CGDirectDisplayID) -> Int32? {
        var index: Int32 = -1
        currentMode(display, &index)
        return index >= 0 ? index : nil
    }

    /// Adds "switch `display` to private mode `index`" to a configuration transaction.
    public func configure(_ config: CGDisplayConfigRef, display: CGDirectDisplayID, index: Int32) {
        configureMode(config, display, index)
    }
}
```

Create `Sources/ResoluteKit/System/ConfigurationScope.swift`:

<!-- file: Sources/ResoluteKit/System/ConfigurationScope.swift | task: 2 | kind: impl -->
```swift
import CoreGraphics

/// How long a display configuration change lasts.
public enum ConfigurationScope: String, Sendable, CaseIterable, Codable {
    /// Saved in the display preferences, like a change made in System Settings.
    case permanent
    /// Until the user logs out.
    case session
    /// Until this process exits.
    case app

    var option: CGConfigureOption {
        switch self {
        case .permanent: .permanently
        case .session: .forSession
        case .app: .forAppOnly
        }
    }
}
```

Create `Sources/ResoluteKit/System/MirroringPlan.swift`:

<!-- file: Sources/ResoluteKit/System/MirroringPlan.swift | task: 2 | kind: impl -->
```swift
import CoreGraphics

/// The `CGConfigureDisplayMirrorOfDisplay` calls that turn mirroring on or off.
public enum MirroringPlan {
    public struct Step: Equatable, Sendable {
        public var display: CGDirectDisplayID
        /// The display to mirror, or `kCGNullDirectDisplay` to stop mirroring.
        public var source: CGDirectDisplayID
    }

    public static func steps(online: [CGDirectDisplayID], main: CGDirectDisplayID, enable: Bool) -> [Step] {
        online
            .filter { $0 != main }
            .map { Step(display: $0, source: enable ? main : kCGNullDirectDisplay) }
    }
}
```

Create `Sources/ResoluteKit/System/DisplayNames.swift`:

<!-- file: Sources/ResoluteKit/System/DisplayNames.swift | task: 2 | kind: impl -->
```swift
import AppKit
import CoreGraphics

/// Human-readable display names.
enum DisplayNames {
    /// Names from `NSScreen`, keyed by display ID (active displays only).
    static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    /// The product name CoreDisplay reports; covers mirrored and inactive displays.
    static func coreDisplayName(for display: CGDirectDisplayID) -> String? {
        typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
        guard let framework = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let symbol = dlsym(framework, "CoreDisplay_DisplayCreateInfoDictionary")
        else { return nil }
        let copyInfo = unsafeBitCast(symbol, to: InfoFunction.self)
        guard let info = copyInfo(display)?.takeRetainedValue() as? [String: Any],
              let names = info["DisplayProductName"] as? [String: String],
              !names.isEmpty
        else { return nil }
        let preferred = Bundle.preferredLocalizations(
            from: Array(names.keys), forPreferences: Locale.preferredLanguages
        ).first
        return preferred.flatMap { names[$0] } ?? names["en_US"] ?? names.values.sorted().first
    }

    static func fallbackName(for display: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(display) != 0 ? "Built-in Display" : "Display \(display)"
    }

    /// Appends " (1)", " (2)", … to names that occur more than once.
    static func disambiguate(_ names: [String]) -> [String] {
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        return names.map { name in
            guard counts[name, default: 0] > 1 else { return name }
            seen[name, default: 0] += 1
            return "\(name) (\(seen[name, default: 1]))"
        }
    }
}
```

Create `Sources/ResoluteKit/System/SystemDisplayService.swift`:

<!-- file: Sources/ResoluteKit/System/SystemDisplayService.swift | task: 2 | kind: impl -->
```swift
import CoreGraphics
import Foundation

/// Reads and changes the display configuration.
public protocol DisplayControlling: Sendable {
    /// A fresh snapshot of every online display.
    func displays() -> [Display]
    /// The IO mode ID `displayID` is using right now.
    func currentModeID(of displayID: CGDirectDisplayID) -> Int32?
    /// Switches `displayID` to the mode with `modeID`.
    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws
    /// Mirrors every display to the main display, or stops mirroring.
    func setMirroring(_ enabled: Bool) throws
}

/// `DisplayControlling` backed by CoreGraphics and, when its records check out, SkyLight.
public struct SystemDisplayService: DisplayControlling {
    private let skyLight: SkyLight?

    public init(skyLight: SkyLight? = SkyLight.shared) {
        self.skyLight = skyLight
    }

    public func displays() -> [Display] {
        let ids = Self.onlineDisplayIDs()
        let screenNames = DisplayNames.screenNames()
        let names = DisplayNames.disambiguate(ids.map {
            screenNames[$0] ?? DisplayNames.coreDisplayName(for: $0) ?? DisplayNames.fallbackName(for: $0)
        })
        return zip(ids, names).map { makeDisplay(id: $0, name: $1) }
    }

    public func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID
    }

    public func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        if let mode = Self.systemModes(for: displayID).first(where: { $0.ioDisplayModeID == modeID }) {
            try configure(scope: scope) { config in
                try check(CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil), "select the display mode")
            }
        } else if let index = hiddenModeIndex(modeID, display: displayID) {
            try apply(privateIndex: index, to: displayID, scope: scope)
        } else {
            throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: [])
        }
    }

    public func setMirroring(_ enabled: Bool) throws {
        let online = Self.onlineDisplayIDs()
        guard online.count > 1 else { throw ResoluteError.mirroringNeedsTwoDisplays }
        let operation = enabled ? "mirror the displays" : "stop mirroring"
        try configure(scope: .permanent) { config in
            for step in MirroringPlan.steps(online: online, main: CGMainDisplayID(), enable: enabled) {
                try check(CGConfigureDisplayMirrorOfDisplay(config, step.display, step.source), operation)
            }
        }
    }

    /// Switches through SkyLight to the mode at `privateIndex` in the private list.
    func apply(privateIndex: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard let skyLight else { throw ResoluteError.modeNotFound("private mode \(privateIndex)", suggestions: []) }
        try configure(scope: scope) { config in
            skyLight.configure(config, display: displayID, index: privateIndex)
        }
    }

    // MARK: - Snapshot

    private func makeDisplay(id: CGDirectDisplayID, name: String) -> Display {
        var modes = Self.systemModes(for: id).map(DisplayMode.init(systemMode:))
        var currentID = currentModeID(of: id)
        var status = PrivateModeStatus.unavailable

        if let skyLight {
            switch PrivateModeValidator.validate(records: skyLight.records(for: id), against: modes) {
            case .trusted(let records, let hidden):
                status = .trusted
                let recordsByID = Dictionary(records.map { ($0.modeID, $0) }, uniquingKeysWith: { first, _ in first })
                for index in modes.indices {
                    guard let record = recordsByID[modes[index].modeID] else { continue }
                    modes[index].privateIndex = record.index
                    modes[index].bitsPerSample = record.bitsPerSample > 0 ? record.bitsPerSample : nil
                }
                var knownIDs = Set(modes.map(\.modeID))
                for record in hidden where knownIDs.insert(record.modeID).inserted {
                    modes.append(record.mode(origin: .hidden))
                }
                let currentIsListed = currentID.map { listed in modes.contains { $0.modeID == listed } } ?? false
                if !currentIsListed, let index = skyLight.currentModeIndex(for: id) {
                    currentID = modes.first { $0.privateIndex == index }?.modeID ?? currentID
                }
            case .untrusted(let reason):
                status = .untrusted(reason: reason)
            }
        }

        let mirrorSource = CGDisplayMirrorsDisplay(id)
        return Display(
            id: id,
            name: name,
            vendorID: CGDisplayVendorNumber(id),
            productID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            mirrorSourceID: mirrorSource == kCGNullDirectDisplay ? nil : mirrorSource,
            isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
            currentModeID: currentID,
            modes: modes,
            privateModes: status
        )
    }

    private func hiddenModeIndex(_ modeID: Int32, display: CGDirectDisplayID) -> Int32? {
        guard let skyLight else { return nil }
        let systemModes = Self.systemModes(for: display).map(DisplayMode.init(systemMode:))
        guard case .trusted(_, let hidden) = PrivateModeValidator.validate(
            records: skyLight.records(for: display), against: systemModes
        ) else { return nil }
        return hidden.first { $0.modeID == modeID }?.index
    }

    // MARK: - CoreGraphics helpers

    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func systemModes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// Runs `body` inside a configuration transaction and commits it with `scope`.
    private func configure(scope: ConfigurationScope, _ body: (CGDisplayConfigRef) throws -> Void) throws {
        var configRef: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configRef), "start a display configuration")
        guard let config = configRef else {
            throw ResoluteError.coreGraphics(code: CGError.failure.rawValue, operation: "start a display configuration")
        }
        do {
            try body(config)
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, scope.option), "apply the display configuration")
    }

    private func check(_ error: CGError, _ operation: String) throws {
        guard error == .success else {
            throw ResoluteError.coreGraphics(code: error.rawValue, operation: operation)
        }
    }
}

extension DisplayMode {
    init(systemMode mode: CGDisplayMode) {
        self.init(
            modeID: mode.ioDisplayModeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: (mode.refreshRate * 1_000).rounded() / 1_000,
            ioFlags: mode.ioFlags,
            origin: .system
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "PrivateMode|MirroringPlan|DisplayNames|ConfigurationScope"`
Expected: all pass.

Run: `RESOLUTE_LIVE_TESTS=1 swift test --filter LiveDisplayTests`
Expected: 4 tests pass; afterwards `swift Scripts/capture-mode-fixture.swift | grep currentModeID` still prints the original mode (54 on the development Mac).

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/System Tests/ResoluteKitTests
git commit -m "Decode SkyLight mode records, validate them against CoreGraphics, and add the display service"
```

---
### Task 3: Mode catalog — grouping, sections, preferred modes

**Files:**
- Create: `Sources/ResoluteKit/Model/ModeCatalog.swift`
- Test: `Tests/ResoluteKitTests/ModeCatalogTests.swift`

**Interfaces:**
- Consumes: `DisplayMode`, `Display`, `RefreshRate` (Task 1).
- Produces: `ResolutionGroup` (`key: ResolutionGroup.Key`, `modes`, `isHiDPI`, `isHidden`, `isDefault`, `isNative`, `sizeText`, `pixelSizeText`, `refreshRates`), `ResolutionGroup.Key(_ mode:)`, `ResolutionGroup.Key.largerFirst(_:_:)`; `ResolutionSection` (`kind: .hiDPI | .lowResolution | .standard | .hidden`, `kind.title`, `groups`); `RefreshOption` (`mode`, `isCurrent`, `refreshRate`); `ModeCatalog.groups(_:)`, `.currentKey(for:)`, `.sections(for:includeLowResolution:includeHidden:)`, `.preferredMode(in:current:)`, `.refreshOptions(for:includeHidden:)`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/ResoluteKitTests/ModeCatalogTests.swift | task: 3 | kind: test -->
```swift
import Testing
@testable import ResoluteKit

@Suite struct ModeCatalogTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    @Test func groupsTheCapturedModesByResolution() {
        let groups = ModeCatalog.groups(display.modes)
        #expect(groups.count == 22)
        #expect(groups.allSatisfy { $0.modes.count == 6 })
        #expect(groups.first?.sizeText == "3456 × 2234")
        #expect(groups.last?.sizeText == "960 × 600")
    }

    @Test func splitsHiDPIAndLowResolutionSections() {
        let sections = ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: false)
        #expect(sections.map(\.kind) == [.hiDPI, .lowResolution])
        #expect(sections[0].groups.map(\.sizeText) == [
            "2056 × 1329", "2056 × 1285", "1728 × 1117", "1728 × 1080", "1496 × 967", "1496 × 935",
            "1312 × 848", "1312 × 820", "1280 × 800", "1168 × 755", "1168 × 730", "960 × 600",
        ])
        #expect(sections[1].groups.map(\.sizeText) == [
            "3456 × 2234", "3456 × 2160", "2992 × 1934", "2992 × 1870", "2624 × 1696",
            "2624 × 1640", "2560 × 1600", "2336 × 1510", "2336 × 1460", "1920 × 1200",
        ])
        #expect(ResolutionSection.Kind.lowResolution.title == "Low Resolution (1×)")
    }

    @Test func hidesLowResolutionModesUnlessOneIsCurrent() {
        #expect(ModeCatalog.sections(for: display, includeLowResolution: false, includeHidden: false).map(\.kind) == [.hiDPI])
        let atNative = capture.display(currentModeID: 126)
        let sections = ModeCatalog.sections(for: atNative, includeLowResolution: false, includeHidden: false)
        #expect(sections.map(\.kind) == [.hiDPI, .lowResolution])
        #expect(sections[1].groups.map(\.sizeText) == ["3456 × 2234"])
    }

    @Test func marksDefaultAndNativeGroups() throws {
        let groups = ModeCatalog.groups(display.modes)
        let hiDPIDefault = try #require(groups.first { $0.sizeText == "1728 × 1117" && $0.isHiDPI })
        #expect(hiDPIDefault.isDefault)
        #expect(hiDPIDefault.isNative)
        let native = try #require(groups.first { $0.sizeText == "3456 × 2234" })
        #expect(native.isNative)
        #expect(!native.isDefault)
        #expect(groups.first { $0.sizeText == "1496 × 967" }?.isNative == false)
        #expect(native.refreshRates == [120, 60, 59.94, 50, 48, 47.95])
    }

    @Test func keepsTheCurrentRefreshRateWhenSwitchingResolution() throws {
        let group = try #require(ModeCatalog.groups(display.modes).first { $0.sizeText == "1496 × 967" })
        #expect(ModeCatalog.preferredMode(in: group, current: display.currentMode).modeID == 42)
        let at60 = capture.display(currentModeID: 55)
        #expect(ModeCatalog.preferredMode(in: group, current: at60.currentMode).modeID == 43)
    }

    @Test func picksTheCurrentModeForItsOwnGroup() throws {
        let group = try #require(ModeCatalog.groups(display.modes).first { $0.sizeText == "1728 × 1117" })
        #expect(ModeCatalog.preferredMode(in: group, current: display.currentMode).modeID == 54)
    }

    @Test func fallsBackToTheFastestSystemMode() throws {
        let fullHD = TestData.fullHD()
        let group = try #require(ModeCatalog.groups(fullHD.modes).first { $0.sizeText == "1920 × 1080" })
        let elsewhereAt75 = TestData.mode(99, 800, 600, hz: 75)
        // The hidden 75 Hz mode matches the refresh rate, but system modes come first.
        #expect(ModeCatalog.preferredMode(in: group, current: elsewhereAt75).modeID == 1)
        #expect(ModeCatalog.preferredMode(in: group, current: nil).modeID == 1)
    }

    @Test func listsRefreshRatesForTheCurrentResolution() {
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: false)
        #expect(options.map { RefreshRate.format($0.refreshRate) } == ["120 Hz", "60 Hz", "59.94 Hz", "50 Hz", "48 Hz", "47.95 Hz"])
        #expect(options.filter(\.isCurrent).map(\.mode.modeID) == [54])
    }

    @Test func includesHiddenRefreshRatesOnlyWhenAsked() {
        let fullHD = TestData.fullHD()
        #expect(ModeCatalog.refreshOptions(for: fullHD, includeHidden: false).map(\.refreshRate) == [60, 50])
        #expect(ModeCatalog.refreshOptions(for: fullHD, includeHidden: true).map(\.refreshRate) == [75, 60, 50])
    }

    @Test func usesOneStandardSectionForDisplaysWithoutHiDPI() {
        let sections = ModeCatalog.sections(for: TestData.fullHD(), includeLowResolution: false, includeHidden: false)
        #expect(sections.map(\.kind) == [.standard])
        #expect(sections[0].groups.map(\.sizeText) == ["1920 × 1080", "1280 × 720", "1024 × 768"])
    }

    @Test func putsHiddenOnlyResolutionsInTheirOwnSection() {
        let sections = ModeCatalog.sections(for: TestData.fullHD(), includeLowResolution: true, includeHidden: true)
        #expect(sections.map(\.kind) == [.standard, .hidden])
        #expect(sections[1].groups.map(\.sizeText) == ["2560 × 1440"])
        #expect(sections[0].groups[0].modes.map(\.modeID) == [1, 2, 90])
    }

    @Test func returnsNoRefreshOptionsWithoutACurrentMode() {
        #expect(ModeCatalog.refreshOptions(for: capture.display(currentModeID: 9_999), includeHidden: false).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ModeCatalogTests`
Expected: build failure — `cannot find 'ModeCatalog' in scope`.

- [ ] **Step 3: Write the implementation**

<!-- file: Sources/ResoluteKit/Model/ModeCatalog.swift | task: 3 | kind: impl -->
```swift
import Foundation

/// All modes that share a size in points and in pixels: one entry in the resolution menu.
public struct ResolutionGroup: Hashable, Sendable, Identifiable {
    public struct Key: Hashable, Sendable {
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int

        public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) {
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        public init(_ mode: DisplayMode) {
            self.init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight)
        }

        /// Orders larger resolutions first.
        public static func largerFirst(_ lhs: Key, _ rhs: Key) -> Bool {
            (lhs.width, lhs.height, lhs.pixelWidth, lhs.pixelHeight)
                > (rhs.width, rhs.height, rhs.pixelWidth, rhs.pixelHeight)
        }
    }

    public var key: Key
    /// System modes first, then the fastest refresh rate first.
    public var modes: [DisplayMode]

    public var id: Key { key }
    public var isHiDPI: Bool { key.pixelWidth > key.width }
    public var isHidden: Bool { modes.allSatisfy { $0.origin == .hidden } }
    public var isDefault: Bool { modes.contains(where: \.isDefault) }
    public var isNative: Bool { modes.contains(where: \.isNative) }
    public var sizeText: String { "\(key.width) × \(key.height)" }
    public var pixelSizeText: String { "\(key.pixelWidth) × \(key.pixelHeight)" }

    /// Distinct refresh rates, highest first.
    public var refreshRates: [Double] {
        var seen = Set<Int>()
        return modes.map(\.refreshRate).sorted(by: >).filter { seen.insert(RefreshRate.key($0)).inserted }
    }
}

/// A titled run of resolutions in the menu.
public struct ResolutionSection: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case hiDPI
        case lowResolution
        case standard
        case hidden

        public var title: String {
            switch self {
            case .hiDPI: "HiDPI"
            case .lowResolution: "Low Resolution (1×)"
            case .standard: "Resolutions"
            case .hidden: "Hidden"
            }
        }
    }

    public var kind: Kind
    public var groups: [ResolutionGroup]
}

/// A refresh rate offered for the current resolution.
public struct RefreshOption: Hashable, Sendable {
    public var mode: DisplayMode
    public var isCurrent: Bool
    public var refreshRate: Double { mode.refreshRate }
}

/// Turns a display's flat mode list into what the menu and the CLI show.
public enum ModeCatalog {
    public static func groups(_ modes: [DisplayMode]) -> [ResolutionGroup] {
        Dictionary(grouping: modes, by: ResolutionGroup.Key.init)
            .map { key, modes in ResolutionGroup(key: key, modes: modes.sorted(by: systemThenFastest)) }
            .sorted { ResolutionGroup.Key.largerFirst($0.key, $1.key) }
    }

    public static func currentKey(for display: Display) -> ResolutionGroup.Key? {
        display.currentMode.map(ResolutionGroup.Key.init)
    }

    /// Resolution sections: HiDPI and low-resolution modes on displays that have HiDPI
    /// modes, one standard section otherwise, and hidden-only resolutions last.
    public static func sections(
        for display: Display,
        includeLowResolution: Bool,
        includeHidden: Bool
    ) -> [ResolutionSection] {
        let currentKey = currentKey(for: display)
        let modes = display.modes.filter {
            includeHidden || $0.origin == .system || $0.modeID == display.currentModeID
        }
        let all = groups(modes)
        let visible = all.filter { !$0.isHidden }
        let hiDPI = visible.filter(\.isHiDPI)
        let oneX = visible.filter { !$0.isHiDPI }

        var sections: [ResolutionSection] = []
        if hiDPI.isEmpty {
            if !oneX.isEmpty { sections.append(ResolutionSection(kind: .standard, groups: oneX)) }
        } else {
            sections.append(ResolutionSection(kind: .hiDPI, groups: hiDPI))
            // Keep the current resolution visible even when low-resolution modes are off.
            let lowResolution = includeLowResolution ? oneX : oneX.filter { $0.key == currentKey }
            if !lowResolution.isEmpty {
                sections.append(ResolutionSection(kind: .lowResolution, groups: lowResolution))
            }
        }
        let hidden = all.filter(\.isHidden)
        if !hidden.isEmpty { sections.append(ResolutionSection(kind: .hidden, groups: hidden)) }
        return sections
    }

    /// The mode to switch to when someone picks `group`: the current mode if it is in the
    /// group; else the current refresh rate if offered, otherwise the fastest — preferring
    /// system modes and the current bit depth.
    public static func preferredMode(in group: ResolutionGroup, current: DisplayMode?) -> DisplayMode {
        if let current, group.modes.contains(current) { return current }
        var candidates = group.modes
        if candidates.contains(where: { $0.origin == .system }) {
            candidates = candidates.filter { $0.origin == .system }
        }
        if let depth = current?.bitsPerSample, candidates.contains(where: { $0.bitsPerSample == depth }) {
            candidates = candidates.filter { $0.bitsPerSample == depth }
        }
        if let current, let sameRate = candidates.first(where: { $0.refreshKey == current.refreshKey }) {
            return sameRate
        }
        return candidates.first ?? group.modes[0]
    }

    /// Refresh rates for the display's current resolution, highest first.
    public static func refreshOptions(for display: Display, includeHidden: Bool) -> [RefreshOption] {
        guard let current = display.currentMode else { return [] }
        let key = ResolutionGroup.Key(current)
        var best: [Int: DisplayMode] = [:]
        for mode in display.modes where ResolutionGroup.Key(mode) == key {
            guard includeHidden || mode.origin == .system || mode.modeID == current.modeID else { continue }
            if let existing = best[mode.refreshKey], rank(existing, current) >= rank(mode, current) { continue }
            best[mode.refreshKey] = mode
        }
        return best.values
            .sorted { $0.refreshKey > $1.refreshKey }
            .map { RefreshOption(mode: $0, isCurrent: $0.modeID == current.modeID) }
    }

    /// For modes with the same refresh rate: the current mode, then the current bit depth,
    /// then system modes.
    private static func rank(_ mode: DisplayMode, _ current: DisplayMode) -> Int {
        (mode.modeID == current.modeID ? 4 : 0)
            + (mode.bitsPerSample == current.bitsPerSample ? 2 : 0)
            + (mode.origin == .system ? 1 : 0)
    }

    private static func systemThenFastest(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        let lhsRank = lhs.origin == .system ? 0 : 1
        let rhsRank = rhs.origin == .system ? 0 : 1
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.refreshKey != rhs.refreshKey { return lhs.refreshKey > rhs.refreshKey }
        return lhs.modeID < rhs.modeID
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ModeCatalogTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/Model/ModeCatalog.swift Tests/ResoluteKitTests/ModeCatalogTests.swift
git commit -m "Group display modes into resolutions and choose the mode to switch to"
```

---

### Task 4: Mode queries and display selectors for the CLI

**Files:**
- Create: `Sources/ResoluteKit/Model/ModeQuery.swift`, `Sources/ResoluteKit/Model/DisplaySelector.swift`
- Test: `Tests/ResoluteKitTests/ModeQueryTests.swift`

**Interfaces:**
- Consumes: `ModeCatalog`, `ResolutionGroup` (Task 3); `Display`, `DisplayMode`, `RefreshRate`, `ResoluteError` (Task 1).
- Produces: `ModeQuery(width:height:scale:refreshRate:modeID:useDefault:allowHidden:)`, `ModeQuery(resolution: String) throws`, `query.summary`, `query.resolve(on: Display) throws -> DisplayMode`; `DisplaySelector(_ text: String)` (`.main`, `.index(Int)`, `.id(CGDirectDisplayID)`, `.name(String)`), `selector.resolve(in: [Display]) throws -> Display`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/ResoluteKitTests/ModeQueryTests.swift | task: 4 | kind: test -->
```swift
import Testing
@testable import ResoluteKit

@Suite struct ModeQueryTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    @Test(arguments: ["1920x1080", "1920×1080", "1920 x 1080", "1920X1080"])
    func parsesPlainResolutions(text: String) throws {
        let query = try ModeQuery(resolution: text)
        #expect(query.width == 1920)
        #expect(query.height == 1080)
        #expect(query.scale == nil)
        #expect(query.refreshRate == nil)
    }

    @Test func parsesScaleAndRefreshRate() throws {
        let query = try ModeQuery(resolution: "1728x1117@2x@59.94Hz")
        #expect(query.scale == 2)
        #expect(query.refreshRate == 59.94)
        #expect(try ModeQuery(resolution: "1920x1200@60").refreshRate == 60)
        #expect(query.summary == "1728 × 1117 @2x 59.94 Hz")
    }

    @Test(arguments: ["", "1920", "1920x", "x1080", "0x0", "1920x1080@", "1920x1080@fast", "-1920x1080"])
    func rejectsMalformedResolutions(text: String) {
        #expect(throws: ResoluteError.invalidResolution(text)) {
            try ModeQuery(resolution: text)
        }
    }

    @Test func keepsTheCurrentRefreshRate() throws {
        #expect(try ModeQuery(resolution: "1496x967").resolve(on: display).modeID == 42)
    }

    @Test func honoursAnExplicitRefreshRateAndScale() throws {
        #expect(try ModeQuery(resolution: "1496x967@60").resolve(on: display).modeID == 43)
        #expect(try ModeQuery(resolution: "3456x2234@1x@59.94").resolve(on: display).modeID == 128)
    }

    @Test func changesOnlyTheRefreshRate() throws {
        #expect(try ModeQuery(refreshRate: 60).resolve(on: display).modeID == 55)
    }

    @Test func findsTheDefaultModeAndExactIDs() throws {
        let at60 = capture.display(currentModeID: 55)
        #expect(try ModeQuery(useDefault: true).resolve(on: at60).modeID == 54)
        #expect(try ModeQuery(modeID: 100).resolve(on: display).modeID == 100)
        #expect(throws: ResoluteError.modeNotFound("mode 5000", suggestions: [])) {
            try ModeQuery(modeID: 5_000).resolve(on: display)
        }
    }

    @Test func prefersTheCurrentScaleForAmbiguousSizes() throws {
        let atHiDPI = TestData.uhd(currentModeID: 12)
        #expect(try ModeQuery(resolution: "1920x1080").resolve(on: atHiDPI).modeID == 10)
        let atLowResolution = TestData.uhd(currentModeID: 22)
        #expect(try ModeQuery(resolution: "1920x1080").resolve(on: atLowResolution).modeID == 21)
        #expect(try ModeQuery(resolution: "1920x1080@2x").resolve(on: atLowResolution).modeID == 10)
    }

    @Test func suggestsNearbyResolutions() {
        let expected = ResoluteError.modeNotFound(
            "1500 × 970",
            suggestions: ["1496 × 967 (HiDPI)", "1496 × 935 (HiDPI)", "1312 × 848 (HiDPI)"]
        )
        #expect(throws: expected) {
            try ModeQuery(resolution: "1500x970").resolve(on: display)
        }
    }

    @Test func asksBeforeUsingHiddenModes() throws {
        let fullHD = TestData.fullHD()
        #expect(throws: ResoluteError.hiddenModeNeedsConfirmation("2560 × 1440")) {
            try ModeQuery(resolution: "2560x1440").resolve(on: fullHD)
        }
        var query = try ModeQuery(resolution: "2560x1440")
        query.allowHidden = true
        #expect(try query.resolve(on: fullHD).modeID == 91)
        #expect(throws: ResoluteError.hiddenModeNeedsConfirmation("mode 90")) {
            try ModeQuery(modeID: 90).resolve(on: fullHD)
        }
    }
}

@Suite struct DisplaySelectorTests {
    let displays = [
        TestData.uhd(id: 3),
        TestData.fullHD(id: 2),
        Display(id: 1, name: "Built-in Retina Display", isBuiltin: true, isMain: true, currentModeID: nil, modes: []),
    ]

    @Test func parsesSelectors() {
        #expect(DisplaySelector("main") == .main)
        #expect(DisplaySelector("MAIN") == .main)
        #expect(DisplaySelector("1") == .index(1))
        #expect(DisplaySelector("id:42") == .id(42))
        #expect(DisplaySelector("dell") == .name("dell"))
    }

    @Test func resolvesEachKind() throws {
        #expect(try DisplaySelector.main.resolve(in: displays).id == 1)
        #expect(try DisplaySelector.index(0).resolve(in: displays).id == 3)
        #expect(try DisplaySelector.id(2).resolve(in: displays).id == 2)
        #expect(try DisplaySelector.name("full hd").resolve(in: displays).id == 2)
    }

    @Test func reportsMissingAndAmbiguousDisplays() {
        #expect(throws: ResoluteError.displayNotFound("7")) {
            try DisplaySelector.index(7).resolve(in: displays)
        }
        #expect(throws: ResoluteError.ambiguousDisplay("monitor", matches: ["4K Monitor", "Full HD Monitor"])) {
            try DisplaySelector.name("monitor").resolve(in: displays)
        }
        #expect(throws: ResoluteError.noDisplays) {
            try DisplaySelector.main.resolve(in: [])
        }
    }

    @Test func prefersAnExactNameOverPartialMatches() throws {
        let similar = [
            Display(id: 5, name: "LG", currentModeID: nil, modes: []),
            Display(id: 6, name: "LG UltraFine", currentModeID: nil, modes: []),
        ]
        #expect(try DisplaySelector.name("lg").resolve(in: similar).id == 5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ModeQueryTests|DisplaySelectorTests"`
Expected: build failure — `cannot find 'ModeQuery' in scope`.

- [ ] **Step 3: Write the implementation**

<!-- file: Sources/ResoluteKit/Model/ModeQuery.swift | task: 4 | kind: impl -->
```swift
import Foundation

/// A request for a display mode, as typed on the command line.
public struct ModeQuery: Hashable, Sendable {
    public var width: Int?
    public var height: Int?
    /// 2 for HiDPI, 1 for low resolution.
    public var scale: Double?
    public var refreshRate: Double?
    public var modeID: Int32?
    public var useDefault: Bool
    public var allowHidden: Bool

    public init(
        width: Int? = nil,
        height: Int? = nil,
        scale: Double? = nil,
        refreshRate: Double? = nil,
        modeID: Int32? = nil,
        useDefault: Bool = false,
        allowHidden: Bool = false
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        self.refreshRate = refreshRate
        self.modeID = modeID
        self.useDefault = useDefault
        self.allowHidden = allowHidden
    }

    /// Parses "1920x1080", "1920×1080", "1920x1080@2x", "1920x1080@60" and
    /// "1920x1080@2x@59.94Hz".
    public init(resolution text: String) throws {
        self.init()
        let normalized = text.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " ", with: "")
        var parts = normalized.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        let size = parts.removeFirst()
        let dimensions = size.split(separator: "x", omittingEmptySubsequences: false)
        guard dimensions.count == 2,
              let width = Int(dimensions[0]), let height = Int(dimensions[1]),
              width > 0, height > 0
        else { throw ResoluteError.invalidResolution(text) }
        self.width = width
        self.height = height
        for part in parts {
            if part.hasSuffix("x"), let scale = Double(part.dropLast()), scale > 0 {
                self.scale = scale
            } else if let hertz = Double(part.hasSuffix("hz") ? String(part.dropLast(2)) : part), hertz > 0 {
                self.refreshRate = hertz
            } else {
                throw ResoluteError.invalidResolution(text)
            }
        }
    }

    /// "1920 × 1080 @2x 60 Hz", for messages.
    public var summary: String {
        var parts: [String] = []
        if let modeID { parts.append("mode \(modeID)") }
        if useDefault { parts.append("the default mode") }
        if let width, let height { parts.append("\(width) × \(height)") }
        if let scale { parts.append(scale == scale.rounded() ? "@\(Int(scale))x" : "@\(scale)x") }
        if let refreshRate { parts.append(RefreshRate.format(refreshRate)) }
        return parts.isEmpty ? "the current mode" : parts.joined(separator: " ")
    }

    /// The mode this query picks on `display`.
    public func resolve(on display: Display) throws -> DisplayMode {
        if let modeID {
            guard let mode = display.modes.first(where: { $0.modeID == modeID }) else {
                throw ResoluteError.modeNotFound(summary, suggestions: [])
            }
            guard allowHidden || mode.origin == .system else {
                throw ResoluteError.hiddenModeNeedsConfirmation(summary)
            }
            return mode
        }
        let matches = matchingModes(on: display, includeHidden: allowHidden)
        guard !matches.isEmpty else {
            if !allowHidden, !matchingModes(on: display, includeHidden: true).isEmpty {
                throw ResoluteError.hiddenModeNeedsConfirmation(summary)
            }
            throw ResoluteError.modeNotFound(summary, suggestions: suggestions(on: display))
        }
        let current = display.currentMode
        let groups = ModeCatalog.groups(matches)
        // Prefer the scale the display uses now, then HiDPI.
        let sameScale = groups.first { group in
            current.map { abs(group.modes[0].scale - $0.scale) < 0.01 } ?? false
        }
        let group = sameScale ?? groups.first(where: \.isHiDPI) ?? groups[0]
        return ModeCatalog.preferredMode(in: group, current: current)
    }

    func matchingModes(on display: Display, includeHidden: Bool) -> [DisplayMode] {
        let current = display.currentMode
        return display.modes.filter { mode in
            guard includeHidden || mode.origin == .system else { return false }
            if useDefault, !mode.isDefault { return false }
            if let width, let height {
                guard mode.width == width, mode.height == height else { return false }
            } else if !useDefault, let current {
                // Only a scale or a refresh rate was given: keep the current size.
                guard mode.width == current.width, mode.height == current.height else { return false }
            }
            if let scale, abs(mode.scale - scale) >= 0.01 { return false }
            if let refreshRate, mode.refreshKey != RefreshRate.key(refreshRate) { return false }
            return true
        }
    }

    /// The three system resolutions closest in area to the one asked for.
    func suggestions(on display: Display) -> [String] {
        guard let width, let height else { return [] }
        let target = width * height
        func distance(_ group: ResolutionGroup) -> Int {
            abs(group.key.width * group.key.height - target)
        }
        return ModeCatalog.groups(display.modes.filter { $0.origin == .system })
            .sorted { lhs, rhs in
                (distance(lhs), lhs.isHiDPI ? 0 : 1, -lhs.key.width) < (distance(rhs), rhs.isHiDPI ? 0 : 1, -rhs.key.width)
            }
            .prefix(3)
            .map { $0.sizeText + ($0.isHiDPI ? " (HiDPI)" : "") }
    }
}
```

<!-- file: Sources/ResoluteKit/Model/DisplaySelector.swift | task: 4 | kind: impl -->
```swift
import CoreGraphics
import Foundation

/// How a person names a display on the command line.
public enum DisplaySelector: Hashable, Sendable, CustomStringConvertible {
    case main
    /// A position in the list `resolute displays` prints.
    case index(Int)
    case id(CGDirectDisplayID)
    /// Part of the display's name, case-insensitive.
    case name(String)

    /// Reads "main", "id:<number>", a list index, or anything else as a name.
    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        if lowercased == "main" {
            self = .main
        } else if lowercased.hasPrefix("id:"), let id = CGDirectDisplayID(trimmed.dropFirst(3)) {
            self = .id(id)
        } else if let index = Int(trimmed) {
            self = .index(index)
        } else {
            self = .name(trimmed)
        }
    }

    public var description: String {
        switch self {
        case .main: "main"
        case .index(let index): "\(index)"
        case .id(let id): "id:\(id)"
        case .name(let name): name
        }
    }

    public func resolve(in displays: [Display]) throws -> Display {
        guard !displays.isEmpty else { throw ResoluteError.noDisplays }
        switch self {
        case .main:
            return displays.first(where: \.isMain) ?? displays[0]
        case .index(let index):
            guard displays.indices.contains(index) else { throw ResoluteError.displayNotFound(description) }
            return displays[index]
        case .id(let id):
            guard let display = displays.first(where: { $0.id == id }) else {
                throw ResoluteError.displayNotFound(description)
            }
            return display
        case .name(let name):
            if let exact = displays.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return exact
            }
            let matches = displays.filter { $0.name.localizedCaseInsensitiveContains(name) }
            guard !matches.isEmpty else { throw ResoluteError.displayNotFound(name) }
            guard matches.count == 1 else {
                throw ResoluteError.ambiguousDisplay(name, matches: matches.map(\.name))
            }
            return matches[0]
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ModeQueryTests|DisplaySelectorTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/Model/ModeQuery.swift Sources/ResoluteKit/Model/DisplaySelector.swift Tests/ResoluteKitTests/ModeQueryTests.swift
git commit -m "Parse resolution queries and display selectors for the command line"
```

---

### Task 5: Menu model and revert countdown

**Files:**
- Create: `Sources/ResoluteKit/Model/MenuModel.swift`, `Sources/ResoluteKit/Model/RevertCountdown.swift`
- Test: `Tests/ResoluteKitTests/MenuModelTests.swift`

**Interfaces:**
- Consumes: `ModeCatalog`, `ResolutionSection`, `RefreshOption` (Task 3); `Display`, `DisplayMode`, `RefreshRate` (Task 1).
- Produces: `MenuAction` (`.applyMode(displayID:modeID:needsConfirmation:)`, `.setMirroring(Bool)`, `.openCustomResolutions(displayID:)`, `.toggleLowResolutionModes`, `.toggleLaunchAtLogin`, `.showAbout`, `.quit`); `LaunchAtLoginState` (`.enabled`, `.disabled`, `.requiresApproval`, `.unavailable`); `MenuItem` (`title`, `subtitle`, `badge`, `symbolName`, `isChecked`, `isEnabled`, `action`, `keyEquivalent`, `submenu`); `MenuNode` (`.header(String)`, `.item(MenuItem)`, `.separator`); `MenuSettings(showLowResolutionModes:launchAtLogin:showsDetails:)`; `MenuModel.build(displays:settings:) -> [MenuNode]`, `MenuModel.render(_:) -> String`, `MenuModel.launchAtLoginItem(_:)`; `RevertCountdown(start:duration:)` with `secondsRemaining(at:)`, `isExpired(at:)`, `message(at:)`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/ResoluteKitTests/MenuModelTests.swift | task: 5 | kind: test -->
```swift
import Foundation
import Testing
@testable import ResoluteKit

@Suite struct MenuModelTests {
    let capture: CapturedDisplay
    let display: Display

    init() throws {
        capture = try CapturedDisplay.load()
        display = capture.display()
    }

    func item(_ nodes: [MenuNode], titled title: String) -> MenuItem? {
        for node in nodes {
            if case .item(let item) = node, item.title == title { return item }
        }
        return nil
    }

    func checkedCount(_ nodes: [MenuNode]) -> Int {
        nodes.filter { node in
            if case .item(let item) = node { return item.isChecked }
            return false
        }.count
    }

    @Test func startsWithTheDisplayAndItsCurrentMode() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        #expect(nodes.first == .header("Built-in Retina Display"))
        let resolution = try #require(item(nodes, titled: "1728 × 1117"))
        #expect(resolution.subtitle == "HiDPI · 3456 × 2234 pixels")
        let refresh = try #require(item(nodes, titled: "120 Hz"))
        #expect(refresh.submenu?.count == 6)
        #expect(item(refresh.submenu ?? [], titled: "60 Hz")?.action
            == .applyMode(displayID: 1, modeID: 55, needsConfirmation: false))
    }

    @Test func checksTheCurrentResolutionAndBadgesIt() throws {
        let nodes = MenuModel.build(displays: [display], settings: MenuSettings())
        let submenu = try #require(item(nodes, titled: "1728 × 1117")?.submenu)
        let current = try #require(item(submenu, titled: "1728 × 1117"))
        #expect(current.isChecked)
        #expect(current.badge == "Default")
        #expect(current.action == .applyMode(displayID: 1, modeID: 54, needsConfirmation: false))
        #expect(item(submenu, titled: "3456 × 2234")?.badge == "Native")
        #expect(checkedCount(submenu) == 1)
        #expect(submenu.contains(.header("HiDPI")))
        #expect(submenu.contains(.header("Low Resolution (1×)")))
        #expect(item(submenu, titled: "Custom Resolutions…")?.action == .openCustomResolutions(displayID: 1))
    }

    @Test func omitsLowResolutionModesWhenTurnedOff() throws {
        let off = MenuModel.build(displays: [display], settings: MenuSettings(showLowResolutionModes: false))
        let submenu = try #require(item(off, titled: "1728 × 1117")?.submenu)
        #expect(!submenu.contains(.header("Low Resolution (1×)")))
        #expect(item(submenu, titled: "3456 × 2234") == nil)
        #expect(item(off, titled: "Show Low-Resolution Modes")?.isChecked == false)
        #expect(item(off, titled: "Show Low-Resolution Modes")?.action == .toggleLowResolutionModes)
    }

    @Test func showsModeIDsAndHiddenModesWithDetails() throws {
        let fullHD = TestData.fullHD()
        let plain = try #require(item(MenuModel.build(displays: [fullHD], settings: MenuSettings()), titled: "1920 × 1080")?.submenu)
        #expect(item(plain, titled: "Hold ⌥ to Show Hidden Modes (2)")?.isEnabled == false)
        #expect(!plain.contains(.header("Hidden")))

        let detailed = try #require(item(
            MenuModel.build(displays: [fullHD], settings: MenuSettings(showsDetails: true)),
            titled: "1920 × 1080  #1"
        )?.submenu)
        #expect(detailed.contains(.header("Hidden")))
        let hidden = try #require(item(detailed, titled: "2560 × 1440  #91"))
        #expect(hidden.action == .applyMode(displayID: 2, modeID: 91, needsConfirmation: true))
        #expect(hidden.symbolName == "exclamationmark.triangle")
    }

    @Test func explainsWhyHiddenModesAreMissing() throws {
        var untrusted = display
        untrusted.privateModes = .untrusted(reason: "record 3 has an unrecognised layout")
        let submenu = try #require(item(
            MenuModel.build(displays: [untrusted], settings: MenuSettings(showsDetails: true)),
            titled: "1728 × 1117  #54"
        )?.submenu)
        #expect(item(submenu, titled: "Hidden Modes Unavailable")?.subtitle == "record 3 has an unrecognised layout")
    }

    @Test func offersMirroringOnlyWithTwoDisplays() throws {
        #expect(item(MenuModel.build(displays: [display], settings: MenuSettings()), titled: "Mirror Displays") == nil)
        var external = TestData.uhd()
        external.isInMirrorSet = true
        external.mirrorSourceID = 1
        var builtIn = display
        builtIn.isInMirrorSet = true
        let nodes = MenuModel.build(displays: [external, builtIn], settings: MenuSettings())
        let mirror = try #require(item(nodes, titled: "Mirror Displays"))
        #expect(mirror.isChecked)
        #expect(mirror.action == .setMirroring(false))
        #expect(nodes.first == .header("Built-in Retina Display"))
        #expect(nodes.contains(.header("4K Monitor — mirroring Built-in Retina Display")))
    }

    @Test func rendersWithoutACurrentMode() throws {
        let unknown = capture.display(currentModeID: 9_999)
        let nodes = MenuModel.build(displays: [unknown], settings: MenuSettings())
        let resolution = try #require(item(nodes, titled: "Choose a Resolution"))
        #expect(checkedCount(resolution.submenu ?? []) == 0)
        #expect(item(nodes, titled: "120 Hz") == nil)
    }

    @Test func omitsRefreshRateWhenUnknown() {
        let projector = Display(id: 7, name: "Projector", currentModeID: 1, modes: [
            TestData.mode(1, 1024, 768, hz: 0),
            TestData.mode(2, 800, 600, hz: 0),
        ])
        let rendered = MenuModel.render(MenuModel.build(displays: [projector], settings: MenuSettings()))
        #expect(!rendered.contains("Hz"))
        #expect(rendered.contains("✓ 1024 × 768"))
    }

    @Test func saysSoWhenThereAreNoDisplays() {
        let nodes = MenuModel.build(displays: [], settings: MenuSettings())
        #expect(item(nodes, titled: "No Displays Found")?.isEnabled == false)
        #expect(item(nodes, titled: "Quit Resolute")?.keyEquivalent == "q")
    }

    @Test func describesLaunchAtLoginStates() {
        #expect(MenuModel.launchAtLoginItem(.enabled).isChecked)
        #expect(!MenuModel.launchAtLoginItem(.disabled).isChecked)
        #expect(MenuModel.launchAtLoginItem(.requiresApproval).subtitle == "Needs approval in System Settings")
        #expect(!MenuModel.launchAtLoginItem(.unavailable).isEnabled)
    }

    @Test func rendersAPlainTextDump() {
        let small = Display(id: 9, name: "Tiny", isMain: true, currentModeID: 1, modes: [
            TestData.mode(1, 1280, 800, scale: 2, hz: 60, flags: 0x7),
            TestData.mode(2, 1280, 800, scale: 2, hz: 30),
            TestData.mode(3, 2560, 1600, hz: 60, flags: 0x0200_0003),
        ])
        let expected = """
            # Tiny
              1280 × 800 — HiDPI · 2560 × 1600 pixels ▸
                # HiDPI
                ✓ 1280 × 800 [Default]
                # Low Resolution (1×)
                  2560 × 1600 [Native]
                ---
                  Custom Resolutions…
              60 Hz ▸
                ✓ 60 Hz
                  30 Hz
            ---
              Custom Resolutions…
            ---
            ✓ Show Low-Resolution Modes
              Launch at Login
            ---
              About Resolute
              Quit Resolute
            """
        #expect(MenuModel.render(MenuModel.build(displays: [small], settings: MenuSettings())) == expected)
    }
}

@Suite struct RevertCountdownTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countsDownAndExpires() {
        let countdown = RevertCountdown(start: start, duration: 15)
        #expect(countdown.secondsRemaining(at: start) == 15)
        #expect(countdown.secondsRemaining(at: start.addingTimeInterval(14.2)) == 1)
        #expect(!countdown.isExpired(at: start.addingTimeInterval(14.9)))
        #expect(countdown.isExpired(at: start.addingTimeInterval(15)))
        #expect(countdown.secondsRemaining(at: start.addingTimeInterval(20)) == 0)
    }

    @Test func explainsWhatHappens() {
        let countdown = RevertCountdown(start: start, duration: 15)
        #expect(countdown.message(at: start)
            == "The previous mode comes back in 15 seconds unless you keep this one.")
        #expect(countdown.message(at: start.addingTimeInterval(14.5))
            == "The previous mode comes back in 1 second unless you keep this one.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "MenuModelTests|RevertCountdownTests"`
Expected: build failure — `cannot find 'MenuModel' in scope`.

- [ ] **Step 3: Write the implementation**

<!-- file: Sources/ResoluteKit/Model/MenuModel.swift | task: 5 | kind: impl -->
```swift
import CoreGraphics
import Foundation

/// What choosing a menu item does.
public enum MenuAction: Hashable, Sendable {
    case applyMode(displayID: CGDirectDisplayID, modeID: Int32, needsConfirmation: Bool)
    case setMirroring(Bool)
    case openCustomResolutions(displayID: CGDirectDisplayID?)
    case toggleLowResolutionModes
    case toggleLaunchAtLogin
    case showAbout
    case quit
}

/// Whether Resolute starts at login.
public enum LaunchAtLoginState: Hashable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    /// Not running from an app bundle, so macOS cannot register it.
    case unavailable
}

/// One menu item, independent of AppKit.
public struct MenuItem: Hashable, Sendable {
    public var title: String
    public var subtitle: String?
    public var badge: String?
    public var symbolName: String?
    public var isChecked: Bool
    public var isEnabled: Bool
    public var action: MenuAction?
    public var keyEquivalent: String
    public var submenu: [MenuNode]?

    public init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        symbolName: String? = nil,
        isChecked: Bool = false,
        isEnabled: Bool = true,
        action: MenuAction? = nil,
        keyEquivalent: String = "",
        submenu: [MenuNode]? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.symbolName = symbolName
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.submenu = submenu
    }
}

/// An entry in a menu.
public enum MenuNode: Hashable, Sendable {
    case header(String)
    case item(MenuItem)
    case separator
}

/// Preferences and state that shape the menu.
public struct MenuSettings: Hashable, Sendable {
    public var showLowResolutionModes: Bool
    public var launchAtLogin: LaunchAtLoginState
    /// True while ⌥ is held: show hidden modes, mode IDs and pixel sizes.
    public var showsDetails: Bool

    public init(
        showLowResolutionModes: Bool = true,
        launchAtLogin: LaunchAtLoginState = .disabled,
        showsDetails: Bool = false
    ) {
        self.showLowResolutionModes = showLowResolutionModes
        self.launchAtLogin = launchAtLogin
        self.showsDetails = showsDetails
    }
}

/// Builds the status-bar menu from display snapshots.
public enum MenuModel {
    public static func build(displays: [Display], settings: MenuSettings) -> [MenuNode] {
        var nodes: [MenuNode] = []
        if displays.isEmpty {
            nodes.append(.item(MenuItem(title: "No Displays Found", isEnabled: false)))
        }
        let names = Dictionary(displays.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for display in ordered(displays) {
            nodes.append(.header(headerTitle(for: display, names: names)))
            nodes.append(contentsOf: displayItems(for: display, settings: settings))
        }
        nodes.append(.separator)
        if displays.count > 1 {
            let mirroring = displays.contains(where: \.isInMirrorSet)
            nodes.append(.item(MenuItem(
                title: "Mirror Displays", symbolName: "rectangle.on.rectangle",
                isChecked: mirroring, action: .setMirroring(!mirroring)
            )))
        }
        nodes.append(.item(MenuItem(
            title: "Custom Resolutions…", symbolName: "slider.horizontal.3",
            action: .openCustomResolutions(displayID: nil)
        )))
        nodes.append(.separator)
        nodes.append(.item(MenuItem(
            title: "Show Low-Resolution Modes",
            isChecked: settings.showLowResolutionModes, action: .toggleLowResolutionModes
        )))
        nodes.append(.item(launchAtLoginItem(settings.launchAtLogin)))
        nodes.append(.separator)
        nodes.append(.item(MenuItem(title: "About Resolute", action: .showAbout)))
        nodes.append(.item(MenuItem(title: "Quit Resolute", action: .quit, keyEquivalent: "q")))
        return nodes
    }

    public static func launchAtLoginItem(_ state: LaunchAtLoginState) -> MenuItem {
        switch state {
        case .enabled:
            MenuItem(title: "Launch at Login", isChecked: true, action: .toggleLaunchAtLogin)
        case .disabled:
            MenuItem(title: "Launch at Login", action: .toggleLaunchAtLogin)
        case .requiresApproval:
            MenuItem(title: "Launch at Login", subtitle: "Needs approval in System Settings", action: .toggleLaunchAtLogin)
        case .unavailable:
            MenuItem(title: "Launch at Login", subtitle: "Available when Resolute runs from its app bundle", isEnabled: false)
        }
    }

    /// A plain-text rendering, for `Resolute --dump-menu` and tests.
    public static func render(_ nodes: [MenuNode]) -> String {
        render(nodes, depth: 0).joined(separator: "\n")
    }

    // MARK: - Pieces

    /// Main display first, then built-in displays, then by ID.
    static func ordered(_ displays: [Display]) -> [Display] {
        displays.sorted { lhs, rhs in
            (lhs.isMain ? 0 : 1, lhs.isBuiltin ? 0 : 1, lhs.id) < (rhs.isMain ? 0 : 1, rhs.isBuiltin ? 0 : 1, rhs.id)
        }
    }

    static func headerTitle(for display: Display, names: [CGDirectDisplayID: String]) -> String {
        guard let source = display.mirrorSourceID, let sourceName = names[source] else { return display.name }
        return "\(display.name) — mirroring \(sourceName)"
    }

    static func displayItems(for display: Display, settings: MenuSettings) -> [MenuNode] {
        let current = display.currentMode
        var nodes: [MenuNode] = [
            .item(MenuItem(
                title: current.map { $0.sizeText + idSuffix($0, settings) } ?? "Choose a Resolution",
                subtitle: current.flatMap { resolutionSubtitle(for: $0, on: display) },
                symbolName: "display",
                submenu: resolutionSubmenu(for: display, settings: settings)
            )),
        ]
        guard let current, current.refreshRate > 0 else { return nodes }
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: settings.showsDetails)
            .filter { $0.refreshRate > 0 }
        let title = RefreshRate.format(current.refreshRate)
        if options.count > 1 {
            nodes.append(.item(MenuItem(
                title: title,
                symbolName: "arrow.triangle.2.circlepath",
                submenu: options.map { option in
                    MenuNode.item(MenuItem(
                        title: RefreshRate.format(option.refreshRate) + idSuffix(option.mode, settings),
                        symbolName: option.mode.origin == .hidden ? "exclamationmark.triangle" : nil,
                        isChecked: option.isCurrent,
                        action: .applyMode(
                            displayID: display.id, modeID: option.mode.modeID,
                            needsConfirmation: option.mode.origin == .hidden
                        )
                    ))
                }
            )))
        } else {
            nodes.append(.item(MenuItem(title: title, symbolName: "arrow.triangle.2.circlepath", isEnabled: false)))
        }
        return nodes
    }

    static func resolutionSubtitle(for mode: DisplayMode, on display: Display) -> String? {
        if mode.isHiDPI { return "HiDPI · \(mode.pixelSizeText) pixels" }
        // Worth saying only on displays that also offer HiDPI modes.
        return display.modes.contains(where: \.isHiDPI) ? "Low resolution (1×)" : nil
    }

    static func idSuffix(_ mode: DisplayMode, _ settings: MenuSettings) -> String {
        settings.showsDetails ? "  #\(mode.modeID)" : ""
    }

    static func resolutionSubmenu(for display: Display, settings: MenuSettings) -> [MenuNode] {
        var nodes: [MenuNode] = []
        let currentKey = ModeCatalog.currentKey(for: display)
        let sections = ModeCatalog.sections(
            for: display,
            includeLowResolution: settings.showLowResolutionModes,
            includeHidden: settings.showsDetails
        )
        for section in sections {
            nodes.append(.header(section.kind.title))
            for group in section.groups {
                let mode = ModeCatalog.preferredMode(in: group, current: display.currentMode)
                nodes.append(.item(MenuItem(
                    title: group.sizeText + idSuffix(mode, settings),
                    subtitle: settings.showsDetails && group.isHiDPI ? "\(group.pixelSizeText) pixels" : nil,
                    badge: group.isDefault ? "Default" : group.isNative ? "Native" : nil,
                    symbolName: group.isHidden ? "exclamationmark.triangle" : nil,
                    isChecked: group.key == currentKey,
                    action: .applyMode(displayID: display.id, modeID: mode.modeID, needsConfirmation: mode.origin == .hidden)
                )))
            }
        }
        if sections.isEmpty {
            nodes.append(.item(MenuItem(title: "No Modes Available", isEnabled: false)))
        }
        nodes.append(.separator)
        if !settings.showsDetails, display.hiddenModeCount > 0 {
            nodes.append(.item(MenuItem(
                title: "Hold ⌥ to Show Hidden Modes (\(display.hiddenModeCount))", isEnabled: false
            )))
        }
        if settings.showsDetails, case .untrusted(let reason) = display.privateModes {
            nodes.append(.item(MenuItem(title: "Hidden Modes Unavailable", subtitle: reason, isEnabled: false)))
        }
        nodes.append(.item(MenuItem(title: "Custom Resolutions…", action: .openCustomResolutions(displayID: display.id))))
        return nodes
    }

    private static func render(_ nodes: [MenuNode], depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        var lines: [String] = []
        for node in nodes {
            switch node {
            case .header(let title):
                lines.append("\(indent)# \(title)")
            case .separator:
                lines.append("\(indent)---")
            case .item(let item):
                var line = indent + (item.isChecked ? "✓ " : "  ") + item.title
                if let subtitle = item.subtitle { line += " — \(subtitle)" }
                if let badge = item.badge { line += " [\(badge)]" }
                if !item.isEnabled { line += " (disabled)" }
                if item.submenu != nil { line += " ▸" }
                lines.append(line)
                if let submenu = item.submenu { lines += render(submenu, depth: depth + 1) }
            }
        }
        return lines
    }
}
```

<!-- file: Sources/ResoluteKit/Model/RevertCountdown.swift | task: 5 | kind: impl -->
```swift
import Foundation

/// The "keep this display mode?" countdown shown after switching to a hidden mode.
public struct RevertCountdown: Equatable, Sendable {
    public let deadline: Date

    public init(start: Date = Date(), duration: TimeInterval = 15) {
        deadline = start.addingTimeInterval(duration)
    }

    public func secondsRemaining(at date: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(date).rounded(.up)))
    }

    public func isExpired(at date: Date) -> Bool {
        date >= deadline
    }

    public func message(at date: Date) -> String {
        let seconds = secondsRemaining(at: date)
        return "The previous mode comes back in \(seconds) second\(seconds == 1 ? "" : "s") unless you keep this one."
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "MenuModelTests|RevertCountdownTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/Model/MenuModel.swift Sources/ResoluteKit/Model/RevertCountdown.swift Tests/ResoluteKitTests/MenuModelTests.swift
git commit -m "Build the status menu as a pure model with a text rendering"
```

---
### Task 6: Override files — entry codec, plist model, store, aspect ratios

**Files:**
- Create: `Sources/ResoluteKit/Overrides/ScaleResolution.swift`, `Sources/ResoluteKit/Overrides/DisplayOverride.swift`, `Sources/ResoluteKit/Overrides/OverrideStore.swift`, `Sources/ResoluteKit/Model/AspectRatio.swift`, `Tests/ResoluteKitTests/Support/Files.swift`
- Test: `Tests/ResoluteKitTests/OverrideFileTests.swift`

**Interfaces:**
- Consumes: `Display`, `ResoluteError` (Task 1).
- Produces: `HiDPIFlags(primary:secondary:)`, `HiDPIFlags.standard`, `HiDPIFlags.hiDPIBit`, `HiDPIFlags(parsing:) throws`, `flags.description`; `ScaleResolution` (`.hiDPI(width:height:flags:)` in points, `.standard(width:height:)` in pixels, `.preserved(PreservedEntry)`), with `isEditable`, `sizeText`, `kindText`, `pixelSize`, `summary`, `sameMode(as:)`; `PreservedEntry` (`.data(Data)`, `.value(Data)`); `ScaleResolutionCodec.decode(_ elements: [Any]) -> [ScaleResolution]`, `.encode(_:) -> [Any]`; `OverrideKey(vendorID:productID:)`, `OverrideKey(display:)`, `OverrideKey(vendorDirectory:productFile:)`, `vendorDirectoryName`, `productFileName`, `relativePath`, `Comparable`; `PropertyListDictionary`; `DisplayOverride(key:productName:resolutions:otherKeys:)`, `DisplayOverride(key:propertyList:) throws`, `propertyListData() throws -> Data`; `OverrideLocations(userRoot:systemRoot:backupRoot:)`, `.standard`, `.staged(at:)`, `userFile(for:)`, `systemFile(for:)`; `OverrideStore(locations:)` with `installedOverride(for:)`, `systemOverride(for:)`, `editableOverride(for:) -> (override:, source: .installed | .system | .missing)`, `installedKeys()`; `AspectRatio(width:height:)`, `description`, `value`, `presets`, `height(forWidth:)`. Test helpers `makeTemporaryDirectory()`, `hexData(_:)`, `rdmOverrideXML`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/ResoluteKitTests/Support/Files.swift | task: 6 | kind: test -->
```swift
import Foundation

/// A fresh temporary directory. Its name contains a space and a single quote, so every
/// test that writes files also checks path quoting.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "Resolute Tests 'quoted' \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func hexData(_ hex: String) -> Data {
    Data(TestData.bytes(hex: hex.replacingOccurrences(of: " ", with: "")))
}

/// The override RDM wrote on the development Mac for a 5120×2160 monitor, byte for byte.
let rdmOverrideXML = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DisplayProductName</key>
	<string></string>
	<key>scale-resolutions</key>
	<array>
		<data>
		AAAUAAAACHA=
		</data>
		<data>
		AAAUAAAACHAAAAALAKAAAA==
		</data>
	</array>
	<key>target-default-ppmm</key>
	<real>10.01</real>
</dict>
</plist>
"""
```

<!-- file: Tests/ResoluteKitTests/OverrideFileTests.swift | task: 6 | kind: test -->
```swift
import Foundation
import Testing
@testable import ResoluteKit

@Suite struct ScaleResolutionCodecTests {
    let rdmKey = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    @Test func decodesTheRDMOverride() throws {
        let override = try DisplayOverride(key: rdmKey, propertyList: Data(rdmOverrideXML.utf8))
        #expect(override.productName == nil)
        #expect(override.resolutions == [
            .hiDPI(width: 2560, height: 1080, flags: HiDPIFlags(primary: 0xB, secondary: 0x00A0_0000)),
        ])
        #expect(override.otherKeys.keys == ["target-default-ppmm"])
    }

    @Test func writesTheRDMOverrideBackUnchanged() throws {
        let original = try #require(
            try PropertyListSerialization.propertyList(from: Data(rdmOverrideXML.utf8), format: nil) as? [String: Any]
        )
        let override = try DisplayOverride(key: rdmKey, propertyList: Data(rdmOverrideXML.utf8))
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["scale-resolutions"] as? [Data] == original["scale-resolutions"] as? [Data])
        #expect(written["target-default-ppmm"] as? Double == 10.01)
        // RDM wrote an empty name, which blanks the display's name in macOS; Resolute omits it.
        #expect(written["DisplayProductName"] == nil)
    }

    @Test func keepsEntriesItDoesNotModel() throws {
        let nineBytes = hexData("00000f00 00000960 00")
        let twelveBytes = hexData("00000672 0000041a 00000001")
        let plainSixteen = hexData("00000780 00000438 00000000 00200000")
        let entries = ScaleResolutionCodec.decode([nineBytes, twelveBytes, plainSixteen, 32_768_800])
        #expect(Array(entries.prefix(3)) == [
            .preserved(.data(nineBytes)), .preserved(.data(twelveBytes)), .preserved(.data(plainSixteen)),
        ])
        guard case .preserved(.value) = entries[3] else {
            Issue.record("expected the number to be preserved")
            return
        }
        #expect(entries.allSatisfy { !$0.isEditable })
        let encoded = ScaleResolutionCodec.encode(entries)
        #expect(encoded.count == 4)
        #expect(encoded[0] as? Data == nineBytes)
        #expect(encoded[1] as? Data == twelveBytes)
        #expect(encoded[2] as? Data == plainSixteen)
        #expect(encoded[3] as? Int == 32_768_800)
    }

    @Test func recognisesHiDPIEntriesAndTheirBackingEntries() {
        let hiDPI = hexData("00000a00 00000640 00000001 00200000")
        let backing = hexData("00000a00 00000640")
        let other = hexData("00000780 00000438")
        #expect(ScaleResolutionCodec.decode([backing, hiDPI, other]) == [
            .hiDPI(width: 1280, height: 800, flags: HiDPIFlags(primary: 1, secondary: 0x0020_0000)),
            .standard(width: 1920, height: 1080),
        ])
    }

    @Test func writesStandardThenBackingThenHiDPIEntries() {
        let encoded = ScaleResolutionCodec.encode([
            .hiDPI(width: 1280, height: 720, flags: .standard),
            .standard(width: 1920, height: 1080),
            .hiDPI(width: 1920, height: 1080, flags: .standard),
            .standard(width: 2560, height: 1440),
        ]).compactMap { ($0 as? Data).map { $0.map { String(format: "%02x", $0) }.joined() } }
        #expect(encoded == [
            "00000a00000005a0",                  // 2560×1440 at 1× (also backs 1280×720 HiDPI)
            "0000078000000438",                  // 1920×1080 at 1×
            "00000f0000000870",                  // backs 1920×1080 HiDPI
            "00000f00000008700000000900a00000",  // 1920×1080 HiDPI
            "00000a00000005a00000000900a00000",  // 1280×720 HiDPI
        ])
    }

    @Test(arguments: ["00000009 00a00000", "0x9 0xa00000", "0000000900a00000", "9,a00000"])
    func parsesFlags(text: String) throws {
        #expect(try HiDPIFlags(parsing: text) == .standard)
    }

    @Test(arguments: ["", "zz 00", "1 2 3", "123456789 0"])
    func rejectsBadFlags(text: String) {
        #expect(throws: ResoluteError.invalidFlags(text)) {
            try HiDPIFlags(parsing: text)
        }
    }

    @Test func describesEntries() {
        let entry = ScaleResolution.hiDPI(width: 2560, height: 1080, flags: .standard)
        #expect(entry.sizeText == "2560 × 1080")
        #expect(entry.kindText == "HiDPI")
        #expect(entry.pixelSize?.width == 5120)
        #expect(entry.summary == "2560 × 1080 HiDPI (5120 × 2160 px, flags 00000009 00a00000)")
        #expect(ScaleResolution.standard(width: 1920, height: 1080).summary == "1920 × 1080 1×")
        #expect(entry.sameMode(as: .hiDPI(width: 2560, height: 1080, flags: HiDPIFlags(primary: 1, secondary: 0))))
        #expect(!entry.sameMode(as: .standard(width: 2560, height: 1080)))
    }
}

@Suite struct DisplayOverrideTests {
    let key = OverrideKey(vendorID: 0x10AC, productID: 0xA0C4)

    @Test func preservesKeysItDoesNotEdit() throws {
        let source: [String: Any] = [
            "DisplayProductName": "DELL U2720Q",
            "DisplayVendorID": 4268,
            "IODisplayEDID": Data([0, 255, 255]),
            "scale-resolutions": [hexData("00000780 00000438")],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .binary, options: 0)
        var override = try DisplayOverride(key: key, propertyList: data)
        #expect(override.productName == "DELL U2720Q")
        override.resolutions.append(.hiDPI(width: 1600, height: 900, flags: .standard))
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["DisplayVendorID"] as? Int == 4268)
        #expect(written["IODisplayEDID"] as? Data == Data([0, 255, 255]))
        #expect(written["DisplayProductName"] as? String == "DELL U2720Q")
        #expect((written["scale-resolutions"] as? [Data])?.count == 3)
        #expect(written["target-default-ppmm"] as? Double == 10.01)
    }

    @Test func writesNothingForAnEmptyOverride() throws {
        let written = try #require(
            try PropertyListSerialization.propertyList(from: DisplayOverride(key: key).propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written.isEmpty)
    }

    @Test func keepsAWrongTypedResolutionsKey() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["scale-resolutions": "garbage"], format: .xml, options: 0)
        let override = try DisplayOverride(key: key, propertyList: data)
        #expect(override.resolutions.isEmpty)
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["scale-resolutions"] as? String == "garbage")
    }

    @Test func rejectsFilesThatAreNotDictionaries() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [1, 2], format: .xml, options: 0)
        let expected = ResoluteError.overrideUnreadable(
            path: "DisplayVendorID-10ac/DisplayProductID-a0c4", reason: "the file is not a dictionary"
        )
        #expect(throws: expected) {
            try DisplayOverride(key: key, propertyList: data)
        }
    }

    @Test func namesFilesInLowercaseHex() {
        #expect(key.relativePath == "DisplayVendorID-10ac/DisplayProductID-a0c4")
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-DB4", productFile: "DisplayProductID-3401")
            == OverrideKey(vendorID: 0xDB4, productID: 0x3401))
        #expect(OverrideKey(vendorDirectory: "Icons.plist", productFile: "x") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-610", productFile: "DisplayProductID-zz") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-610", productFile: "DisplayProductID-a050.plist") == nil)
    }
}

@Suite struct OverrideStoreTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func findsInstalledOverridesAndIgnoresOtherFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        try write(rdmOverrideXML, to: store.locations.userFile(for: key))
        try write("", to: store.locations.userRoot.appending(path: "Icons.plist"))
        try write("", to: store.locations.userRoot.appending(path: "DisplayVendorID-610/DisplayProductID-zz"))
        try write("", to: store.locations.userRoot.appending(path: "DisplayVendorID-610/.DS_Store"))
        #expect(store.installedKeys() == [key])
    }

    @Test func prefersTheInstalledOverride() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        try write(rdmOverrideXML, to: store.locations.userFile(for: key))
        let systemData = try PropertyListSerialization.data(fromPropertyList: ["DisplayProductName": "Apple's"], format: .xml, options: 0)
        try write(String(decoding: systemData, as: UTF8.self), to: store.locations.systemFile(for: key))
        let (override, source) = try store.editableOverride(for: key)
        #expect(source == .installed)
        #expect(override.resolutions.count == 1)
    }

    @Test func fallsBackToTheSystemOverrideThenToNothing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let builtIn = OverrideKey(vendorID: 0x610, productID: 0xA050)
        #expect(try store.editableOverride(for: builtIn).source == .missing)
        let data = try PropertyListSerialization.data(fromPropertyList: ["DisplayProductName": "Color LCD"], format: .xml, options: 0)
        try write(String(decoding: data, as: UTF8.self), to: store.locations.systemFile(for: builtIn))
        let (override, source) = try store.editableOverride(for: builtIn)
        #expect(source == .system)
        #expect(override.productName == "Color LCD")
    }

    @Test func reportsUnreadableFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let url = store.locations.userFile(for: key)
        try write("<plist><dict><key>broken", to: url)
        let expected = ResoluteError.overrideUnreadable(
            path: url.path(percentEncoded: false), reason: "it is not a valid property list"
        )
        #expect(throws: expected) {
            try store.installedOverride(for: key)
        }
    }

    @Test func pointsAtTheStandardLocations() {
        #expect(OverrideLocations.standard.userFile(for: key).path(percentEncoded: false)
            == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-db4/DisplayProductID-3401")
        #expect(OverrideLocations.standard.backupRoot.path(percentEncoded: false)
            == "/Library/Application Support/Resolute/Backups/")
    }
}

@Suite struct AspectRatioTests {
    @Test(arguments: [
        (1920, 1080, "16:9"), (2560, 1600, "16:10"), (5120, 2160, "64:27"), (3440, 1440, "43:18"),
        (2520, 1080, "21:9"), (1728, 1117, "1.55:1"), (1024, 768, "4:3"), (0, 1080, "—"),
    ])
    func describesRatios(width: Int, height: Int, expected: String) {
        #expect(AspectRatio(width: width, height: height).description == expected)
    }

    @Test func computesHeightsFromWidths() {
        #expect(AspectRatio(width: 16, height: 9).height(forWidth: 2560) == 1440)
        #expect(AspectRatio(width: 64, height: 27).height(forWidth: 3840) == 1620)
        #expect(AspectRatio.presets.map(\.description) == ["16:9", "16:10", "21:9", "32:9", "64:27", "4:3", "3:2"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ScaleResolutionCodecTests|DisplayOverrideTests|OverrideStoreTests|AspectRatioTests"`
Expected: build failure — `cannot find 'DisplayOverride' in scope`.

- [ ] **Step 3: Write the implementation**

<!-- file: Sources/ResoluteKit/Overrides/ScaleResolution.swift | task: 6 | kind: impl -->
```swift
import Foundation

/// The two flag words stored with a HiDPI `scale-resolutions` entry.
public struct HiDPIFlags: Hashable, Sendable, CustomStringConvertible {
    public var primary: UInt32
    public var secondary: UInt32

    public init(primary: UInt32, secondary: UInt32) {
        self.primary = primary
        self.secondary = secondary
    }

    /// The combination Apple uses for most HiDPI entries in its own override files.
    public static let standard = HiDPIFlags(primary: 0x0000_0009, secondary: 0x00A0_0000)

    /// Bit 0 of the first word marks an entry as HiDPI.
    public static let hiDPIBit: UInt32 = 0x1

    /// "00000009 00a00000"
    public var description: String {
        String(format: "%08x %08x", primary, secondary)
    }

    /// Parses "00000009 00a00000", "0x9 0xa00000", "9,a00000" or "0000000900a00000".
    public init(parsing text: String) throws {
        func word(_ text: Substring) -> UInt32? {
            let digits = text.lowercased().hasPrefix("0x") ? text.dropFirst(2) : text
            guard !digits.isEmpty, digits.count <= 8 else { return nil }
            return UInt32(digits, radix: 16)
        }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        if words.count == 2, let primary = word(words[0]), let secondary = word(words[1]) {
            self.init(primary: primary, secondary: secondary)
        } else if words.count == 1, words[0].count == 16, let value = UInt64(words[0], radix: 16) {
            self.init(primary: UInt32(value >> 32), secondary: UInt32(value & 0xFFFF_FFFF))
        } else {
            throw ResoluteError.invalidFlags(text)
        }
    }
}

/// One element of a display override's `scale-resolutions` array.
public enum ScaleResolution: Hashable, Sendable {
    /// A HiDPI mode. Sizes are in points; the file stores twice as many pixels.
    case hiDPI(width: Int, height: Int, flags: HiDPIFlags)
    /// A 1× mode, in pixels.
    case standard(width: Int, height: Int)
    /// An element Resolute does not interpret; written back unchanged.
    case preserved(PreservedEntry)

    public var isEditable: Bool {
        if case .preserved = self { return false }
        return true
    }

    /// "2560 × 1080"
    public var sizeText: String {
        switch self {
        case .hiDPI(let width, let height, _), .standard(let width, let height):
            "\(width) × \(height)"
        case .preserved(let entry):
            entry.summary
        }
    }

    /// "HiDPI", "1×" or "Kept as is"
    public var kindText: String {
        switch self {
        case .hiDPI: "HiDPI"
        case .standard: "1×"
        case .preserved: "Kept as is"
        }
    }

    /// The pixels macOS renders for this entry.
    public var pixelSize: (width: Int, height: Int)? {
        switch self {
        case .hiDPI(let width, let height, _): (width * 2, height * 2)
        case .standard(let width, let height): (width, height)
        case .preserved: nil
        }
    }

    /// "2560 × 1080 HiDPI (5120 × 2160 px, flags 0000000b 00a00000)"
    public var summary: String {
        switch self {
        case .hiDPI(let width, let height, let flags):
            "\(width) × \(height) HiDPI (\(width * 2) × \(height * 2) px, flags \(flags))"
        case .standard(let width, let height):
            "\(width) × \(height) 1×"
        case .preserved(let entry):
            "\(entry.summary), kept as is"
        }
    }

    /// Same kind and size, whatever the flags.
    public func sameMode(as other: ScaleResolution) -> Bool {
        switch (self, other) {
        case let (.hiDPI(lhsWidth, lhsHeight, _), .hiDPI(rhsWidth, rhsHeight, _)),
             let (.standard(lhsWidth, lhsHeight), .standard(rhsWidth, rhsHeight)):
            lhsWidth == rhsWidth && lhsHeight == rhsHeight
        default:
            false
        }
    }
}

/// A `scale-resolutions` element kept byte for byte.
public enum PreservedEntry: Hashable, Sendable {
    case data(Data)
    /// A non-data property-list value, archived as a binary property list.
    case value(Data)

    var propertyListValue: Any {
        switch self {
        case .data(let data):
            return data
        case .value(let archive):
            return (try? PropertyListSerialization.propertyList(from: archive, format: nil)) ?? archive
        }
    }

    public var summary: String {
        switch self {
        case .data(let data):
            let words = ScaleResolutionCodec.words(data)
            return words.count >= 2 ? "\(data.count)-byte entry \(words[0]) × \(words[1])" : "\(data.count)-byte entry"
        case .value:
            return "value \(propertyListValue)"
        }
    }
}

/// Reads and writes `scale-resolutions` arrays.
public enum ScaleResolutionCodec {
    public static func decode(_ elements: [Any]) -> [ScaleResolution] {
        var entries = elements.map(decodeElement)
        // A 1× entry at a HiDPI entry's pixel size only backs that entry; `encode` recreates it.
        let backingSizes = Set(entries.compactMap { entry -> PixelSize? in
            guard case .hiDPI(let width, let height, _) = entry else { return nil }
            return PixelSize(width: width * 2, height: height * 2)
        })
        entries.removeAll { entry in
            guard case .standard(let width, let height) = entry else { return false }
            return backingSizes.contains(PixelSize(width: width, height: height))
        }
        var seen = Set<ScaleResolution>()
        return entries.filter { seen.insert($0).inserted }
    }

    /// 1× entries, then the 1× entries that back HiDPI entries, then HiDPI entries (each
    /// largest first, as RDM wrote them), then preserved elements in their original order.
    public static func encode(_ entries: [ScaleResolution]) -> [Any] {
        var standard: [PixelSize] = []
        var hiDPI: [(size: PixelSize, flags: HiDPIFlags)] = []
        var preserved: [Any] = []
        for entry in entries {
            switch entry {
            case .standard(let width, let height): standard.append(PixelSize(width: width, height: height))
            case .hiDPI(let width, let height, let flags): hiDPI.append((PixelSize(width: width, height: height), flags))
            case .preserved(let element): preserved.append(element.propertyListValue)
            }
        }
        standard.sort(by: PixelSize.largerFirst)
        hiDPI.sort { PixelSize.largerFirst($0.size, $1.size) }
        var written = Set(standard)
        var backing: [PixelSize] = []
        for entry in hiDPI {
            let size = PixelSize(width: entry.size.width * 2, height: entry.size.height * 2)
            if written.insert(size).inserted { backing.append(size) }
        }
        let standardData: [Any] = (standard + backing).map { data([UInt32($0.width), UInt32($0.height)]) }
        let hiDPIData: [Any] = hiDPI.map {
            data([UInt32($0.size.width * 2), UInt32($0.size.height * 2), $0.flags.primary, $0.flags.secondary])
        }
        return standardData + hiDPIData + preserved
    }

    static func decodeElement(_ element: Any) -> ScaleResolution {
        guard let data = element as? Data else {
            let archive = (try? PropertyListSerialization.data(fromPropertyList: element, format: .binary, options: 0)) ?? Data()
            return .preserved(.value(archive))
        }
        let words = words(data)
        switch data.count {
        case 8 where words[0] > 0 && words[1] > 0:
            return .standard(width: Int(words[0]), height: Int(words[1]))
        case 16 where words[2] & HiDPIFlags.hiDPIBit != 0
            && words[0] > 0 && words[1] > 0 && words[0] % 2 == 0 && words[1] % 2 == 0:
            return .hiDPI(
                width: Int(words[0] / 2), height: Int(words[1] / 2),
                flags: HiDPIFlags(primary: words[2], secondary: words[3])
            )
        default:
            return .preserved(.data(data))
        }
    }

    /// The big-endian 32-bit words in `data`.
    static func words(_ data: Data) -> [UInt32] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - bytes.count % 4, by: 4).map { index in
            UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16
                | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
        }
    }

    static func data(_ words: [UInt32]) -> Data {
        var bytes: [UInt8] = []
        for word in words {
            bytes += [UInt8(word >> 24), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)]
        }
        return Data(bytes)
    }
}

struct PixelSize: Hashable, Sendable {
    var width: Int
    var height: Int

    static func largerFirst(_ lhs: PixelSize, _ rhs: PixelSize) -> Bool {
        (lhs.width, lhs.height) > (rhs.width, rhs.height)
    }
}
```

<!-- file: Sources/ResoluteKit/Overrides/DisplayOverride.swift | task: 6 | kind: impl -->
```swift
import Foundation

/// Identifies a display model the way override files do: by vendor and product ID.
public struct OverrideKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var vendorID: UInt32
    public var productID: UInt32

    public init(vendorID: UInt32, productID: UInt32) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public init(display: Display) {
        self.init(vendorID: display.vendorID, productID: display.productID)
    }

    /// Parses "DisplayVendorID-db4" and "DisplayProductID-3401".
    public init?(vendorDirectory: String, productFile: String) {
        guard let vendor = Self.hexSuffix(of: vendorDirectory, after: "DisplayVendorID-"),
              let product = Self.hexSuffix(of: productFile, after: "DisplayProductID-")
        else { return nil }
        self.init(vendorID: vendor, productID: product)
    }

    /// "DisplayVendorID-db4"
    public var vendorDirectoryName: String { "DisplayVendorID-" + String(vendorID, radix: 16) }
    /// "DisplayProductID-3401"
    public var productFileName: String { "DisplayProductID-" + String(productID, radix: 16) }
    /// "DisplayVendorID-db4/DisplayProductID-3401"
    public var relativePath: String { "\(vendorDirectoryName)/\(productFileName)" }
    /// "vendor db4, product 3401"
    public var description: String {
        "vendor \(String(vendorID, radix: 16)), product \(String(productID, radix: 16))"
    }

    public static func < (lhs: OverrideKey, rhs: OverrideKey) -> Bool {
        (lhs.vendorID, lhs.productID) < (rhs.vendorID, rhs.productID)
    }

    private static func hexSuffix(of name: String, after prefix: String) -> UInt32? {
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/// A property-list dictionary that is `Sendable` and compares by content.
public struct PropertyListDictionary: Equatable, Sendable {
    private let archive: Data

    public static let empty = PropertyListDictionary([:])

    public init(_ dictionary: [String: Any]) {
        archive = (try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)) ?? Data()
    }

    public var dictionary: [String: Any] {
        ((try? PropertyListSerialization.propertyList(from: archive, format: nil)) as? [String: Any]) ?? [:]
    }

    public var keys: [String] { dictionary.keys.sorted() }

    public static func == (lhs: PropertyListDictionary, rhs: PropertyListDictionary) -> Bool {
        NSDictionary(dictionary: lhs.dictionary).isEqual(to: rhs.dictionary)
    }
}

/// The contents of one override file (`DisplayVendorID-xxxx/DisplayProductID-yyyy`).
public struct DisplayOverride: Equatable, Sendable {
    public static let productNameKey = "DisplayProductName"
    public static let resolutionsKey = "scale-resolutions"
    public static let targetPPMMKey = "target-default-ppmm"
    /// The value RDM wrote when a file had none.
    public static let defaultTargetPPMM = 10.01

    public var key: OverrideKey
    /// Replaces the display's name in macOS; nil keeps the display's own name.
    public var productName: String?
    public var resolutions: [ScaleResolution]
    /// Every other key in the file, written back unchanged.
    public var otherKeys: PropertyListDictionary

    public init(
        key: OverrideKey,
        productName: String? = nil,
        resolutions: [ScaleResolution] = [],
        otherKeys: PropertyListDictionary = .empty
    ) {
        self.key = key
        self.productName = productName
        self.resolutions = resolutions
        self.otherKeys = otherKeys
    }

    /// Reads an override file's contents.
    public init(key: OverrideKey, propertyList data: Data) throws {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard var dictionary = object as? [String: Any] else {
            throw ResoluteError.overrideUnreadable(path: key.relativePath, reason: "the file is not a dictionary")
        }
        var productName: String?
        if let name = dictionary[Self.productNameKey] as? String {
            productName = name.isEmpty ? nil : name
            dictionary.removeValue(forKey: Self.productNameKey)
        }
        var resolutions: [ScaleResolution] = []
        if let elements = dictionary[Self.resolutionsKey] as? [Any] {
            resolutions = ScaleResolutionCodec.decode(elements)
            dictionary.removeValue(forKey: Self.resolutionsKey)
        }
        self.init(key: key, productName: productName, resolutions: resolutions, otherKeys: PropertyListDictionary(dictionary))
    }

    /// The file contents, as an XML property list.
    public func propertyListData() throws -> Data {
        var dictionary = otherKeys.dictionary
        if let productName, !productName.isEmpty {
            dictionary[Self.productNameKey] = productName
        }
        let encoded = ScaleResolutionCodec.encode(resolutions)
        if !encoded.isEmpty {
            dictionary[Self.resolutionsKey] = encoded
            if dictionary[Self.targetPPMMKey] == nil {
                dictionary[Self.targetPPMMKey] = Self.defaultTargetPPMM
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
```

<!-- file: Sources/ResoluteKit/Overrides/OverrideStore.swift | task: 6 | kind: impl -->
```swift
import Foundation

/// Where override files and their backups live.
public struct OverrideLocations: Hashable, Sendable {
    /// Overrides Resolute writes.
    public var userRoot: URL
    /// Overrides that ship with macOS (read only).
    public var systemRoot: URL
    /// Copies of the files Resolute replaced or removed.
    public var backupRoot: URL

    public init(userRoot: URL, systemRoot: URL, backupRoot: URL) {
        self.userRoot = userRoot
        self.systemRoot = systemRoot
        self.backupRoot = backupRoot
    }

    public static let standard = OverrideLocations(
        userRoot: URL(filePath: "/Library/Displays/Contents/Resources/Overrides", directoryHint: .isDirectory),
        systemRoot: URL(filePath: "/System/Library/Displays/Contents/Resources/Overrides", directoryHint: .isDirectory),
        backupRoot: URL(filePath: "/Library/Application Support/Resolute/Backups", directoryHint: .isDirectory)
    )

    /// Every location inside `root`, for staging and tests.
    public static func staged(at root: URL) -> OverrideLocations {
        OverrideLocations(
            userRoot: root.appending(path: "Overrides", directoryHint: .isDirectory),
            systemRoot: root.appending(path: "System", directoryHint: .isDirectory),
            backupRoot: root.appending(path: "Backups", directoryHint: .isDirectory)
        )
    }

    public func userFile(for key: OverrideKey) -> URL {
        file(for: key, in: userRoot)
    }

    public func systemFile(for key: OverrideKey) -> URL {
        file(for: key, in: systemRoot)
    }

    private func file(for key: OverrideKey, in root: URL) -> URL {
        root.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
            .appending(path: key.productFileName, directoryHint: .notDirectory)
    }
}

/// Reads override files.
public struct OverrideStore: Sendable {
    /// Where an editable override came from.
    public enum Source: Hashable, Sendable {
        /// A file under the user root (written by Resolute, RDM or another tool).
        case installed
        /// The file macOS ships for this display.
        case system
        /// No file exists yet.
        case missing
    }

    public var locations: OverrideLocations

    public init(locations: OverrideLocations = .standard) {
        self.locations = locations
    }

    public func installedOverride(for key: OverrideKey) throws -> DisplayOverride? {
        try read(locations.userFile(for: key), key: key)
    }

    public func systemOverride(for key: OverrideKey) throws -> DisplayOverride? {
        try read(locations.systemFile(for: key), key: key)
    }

    /// What editing starts from: the installed override, else Apple's file, else nothing.
    public func editableOverride(for key: OverrideKey) throws -> (override: DisplayOverride, source: Source) {
        if let installed = try installedOverride(for: key) { return (installed, .installed) }
        if let system = try systemOverride(for: key) { return (system, .system) }
        return (DisplayOverride(key: key), .missing)
    }

    /// Displays with an override under the user root.
    public func installedKeys() -> [OverrideKey] {
        let fileManager = FileManager.default
        guard let vendors = try? fileManager.contentsOfDirectory(atPath: locations.userRoot.path(percentEncoded: false)) else {
            return []
        }
        var keys: [OverrideKey] = []
        for vendor in vendors {
            let directory = locations.userRoot.appending(path: vendor, directoryHint: .isDirectory)
            let products = (try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            keys += products.compactMap { OverrideKey(vendorDirectory: vendor, productFile: $0) }
        }
        return keys.sorted()
    }

    private func read(_ url: URL, key: OverrideKey) throws -> DisplayOverride? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try DisplayOverride(key: key, propertyList: Data(contentsOf: url))
        } catch ResoluteError.overrideUnreadable(_, let reason) {
            throw ResoluteError.overrideUnreadable(path: path, reason: reason)
        } catch {
            throw ResoluteError.overrideUnreadable(path: path, reason: "it is not a valid property list")
        }
    }
}
```

<!-- file: Sources/ResoluteKit/Model/AspectRatio.swift | task: 6 | kind: impl -->
```swift
import Foundation

/// A width:height ratio in its conventional reduced form.
public struct AspectRatio: Hashable, Sendable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        guard width > 0, height > 0 else {
            self.width = 0
            self.height = 0
            return
        }
        let divisor = Self.greatestCommonDivisor(width, height)
        var reduced = (width / divisor, height / divisor)
        // Screens are sold as 16:10 and 21:9, not 8:5 and 7:3.
        if reduced == (8, 5) { reduced = (16, 10) }
        if reduced == (7, 3) { reduced = (21, 9) }
        self.width = reduced.0
        self.height = reduced.1
    }

    /// Common ratios offered by the resolution editor.
    public static let presets: [AspectRatio] = [(16, 9), (16, 10), (21, 9), (32, 9), (64, 27), (4, 3), (3, 2)]
        .map { AspectRatio(width: $0.0, height: $0.1) }

    public var value: Double {
        height > 0 ? Double(width) / Double(height) : 0
    }

    /// "16:9", or "1.55:1" when the reduced numbers are unwieldy.
    public var description: String {
        guard width > 0 else { return "—" }
        if width <= 64 && height <= 64 { return "\(width):\(height)" }
        return String(format: "%.2f:1", value)
    }

    /// The height that gives this ratio at `width`.
    public func height(forWidth width: Int) -> Int {
        guard value > 0 else { return 0 }
        return Int((Double(width) / value).rounded())
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ScaleResolutionCodecTests|DisplayOverrideTests|OverrideStoreTests|AspectRatioTests"`
Expected: all pass.

Also check the real file on this Mac decodes: `swift test --filter decodesTheRDMOverride` passes against the embedded copy, which is byte-identical to `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-db4/DisplayProductID-3401`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/Overrides Sources/ResoluteKit/Model/AspectRatio.swift Tests/ResoluteKitTests
git commit -m "Read and write display override files without losing unknown entries"
```

---

### Task 7: Installing overrides — command runners, installer, editing drafts

**Files:**
- Create: `Sources/ResoluteKit/Overrides/CommandRunning.swift`, `Sources/ResoluteKit/Overrides/OverrideInstaller.swift`, `Sources/ResoluteKit/Overrides/OverrideDraft.swift`
- Test: `Tests/ResoluteKitTests/OverrideInstallerTests.swift`

**Interfaces:**
- Consumes: `DisplayOverride`, `OverrideKey`, `OverrideLocations`, `OverrideStore`, `ScaleResolution`, `HiDPIFlags` (Task 6); `ResoluteError` (Task 1).
- Produces: protocol `CommandRunning` (`run(_ script: String) async throws`); `ShellCommandRunner()`; `AdminCommandRunner()` (user cancel → `ResoluteError.cancelled`); `Shell.quote(_:)`; `AppleScript.doShellScript(_:withAdministratorPrivileges:)`; `Subprocess.run(_:arguments:) throws`; `OverrideInstaller(locations:runner:now:)` with `install(_:) async throws -> URL`, `remove(_:) async throws`, static `installScript(staging:destination:backup:)`, `removeScript(destination:backup:)`, `timestamp(_:)`; `OverrideDraft(_:)` with `saved`, `working`, `hasChanges`, `add(_:) throws`, `remove(atOffsets:)`, `revert()`, `markSaved()`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/ResoluteKitTests/OverrideInstallerTests.swift | task: 7 | kind: test -->
```swift
import Foundation
import Testing
@testable import ResoluteKit

@Suite struct OverrideInstallerTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)
    let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    func installer(at root: URL) -> OverrideInstaller {
        let date = fixedDate
        return OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner(), now: { date })
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func handlesPathsWithQuotesAndSpaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let override = DisplayOverride(key: key, resolutions: [.hiDPI(width: 2560, height: 1080, flags: .standard)])
        let url = try await installer.install(override)
        #expect(url == installer.locations.userFile(for: key))
        let stored = try OverrideStore(locations: installer.locations).installedOverride(for: key)
        #expect(stored?.resolutions == override.resolutions)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
    }

    @Test func backsUpTheFileItReplaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        let backup = installer.backupFile(for: key)
        #expect(!exists(backup))
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        #expect(exists(backup))
        let saved = try DisplayOverride(key: key, propertyList: Data(contentsOf: backup))
        #expect(saved.resolutions == [.standard(width: 1920, height: 1080)])
        #expect(backup.lastPathComponent == "DisplayProductID-3401-20260921-141320.plist")
    }

    @Test func removesTheOverrideAndItsEmptyFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let url = try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        try await installer.remove(key)
        #expect(!exists(url))
        #expect(!exists(url.deletingLastPathComponent()))
        #expect(exists(installer.backupFile(for: key)))
    }

    @Test func removingAMissingOverrideSucceeds() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await installer(at: root).remove(key)
    }

    @Test func reportsFailuresFromTheScript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        // A file where the vendor folder belongs makes the script fail.
        try FileManager.default.createDirectory(at: installer.locations.userRoot, withIntermediateDirectories: true)
        try Data().write(to: installer.locations.userRoot.appending(path: key.vendorDirectoryName))
        await #expect(throws: ResoluteError.self) {
            try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        }
    }

    @Test func buildsTheScriptItDescribes() {
        let script = OverrideInstaller.installScript(
            staging: URL(filePath: "/tmp/a b.plist"),
            destination: URL(filePath: "/L/DisplayVendorID-1/DisplayProductID-2"),
            backup: URL(filePath: "/B/DisplayVendorID-1/DisplayProductID-2-x.plist")
        )
        #expect(script == "set -e; "
            + "if [ -f '/L/DisplayVendorID-1/DisplayProductID-2' ]; then mkdir -p '/B/DisplayVendorID-1/'; "
            + "cp -p '/L/DisplayVendorID-1/DisplayProductID-2' '/B/DisplayVendorID-1/DisplayProductID-2-x.plist'; fi; "
            + "mkdir -p '/L/DisplayVendorID-1/'; "
            + "cp '/tmp/a b.plist' '/L/DisplayVendorID-1/DisplayProductID-2'; "
            + "chmod 644 '/L/DisplayVendorID-1/DisplayProductID-2'")
        #expect(OverrideInstaller.timestamp(fixedDate) == "20260921-141320")
    }
}

@Suite struct QuotingTests {
    @Test func quotesForTheShell() {
        #expect(Shell.quote("it's here") == #"'it'\''s here'"#)
    }

    @Test func escapesForAppleScript() {
        #expect(AppleScript.doShellScript(#"echo "hi" \ there"#, withAdministratorPrivileges: true)
            == #"do shell script "echo \"hi\" \\ there" with administrator privileges"#)
        #expect(AppleScript.doShellScript("ls", withAdministratorPrivileges: false) == #"do shell script "ls""#)
    }

    @Test func survivesARealAppleScriptRoundTrip() throws {
        // Runs osascript without administrator rights, so no password prompt appears.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appending(path: #"it's "done""#)
        let script = "touch \(Shell.quote(marker.path(percentEncoded: false)))"
        try Subprocess.run("/usr/bin/osascript", arguments: ["-e", AppleScript.doShellScript(script, withAdministratorPrivileges: false)])
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

@Suite struct OverrideDraftTests {
    let key = OverrideKey(vendorID: 1, productID: 2)

    @Test func tracksChangesAndReverts() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        #expect(!draft.hasChanges)
        try draft.add(.hiDPI(width: 1600, height: 900, flags: .standard))
        #expect(draft.hasChanges)
        draft.revert()
        #expect(!draft.hasChanges)
        #expect(draft.working.resolutions.isEmpty)
        try draft.add(.standard(width: 2560, height: 1080))
        draft.markSaved()
        #expect(!draft.hasChanges)
        #expect(draft.saved.resolutions.count == 1)
    }

    @Test func rejectsDuplicatesAndNonsense() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.hiDPI(width: 1600, height: 900, flags: .standard)]))
        #expect(throws: ResoluteError.invalidEntry("1600 × 900 (HiDPI) is already in the list.")) {
            try draft.add(.hiDPI(width: 1600, height: 900, flags: HiDPIFlags(primary: 1, secondary: 0)))
        }
        #expect(throws: ResoluteError.self) { try draft.add(.hiDPI(width: 9_000, height: 900, flags: .standard)) }
        #expect(throws: ResoluteError.self) { try draft.add(.standard(width: 100, height: 100)) }
        #expect(throws: ResoluteError.invalidEntry("HiDPI flags need bit 0 of the first word set.")) {
            try draft.add(.hiDPI(width: 1280, height: 720, flags: HiDPIFlags(primary: 8, secondary: 0)))
        }
        try draft.add(.standard(width: 1600, height: 900))  // same size at 1× is a different mode
        #expect(draft.working.resolutions.count == 2)
    }

    @Test func removesByOffsets() {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [
            .standard(width: 1920, height: 1080), .standard(width: 2560, height: 1440), .standard(width: 3840, height: 2160),
        ]))
        draft.remove(atOffsets: IndexSet([0, 2, 7]))
        #expect(draft.working.resolutions == [.standard(width: 2560, height: 1440)])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "OverrideInstallerTests|QuotingTests|OverrideDraftTests"`
Expected: build failure — `cannot find 'OverrideInstaller' in scope`.

- [ ] **Step 3: Write the implementation**

<!-- file: Sources/ResoluteKit/Overrides/CommandRunning.swift | task: 7 | kind: impl -->
```swift
import Foundation

/// Runs a shell script, possibly with administrator rights.
public protocol CommandRunning: Sendable {
    func run(_ script: String) async throws
}

/// Runs scripts with `/bin/sh` as the current user (or as root under `sudo`).
public struct ShellCommandRunner: CommandRunning {
    public init() {}

    public func run(_ script: String) async throws {
        try await Task.detached {
            try Subprocess.run("/bin/sh", arguments: ["-c", script])
        }.value
    }
}

/// Runs scripts as root after macOS asks for an administrator's password.
public struct AdminCommandRunner: CommandRunning {
    public init() {}

    public func run(_ script: String) async throws {
        let source = AppleScript.doShellScript(script, withAdministratorPrivileges: true)
        do {
            try await Task.detached {
                try Subprocess.run("/usr/bin/osascript", arguments: ["-e", source])
            }.value
        } catch ResoluteError.commandFailed(_, let message) where message.contains("-128") {
            // "User canceled. (-128)"
            throw ResoluteError.cancelled
        }
    }
}

/// Quoting for `/bin/sh`.
public enum Shell {
    /// Wraps `text` in single quotes, escaping any single quotes inside it.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// Building AppleScript source.
public enum AppleScript {
    /// A `do shell script` statement that runs `script`.
    public static func doShellScript(_ script: String, withAdministratorPrivileges: Bool) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\"" + (withAdministratorPrivileges ? " with administrator privileges" : "")
    }
}

/// Runs a program and waits for it.
enum Subprocess {
    /// Throws `ResoluteError.commandFailed` with the program's error output when it fails.
    static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let errorOutput = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ResoluteError.commandFailed(status: process.terminationStatus, message: message)
        }
    }
}
```

<!-- file: Sources/ResoluteKit/Overrides/OverrideInstaller.swift | task: 7 | kind: impl -->
```swift
import Foundation

/// Writes and removes override files through a `CommandRunning`, backing up what it replaces.
public struct OverrideInstaller: Sendable {
    public var locations: OverrideLocations
    public var runner: any CommandRunning
    public var now: @Sendable () -> Date

    public init(
        locations: OverrideLocations = .standard,
        runner: any CommandRunning,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locations = locations
        self.runner = runner
        self.now = now
    }

    /// Writes `override` to its file and returns the file's location.
    @discardableResult
    public func install(_ override: DisplayOverride) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appending(path: "Resolute-\(UUID().uuidString).plist")
        try override.propertyListData().write(to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let destination = locations.userFile(for: override.key)
        try await runner.run(Self.installScript(
            staging: staging, destination: destination, backup: backupFile(for: override.key)
        ))
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey) async throws {
        try await runner.run(Self.removeScript(destination: locations.userFile(for: key), backup: backupFile(for: key)))
    }

    func backupFile(for key: OverrideKey) -> URL {
        locations.backupRoot
            .appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
            .appending(path: "\(key.productFileName)-\(Self.timestamp(now())).plist")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func installScript(staging: URL, destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        return [
            "set -e",
            backupCommand(file: file, backup: backup),
            "mkdir -p \(Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false)))",
            "cp \(Shell.quote(staging.path(percentEncoded: false))) \(file)",
            "chmod 644 \(file)",
        ].joined(separator: "; ")
    }

    static func removeScript(destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return [
            "set -e",
            backupCommand(file: file, backup: backup),
            "rm -f \(file)",
            "rmdir \(folder) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    private static func backupCommand(file: String, backup: URL) -> String {
        let folder = Shell.quote(backup.deletingLastPathComponent().path(percentEncoded: false))
        return "if [ -f \(file) ]; then mkdir -p \(folder); cp -p \(file) \(Shell.quote(backup.path(percentEncoded: false))); fi"
    }
}
```

<!-- file: Sources/ResoluteKit/Overrides/OverrideDraft.swift | task: 7 | kind: impl -->
```swift
import Foundation

/// An override being edited: the saved version and the working copy.
public struct OverrideDraft: Equatable, Sendable {
    public private(set) var saved: DisplayOverride
    public var working: DisplayOverride

    public init(_ override: DisplayOverride) {
        saved = override
        working = override
    }

    public var hasChanges: Bool { working != saved }

    /// Adds an entry after checking it is sensible and not already listed.
    public mutating func add(_ entry: ScaleResolution) throws {
        try Self.validate(entry)
        if working.resolutions.contains(where: { $0.sameMode(as: entry) }) {
            throw ResoluteError.invalidEntry("\(entry.sizeText) (\(entry.kindText)) is already in the list.")
        }
        working.resolutions.append(entry)
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where working.resolutions.indices.contains(index) {
            working.resolutions.remove(at: index)
        }
    }

    public mutating func revert() {
        working = saved
    }

    public mutating func markSaved() {
        saved = working
    }

    /// The largest pixel size Resolute writes to an override.
    static let maximumPixels = 16_384

    static func validate(_ entry: ScaleResolution) throws {
        switch entry {
        case .hiDPI(let width, let height, let flags):
            guard width >= 320, height >= 200, width * 2 <= maximumPixels, height * 2 <= maximumPixels else {
                throw ResoluteError.invalidEntry("HiDPI resolutions must be between 320 × 200 and 8192 × 8192.")
            }
            guard flags.primary & HiDPIFlags.hiDPIBit != 0 else {
                throw ResoluteError.invalidEntry("HiDPI flags need bit 0 of the first word set.")
            }
        case .standard(let width, let height):
            guard width >= 320, height >= 200, width <= maximumPixels, height <= maximumPixels else {
                throw ResoluteError.invalidEntry("Resolutions must be between 320 × 200 and 16384 × 16384.")
            }
        case .preserved:
            throw ResoluteError.invalidEntry("Only HiDPI and 1× resolutions can be added.")
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "OverrideInstallerTests|QuotingTests|OverrideDraftTests"`
Expected: all pass (the osascript test runs without a password prompt).

- [ ] **Step 5: Commit**

```bash
git add Sources/ResoluteKit/Overrides Tests/ResoluteKitTests/OverrideInstallerTests.swift
git commit -m "Install and remove override files with backups through a pluggable command runner"
```

---
### Task 8: The `resolute` command-line tool

**Files:**
- Modify: `Package.swift` (add swift-argument-parser and the `resolute` target)
- Create: `Sources/resolute/ResoluteCommand.swift`, `Sources/resolute/Output.swift`, `Sources/resolute/DisplaysCommand.swift`, `Sources/resolute/ModesCommand.swift`, `Sources/resolute/SetCommand.swift`, `Sources/resolute/MirrorCommand.swift`, `Sources/resolute/OverridesCommand.swift`
- Test: end-to-end runs of the built binary (Step 4); the logic it calls is unit-tested in Tasks 1–7.

**Interfaces:**
- Consumes: `SystemDisplayService`, `DisplaySelector`, `ModeQuery`, `ModeCatalog`, `RefreshRate`, `OverrideStore`, `OverrideLocations`, `OverrideInstaller`, `ShellCommandRunner`, `OverrideDraft`, `HiDPIFlags`, `ScaleResolution`, `ResoluteVersion`, `ResoluteError`.
- Produces: the `resolute` executable with subcommands `displays` (default), `modes`, `set`, `mirror`, `overrides list|show|add|remove|reset`.

- [ ] **Step 1: Add the dependency and target**

<!-- file: Package.swift | task: 8 | kind: impl -->
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Resolute",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResoluteKit", targets: ["ResoluteKit"]),
        .executable(name: "resolute", targets: ["resolute"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ResoluteKit"),
        .executableTarget(
            name: "resolute",
            dependencies: [
                "ResoluteKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Write the commands**

<!-- file: Sources/resolute/ResoluteCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import ResoluteKit

@main
struct ResoluteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolute",
        abstract: "List and switch display modes, including the ones macOS hides.",
        version: ResoluteVersion.string,
        subcommands: [
            DisplaysCommand.self, ModesCommand.self, SetCommand.self, MirrorCommand.self, OverridesCommand.self,
        ],
        defaultSubcommand: DisplaysCommand.self
    )
}

/// Chooses a display.
struct DisplayOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "main, an index from `resolute displays`, id:<number>, or part of the display's name.")
    var display = "main"

    func resolve(in displays: [Display]) throws -> Display {
        try DisplaySelector(display).resolve(in: displays)
    }
}
```

<!-- file: Sources/resolute/Output.swift | task: 8 | kind: impl -->
```swift
import Foundation
import ResoluteKit

/// Text and JSON formatting shared by the commands.
enum Output {
    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// "1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54"
    static func describe(_ mode: DisplayMode) -> String {
        var text = mode.sizeText
        if mode.isHiDPI { text += " HiDPI (\(mode.pixelSizeText) px)" }
        let rate = RefreshRate.format(mode.refreshRate)
        if !rate.isEmpty { text += " @ \(rate)" }
        text += ", mode \(mode.modeID)"
        if mode.origin == .hidden { text += ", hidden" }
        return text
    }

    /// Left-aligned columns separated by two spaces.
    static func table(_ rows: [[String]], indent: String = "") -> String {
        var widths: [Int] = []
        for row in rows {
            for (column, cell) in row.enumerated() {
                if column < widths.count {
                    widths[column] = max(widths[column], cell.count)
                } else {
                    widths.append(cell.count)
                }
            }
        }
        return rows.map { row in
            var line = indent
            for (column, cell) in row.enumerated() {
                line += cell
                if column < row.count - 1 {
                    line += String(repeating: " ", count: widths[column] - cell.count + 2)
                }
            }
            while line.hasSuffix(" ") { line.removeLast() }
            return line
        }.joined(separator: "\n")
    }

    static func hex(_ value: UInt32) -> String {
        String(value, radix: 16)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
```

<!-- file: Sources/resolute/DisplaysCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import ResoluteKit

struct DisplaysCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List online displays and their current modes."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let displays = SystemDisplayService().displays()
        guard !displays.isEmpty else { throw ResoluteError.noDisplays }
        if json {
            print(try Output.json(displays.enumerated().map { DisplaySummary(index: $0.offset, display: $0.element) }))
            return
        }
        for (index, display) in displays.enumerated() {
            var traits = ["id \(display.id)", "vendor \(Output.hex(display.vendorID))", "product \(Output.hex(display.productID))"]
            if display.isMain { traits.append("main") }
            if display.isBuiltin { traits.append("built-in") }
            if display.isInMirrorSet { traits.append("mirrored") }
            print("\(index)  \(display.name)  (\(traits.joined(separator: ", ")))")
            print("   " + (display.currentMode.map(Output.describe) ?? "current mode unknown"))
        }
    }
}

/// A display without its full mode list, for `displays --json`.
struct DisplaySummary: Encodable {
    let index: Int
    let id: UInt32
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let isMain: Bool
    let isBuiltin: Bool
    let isInMirrorSet: Bool
    let currentMode: DisplayMode?
    let modeCount: Int
    let hiddenModeCount: Int
    let hiddenModes: String

    init(index: Int, display: Display) {
        self.index = index
        id = display.id
        name = display.name
        vendorID = display.vendorID
        productID = display.productID
        serialNumber = display.serialNumber
        isMain = display.isMain
        isBuiltin = display.isBuiltin
        isInMirrorSet = display.isInMirrorSet
        currentMode = display.currentMode
        modeCount = display.modes.count
        hiddenModeCount = display.hiddenModeCount
        switch display.privateModes {
        case .trusted: hiddenModes = "available"
        case .unavailable: hiddenModes = "unavailable"
        case .untrusted(let reason): hiddenModes = "ignored: \(reason)"
        }
    }
}
```

<!-- file: Sources/resolute/ModesCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import ResoluteKit

struct ModesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modes",
        abstract: "List a display's modes.",
        discussion: "Resolutions are grouped with their refresh rates; * marks the current mode."
    )

    @OptionGroup var target: DisplayOptions

    @Flag(help: "Include hidden modes that only the private SkyLight API lists.")
    var all = false

    @Flag(help: "One line per mode, with mode IDs and flags.")
    var raw = false

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let display = try target.resolve(in: SystemDisplayService().displays())
        let modes = display.modes.filter { all || $0.origin == .system }
        if json {
            print(try Output.json(modes))
            return
        }
        print("\(display.name): \(modes.count) modes\(Self.hiddenNote(for: display, all: all))")
        if raw {
            print(Self.rawTable(modes, currentModeID: display.currentModeID))
            return
        }
        let currentKey = ModeCatalog.currentKey(for: display)
        for section in ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: all) {
            print("  \(section.kind.title)")
            let rows = section.groups.map { group -> [String] in
                let isCurrent = group.key == currentKey
                let rates = group.refreshRates.filter { $0 > 0 }.map { rate -> String in
                    let number = RefreshRate.format(rate).replacingOccurrences(of: " Hz", with: "")
                    return isCurrent && RefreshRate.key(rate) == display.currentMode?.refreshKey ? number + "*" : number
                }
                var notes: [String] = []
                if group.isDefault { notes.append("default") }
                if group.isNative { notes.append("native") }
                return [
                    isCurrent ? "*" : " ",
                    group.sizeText,
                    group.isHiDPI ? "\(group.pixelSizeText) px" : "",
                    rates.isEmpty ? "" : rates.joined(separator: ", ") + " Hz",
                    notes.joined(separator: ", "),
                ]
            }
            print(Output.table(rows, indent: "  "))
        }
    }

    static func hiddenNote(for display: Display, all: Bool) -> String {
        switch display.privateModes {
        case .trusted:
            display.hiddenModeCount > 0 && !all ? " (+\(display.hiddenModeCount) hidden; add --all)" : ""
        case .untrusted(let reason):
            all ? " (hidden modes ignored: \(reason))" : ""
        case .unavailable:
            all ? " (hidden modes are unavailable on this system)" : ""
        }
    }

    static func rawTable(_ modes: [DisplayMode], currentModeID: Int32?) -> String {
        let sorted = modes.sorted {
            ($0.width, $0.height, $0.pixelWidth, $0.refreshKey) > ($1.width, $1.height, $1.pixelWidth, $1.refreshKey)
        }
        return Output.table(sorted.map { mode in
            [
                mode.modeID == currentModeID ? "*" : " ",
                "\(mode.modeID)",
                mode.sizeText,
                "\(mode.pixelSizeText) px",
                String(format: "%gx", mode.scale),
                RefreshRate.format(mode.refreshRate),
                mode.bitsPerSample.map { "\($0)-bit" } ?? "",
                String(format: "0x%08x", mode.ioFlags),
                mode.origin == .hidden ? "hidden" : "",
            ]
        }, indent: "  ")
    }
}
```

<!-- file: Sources/resolute/SetCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import ResoluteKit

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Switch a display to another mode.",
        discussion: """
            Examples:
              resolute set 1512x982          keep the refresh rate, pick the resolution
              resolute set 1920x1200@1x      a low-resolution (1×) mode
              resolute set --refresh 60      keep the resolution, change the refresh rate
              resolute set --mode-id 55      an exact mode from `resolute modes --raw`
              resolute set --default         the display's default mode
            """
    )

    @Argument(help: "WIDTHxHEIGHT in points, optionally followed by @2x or @1x and @<Hz>.")
    var resolution: String?

    @OptionGroup var target: DisplayOptions

    @Option(help: "2 for HiDPI, 1 for low resolution.")
    var scale: Double?

    @Option(help: "Refresh rate in Hz.")
    var refresh: Double?

    @Option(name: .customLong("mode-id"), help: "An exact mode ID.")
    var modeID: Int32?

    @Flag(name: .customLong("default"), help: "Switch to the display's default mode.")
    var useDefault = false

    @Flag(help: "Change the mode until you log out instead of permanently.")
    var session = false

    @Flag(help: "Allow hidden modes that macOS does not list.")
    var allowHidden = false

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    func validate() throws {
        if resolution == nil && scale == nil && refresh == nil && modeID == nil && !useDefault {
            throw ValidationError("Give a resolution, --refresh, --scale, --mode-id or --default.")
        }
    }

    func run() throws {
        let service = SystemDisplayService()
        let display = try target.resolve(in: service.displays())
        var query = try resolution.map { try ModeQuery(resolution: $0) } ?? ModeQuery()
        if let scale { query.scale = scale }
        if let refresh { query.refreshRate = refresh }
        query.modeID = modeID
        query.useDefault = useDefault
        query.allowHidden = allowHidden

        let mode = try query.resolve(on: display)
        guard mode.modeID != display.currentModeID else {
            print("\(display.name) is already at \(Output.describe(mode)).")
            return
        }
        guard !dryRun else {
            print("Would switch \(display.name) to \(Output.describe(mode)).")
            return
        }
        try service.apply(modeID: mode.modeID, to: display.id, scope: session ? .session : .permanent)
        if service.currentModeID(of: display.id) == mode.modeID {
            print("\(display.name): \(Output.describe(mode))")
        } else {
            Output.printError("warning: macOS accepted the change but reports a different mode now.")
        }
    }
}
```

<!-- file: Sources/resolute/MirrorCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import ResoluteKit

struct MirrorCommand: ParsableCommand {
    enum State: String, ExpressibleByArgument, CaseIterable {
        case on, off, toggle, status
    }

    static let configuration = CommandConfiguration(
        commandName: "mirror",
        abstract: "Mirror every display to the main display, or stop mirroring."
    )

    @Argument(help: "on, off, toggle or status.")
    var state: State = .status

    func run() throws {
        let service = SystemDisplayService()
        let mirroring = service.displays().contains(where: \.isInMirrorSet)
        let enable: Bool
        switch state {
        case .status:
            print(mirroring ? "Mirroring is on." : "Mirroring is off.")
            return
        case .on: enable = true
        case .off: enable = false
        case .toggle: enable = !mirroring
        }
        try service.setMirroring(enable)
        print(enable ? "Mirroring is on." : "Mirroring is off.")
    }
}
```

<!-- file: Sources/resolute/OverridesCommand.swift | task: 8 | kind: impl -->
```swift
import ArgumentParser
import Foundation
import ResoluteKit

struct OverridesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overrides",
        abstract: "Inspect and edit custom resolutions in /Library/Displays.",
        discussion: """
            Changes apply after the display is reconnected or the Mac restarts.
            Commands that write need administrator rights: run them with sudo.
            """,
        subcommands: [ListOverrides.self, ShowOverride.self, AddResolution.self, RemoveResolution.self, ResetOverride.self],
        defaultSubcommand: ListOverrides.self
    )
}

/// Where overrides are read from and written to.
struct LocationOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Use this directory instead of /Library/Displays.", visibility: .hidden))
    var root: String?

    var locations: OverrideLocations {
        root.map { OverrideLocations.staged(at: URL(filePath: $0, directoryHint: .isDirectory)) } ?? .standard
    }

    func installer() throws -> OverrideInstaller {
        guard root != nil || geteuid() == 0 else { throw ResoluteError.needsRoot }
        return OverrideInstaller(locations: locations, runner: ShellCommandRunner())
    }
}

/// Which display's override to use.
struct OverrideTargetOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "A connected display: main, an index, id:<number>, or part of its name.")
    var display: String?

    @Option(help: "Vendor ID in hex, for a display that is not connected (for example db4).")
    var vendor: String?

    @Option(help: "Product ID in hex, for a display that is not connected (for example 3401).")
    var product: String?

    func validate() throws {
        if (vendor == nil) != (product == nil) {
            throw ValidationError("Pass both --vendor and --product.")
        }
        if display != nil && vendor != nil {
            throw ValidationError("Pass either --display or --vendor and --product.")
        }
    }

    func key() throws -> OverrideKey {
        if let vendor, let product {
            guard let vendorID = Self.hex(vendor), let productID = Self.hex(product) else {
                throw ValidationError("--vendor and --product take hexadecimal IDs, for example db4 and 3401.")
            }
            return OverrideKey(vendorID: vendorID, productID: productID)
        }
        let displays = SystemDisplayService().displays()
        return OverrideKey(display: try DisplaySelector(display ?? "main").resolve(in: displays))
    }

    private static func hex(_ text: String) -> UInt32? {
        UInt32(text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16)
    }
}

/// The resolution an `add` or `remove` command names.
struct EntryOptions: ParsableArguments {
    @Argument(help: "WIDTHxHEIGHT: points for HiDPI entries, pixels with --standard.")
    var resolution: String

    @Flag(help: "A 1× entry instead of a HiDPI one.")
    var standard = false

    func entry(flags: HiDPIFlags = .standard) throws -> ScaleResolution {
        let query = try ModeQuery(resolution: resolution)
        guard let width = query.width, let height = query.height else {
            throw ResoluteError.invalidResolution(resolution)
        }
        return standard ? .standard(width: width, height: height) : .hiDPI(width: width, height: height, flags: flags)
    }
}

struct ListOverrides: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed overrides.")

    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let store = OverrideStore(locations: location.locations)
        let displays = SystemDisplayService().displays()
        let summaries = store.installedKeys().map { key in
            OverrideSummary(key: key, store: store, display: displays.first { OverrideKey(display: $0) == key })
        }
        if json {
            print(try Output.json(summaries))
            return
        }
        guard !summaries.isEmpty else {
            print("No overrides in \(store.locations.userRoot.path(percentEncoded: false))")
            return
        }
        summaries.forEach { $0.printText() }
    }
}

struct ShowOverride: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show the override for a display (the installed one, else the one macOS ships)."
    )

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let key = try target.key()
        let store = OverrideStore(locations: location.locations)
        let (override, source) = try store.editableOverride(for: key)
        let display = SystemDisplayService().displays().first { OverrideKey(display: $0) == key }
        let summary = OverrideSummary(key: key, override: override, source: source, locations: store.locations, display: display)
        if json {
            print(try Output.json(summary))
        } else {
            summary.printText()
        }
    }
}

struct AddResolution: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a custom resolution to a display's override.")

    @OptionGroup var entry: EntryOptions

    @Option(help: "HiDPI flags as two hex words (default 00000009 00a00000).")
    var flags: String?

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        let installer = try location.installer()
        let key = try target.key()
        var draft = OverrideDraft(try OverrideStore(locations: location.locations).editableOverride(for: key).override)
        let newEntry = try entry.entry(flags: try flags.map { try HiDPIFlags(parsing: $0) } ?? .standard)
        try draft.add(newEntry)
        let url = try await installer.install(draft.working)
        print("Added \(newEntry.summary) to \(url.path(percentEncoded: false))")
        print("Reconnect the display or restart the Mac to use it.")
    }
}

struct RemoveResolution: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a custom resolution from a display's override.")

    @OptionGroup var entry: EntryOptions
    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        let installer = try location.installer()
        let key = try target.key()
        guard let installed = try OverrideStore(locations: location.locations).installedOverride(for: key) else {
            throw ResoluteError.invalidEntry("There is no installed override for \(key).")
        }
        let unwanted = try entry.entry()
        var draft = OverrideDraft(installed)
        let offsets = IndexSet(draft.working.resolutions.indices.filter { draft.working.resolutions[$0].sameMode(as: unwanted) })
        guard !offsets.isEmpty else {
            throw ResoluteError.invalidEntry("\(unwanted.sizeText) (\(unwanted.kindText)) is not in the override.")
        }
        draft.remove(atOffsets: offsets)
        let url = try await installer.install(draft.working)
        print("Removed \(unwanted.sizeText) (\(unwanted.kindText)) from \(url.path(percentEncoded: false))")
    }
}

struct ResetOverride: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Delete a display's override so macOS uses its default resolutions."
    )

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        let installer = try location.installer()
        let key = try target.key()
        try await installer.remove(key)
        print("Removed the override for \(key). Backups are in \(installer.locations.backupRoot.path(percentEncoded: false))")
    }
}

/// An override as `overrides list` and `overrides show` print it.
struct OverrideSummary: Encodable {
    struct Entry: Encodable {
        let kind: String
        let width: Int?
        let height: Int?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let flags: String?
        let summary: String

        init(_ entry: ScaleResolution) {
            switch entry {
            case .hiDPI(let width, let height, let flags):
                kind = "hidpi"
                self.width = width
                self.height = height
                pixelWidth = width * 2
                pixelHeight = height * 2
                self.flags = flags.description
            case .standard(let width, let height):
                kind = "standard"
                self.width = width
                self.height = height
                pixelWidth = width
                pixelHeight = height
                flags = nil
            case .preserved:
                kind = "preserved"
                width = nil
                height = nil
                pixelWidth = nil
                pixelHeight = nil
                flags = nil
            }
            summary = entry.summary
        }
    }

    let vendorID: String
    let productID: String
    let path: String
    let source: String
    let connectedDisplay: String?
    let productName: String?
    let entries: [Entry]
    let problem: String?

    init(key: OverrideKey, override: DisplayOverride, source: OverrideStore.Source, locations: OverrideLocations, display: Display?, problem: String? = nil) {
        vendorID = Output.hex(key.vendorID)
        productID = Output.hex(key.productID)
        switch source {
        case .installed:
            path = locations.userFile(for: key).path(percentEncoded: false)
            self.source = "installed"
        case .system:
            path = locations.systemFile(for: key).path(percentEncoded: false)
            self.source = "macOS"
        case .missing:
            path = locations.userFile(for: key).path(percentEncoded: false)
            self.source = "none"
        }
        connectedDisplay = display?.name
        productName = override.productName
        entries = override.resolutions.map(Entry.init)
        self.problem = problem
    }

    init(key: OverrideKey, store: OverrideStore, display: Display?) {
        do {
            let installed = try store.installedOverride(for: key)
            self.init(
                key: key, override: installed ?? DisplayOverride(key: key), source: installed == nil ? .missing : .installed,
                locations: store.locations, display: display
            )
        } catch {
            self.init(
                key: key, override: DisplayOverride(key: key), source: .installed, locations: store.locations,
                display: display, problem: error.localizedDescription
            )
        }
    }

    func printText() {
        print(path)
        let origin = switch source {
        case "installed": "installed"
        case "macOS": "shipped with macOS, not installed"
        default: "no override yet"
        }
        print("  vendor \(vendorID), product \(productID), \(connectedDisplay.map { "connected: \($0)" } ?? "not connected"), \(origin)")
        if let productName { print("  name: \(productName)") }
        if let problem { print("  problem: \(problem)") }
        if entries.isEmpty { print("  no custom resolutions") }
        for entry in entries { print("  • \(entry.summary)") }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build --product resolute 2>&1 | tail -3`
Expected: `Build complete!` with no warnings from `Sources/resolute`.

- [ ] **Step 4: Verify end to end**

```bash
B="$(swift build --show-bin-path)/resolute"
"$B" --version                                   # 0.1.0
"$B"                                             # lists the built-in display at 1728 × 1117 HiDPI @ 120 Hz, mode 54
"$B" displays --json | python3 -m json.tool >/dev/null && echo json-ok
"$B" modes                                       # HiDPI and Low Resolution (1×) sections, * on 1728 × 1117 and 120*
"$B" modes --raw | head -4
"$B" set 1728x1117 --dry-run                     # "… is already at …"
"$B" set --refresh 60 --dry-run                  # "Would switch … @ 60 Hz, mode 55."
"$B" set 1500x970; echo "exit $?"                # suggestions, exit 1
"$B" mirror                                      # "Mirroring is off."
"$B" overrides list                              # shows DisplayVendorID-db4/DisplayProductID-3401 with 2560 × 1080 HiDPI
"$B" overrides show --vendor db4 --product 3401
T="$(mktemp -d)"
"$B" overrides add 1920x1080 --vendor db4 --product 3401 --root "$T"
"$B" overrides show --vendor db4 --product 3401 --root "$T"
"$B" overrides remove 1920x1080 --vendor db4 --product 3401 --root "$T"
"$B" overrides reset --vendor db4 --product 3401 --root "$T" && find "$T" -type f
"$B" overrides add 1920x1080 --vendor db4 --product 3401; echo "exit $?"   # needs sudo, exit 1
```

Then the one live change (refresh rate only, session scope, restored immediately):

```bash
"$B" set --refresh 60 --session && "$B" set --refresh 120 --session && "$B"
```

Expected: both switches print the new mode; the final listing shows `@ 120 Hz, mode 54` again.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/resolute
git commit -m "Add the resolute command-line tool"
```

---
### Task 9: App target and the Custom Resolutions editor

**Files:**
- Modify: `Package.swift` (add the `ResoluteApp` executable)
- Create: `Sources/ResoluteApp/main.swift`, `Sources/ResoluteApp/Diagnostics.swift`, `Sources/ResoluteApp/CustomResolutions/CustomResolutionsModel.swift`, `Sources/ResoluteApp/CustomResolutions/CustomResolutionsView.swift`, `Sources/ResoluteApp/CustomResolutions/AddResolutionSheet.swift`, `Sources/ResoluteApp/CustomResolutions/CustomResolutionsWindowController.swift`, `Sources/ResoluteApp/CustomResolutions/EditorSnapshot.swift`
- Test: offscreen render of the editor with live data (Step 4); its logic (`OverrideDraft`, `OverrideStore`, `OverrideInstaller`) is unit-tested in Tasks 6–7.

**Interfaces:**
- Consumes: `DisplayControlling`, `SystemDisplayService`, `OverrideKey`, `OverrideStore`, `OverrideInstaller`, `AdminCommandRunner`, `CommandRunning`, `OverrideDraft`, `ScaleResolution`, `HiDPIFlags`, `AspectRatio`, `ResoluteVersion`, `ResoluteError`.
- Produces: `CustomResolutionsModel(service:store:installer:)` (`targets`, `selection`, `draft`, `source`, `rows`, `select(_:)`, `select(displayID:)`, `reloadTargets()`, `add(width:height:hiDPI:flags:) -> String?`, `remove(rows:)`, `revert()`, `save() async`, `removeOverride() async`, `revealInFinder()`); `CustomResolutionsView(model:)`; `CustomResolutionsWindowController(model:)` with `show(selecting:)`, `displaysDidChange()`; `Diagnostics.run(_ arguments:) -> Int32?` handling `--version` and `--render-editor <png>`.

- [ ] **Step 1: Add the app target**

<!-- file: Package.swift | task: 9 | kind: impl -->
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Resolute",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResoluteKit", targets: ["ResoluteKit"]),
        .executable(name: "resolute", targets: ["resolute"]),
        .executable(name: "ResoluteApp", targets: ["ResoluteApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ResoluteKit"),
        .executableTarget(
            name: "resolute",
            dependencies: [
                "ResoluteKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "ResoluteApp", dependencies: ["ResoluteKit"]),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Write the editor**

<!-- file: Sources/ResoluteApp/CustomResolutions/CustomResolutionsModel.swift | task: 9 | kind: impl -->
```swift
import AppKit
import Observation
import ResoluteKit

/// State behind the Custom Resolutions window.
@MainActor
@Observable
final class CustomResolutionsModel {
    /// A display that can have an override: a connected one, or one with an override file.
    struct Target: Identifiable, Hashable {
        var key: OverrideKey
        var name: String
        var isConnected: Bool
        var hasOverride: Bool

        var id: OverrideKey { key }

        var detail: String {
            let ids = "Vendor \(String(key.vendorID, radix: 16)) · Product \(String(key.productID, radix: 16))"
            return hasOverride ? "\(ids) · Custom" : ids
        }
    }

    /// A row in the resolutions table.
    struct Row: Identifiable, Hashable {
        var id: Int
        var entry: ScaleResolution

        var resolution: String { entry.sizeText }
        var kind: String { entry.kindText }
        var pixels: String { entry.pixelSize.map { "\($0.width) × \($0.height)" } ?? "—" }
        var aspectRatio: String {
            entry.pixelSize.map { AspectRatio(width: $0.width, height: $0.height).description } ?? "—"
        }
    }

    /// A message shown in an alert.
    struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
    }

    private(set) var targets: [Target] = []
    private(set) var selection: OverrideKey?
    private(set) var draft: OverrideDraft?
    private(set) var source: OverrideStore.Source = .missing
    private(set) var isWorking = false
    var notice: Notice?

    @ObservationIgnored private let service: any DisplayControlling
    @ObservationIgnored let store: OverrideStore
    @ObservationIgnored private let installer: OverrideInstaller

    init(
        service: any DisplayControlling,
        store: OverrideStore = OverrideStore(),
        installer: OverrideInstaller = OverrideInstaller(runner: AdminCommandRunner())
    ) {
        self.service = service
        self.store = store
        self.installer = installer
        reloadTargets()
    }

    var rows: [Row] {
        (draft?.working.resolutions ?? []).enumerated().map { Row(id: $0.offset, entry: $0.element) }
    }

    var selectedTarget: Target? {
        targets.first { $0.key == selection }
    }

    var hasChanges: Bool { draft?.hasChanges ?? false }

    var canSave: Bool { hasChanges && !isWorking }

    /// The name macOS shows for the display; empty keeps the display's own name.
    var productName: String {
        get { draft?.working.productName ?? "" }
        set { draft?.working.productName = newValue.isEmpty ? nil : newValue }
    }

    var sourceDescription: String {
        guard let selection else { return "" }
        switch source {
        case .installed:
            return "Custom override installed at \(store.locations.userFile(for: selection).path(percentEncoded: false))"
        case .system:
            return "macOS ships an override for this display. Saving creates your own copy of it."
        case .missing:
            return "No override yet: macOS uses the display's own list of resolutions."
        }
    }

    // MARK: - Targets

    func reloadTargets() {
        let installed = store.installedKeys()
        var seen = Set<OverrideKey>()
        var result: [Target] = []
        for display in service.displays() {
            let key = OverrideKey(display: display)
            guard seen.insert(key).inserted else { continue }
            result.append(Target(key: key, name: display.name, isConnected: true, hasOverride: installed.contains(key)))
        }
        for key in installed where seen.insert(key).inserted {
            let name = (try? store.installedOverride(for: key))?.productName
                ?? "Display \(String(key.vendorID, radix: 16)):\(String(key.productID, radix: 16))"
            result.append(Target(key: key, name: name, isConnected: false, hasOverride: true))
        }
        targets = result
        if let selection, result.contains(where: { $0.key == selection }) { return }
        select(result.first?.key)
    }

    func select(_ key: OverrideKey?) {
        guard key != selection || draft == nil else { return }
        selection = key
        load()
    }

    func select(displayID: CGDirectDisplayID?) {
        reloadTargets()
        guard let displayID, let display = service.displays().first(where: { $0.id == displayID }) else { return }
        select(OverrideKey(display: display))
    }

    private func load() {
        guard let selection else {
            draft = nil
            return
        }
        do {
            let (override, source) = try store.editableOverride(for: selection)
            draft = OverrideDraft(override)
            self.source = source
        } catch {
            draft = nil
            notice = Notice(title: "The override could not be read", detail: error.localizedDescription)
        }
    }

    // MARK: - Editing

    /// Adds an entry; returns a message when it is not valid.
    func add(width: Int, height: Int, hiDPI: Bool, flags: HiDPIFlags) -> String? {
        let entry: ScaleResolution = hiDPI
            ? .hiDPI(width: width, height: height, flags: flags)
            : .standard(width: width, height: height)
        do {
            try draft?.add(entry)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func remove(rows ids: Set<Int>) {
        draft?.remove(atOffsets: IndexSet(ids))
    }

    func revert() {
        draft?.revert()
    }

    func save() async {
        guard let draft, canSave else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await installer.install(draft.working)
            self.draft?.markSaved()
            source = .installed
            reloadTargets()
            notice = Notice(
                title: "Custom resolutions saved",
                detail: "Reconnect the display or restart your Mac to use them."
            )
        } catch let error as ResoluteError where error == .cancelled {
            return
        } catch {
            notice = Notice(title: "The override could not be saved", detail: error.localizedDescription)
        }
    }

    func removeOverride() async {
        guard let selection, source == .installed else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await installer.remove(selection)
            load()
            reloadTargets()
            notice = Notice(
                title: "Override removed",
                detail: "A backup is in \(store.locations.backupRoot.path(percentEncoded: false)). Reconnect the display or restart your Mac to go back to its default resolutions."
            )
        } catch let error as ResoluteError where error == .cancelled {
            return
        } catch {
            notice = Notice(title: "The override could not be removed", detail: error.localizedDescription)
        }
    }

    func revealInFinder() {
        guard let selection, source == .installed else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.locations.userFile(for: selection)])
    }
}
```

<!-- file: Sources/ResoluteApp/CustomResolutions/CustomResolutionsView.swift | task: 9 | kind: impl -->
```swift
import ResoluteKit
import SwiftUI

/// The Custom Resolutions window: displays on the left, their override on the right.
struct CustomResolutionsView: View {
    @Bindable var model: CustomResolutionsModel

    var body: some View {
        NavigationSplitView {
            TargetList(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if model.draft != nil {
                OverrideEditor(model: model)
            } else {
                ContentUnavailableView(
                    "No Display Selected",
                    systemImage: "display",
                    description: Text("Choose a display to edit its custom resolutions.")
                )
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .alert(
            model.notice?.title ?? "",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            presenting: model.notice
        ) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.detail)
        }
    }
}

private struct TargetList: View {
    @Bindable var model: CustomResolutionsModel

    var body: some View {
        let connected = model.targets.filter(\.isConnected)
        let others = model.targets.filter { !$0.isConnected }
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            Section("Connected") {
                ForEach(connected) { target in
                    TargetRow(target: target).tag(target.key)
                }
            }
            if !others.isEmpty {
                Section("Other Overrides") {
                    ForEach(others) { target in
                        TargetRow(target: target).tag(target.key)
                    }
                }
            }
        }
    }
}

private struct TargetRow: View {
    let target: CustomResolutionsModel.Target

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).lineLimit(1)
                Text(target.detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "display")
                .foregroundStyle(target.isConnected ? .primary : .secondary)
        }
    }
}

private struct OverrideEditor: View {
    @Bindable var model: CustomResolutionsModel
    @State private var tableSelection = Set<Int>()
    @State private var isAdding = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedTarget?.name ?? "Display")
                    .font(.title2.weight(.semibold))
                Text(model.sourceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent("Name shown by macOS") {
                TextField("Name shown by macOS", text: $model.productName, prompt: Text("The display's own name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            Table(model.rows, selection: $tableSelection) {
                TableColumn("Resolution") { row in Text(row.resolution).monospacedDigit() }
                TableColumn("Type") { row in Text(row.kind) }
                    .width(min: 60, ideal: 80)
                TableColumn("Rendered At") { row in
                    Text(row.pixels).monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("Aspect Ratio") { row in Text(row.aspectRatio).foregroundStyle(.secondary) }
                    .width(min: 70, ideal: 90)
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(
                        "No Custom Resolutions",
                        systemImage: "rectangle.dashed",
                        description: Text("Add a resolution to create an override for this display.")
                    )
                }
            }

            HStack(spacing: 8) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Resolution", systemImage: "plus")
                }
                Button {
                    model.remove(rows: tableSelection)
                    tableSelection.removeAll()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(tableSelection.isEmpty)
                Spacer()
            }

            Label(
                "Changes apply after you reconnect the display or restart your Mac. On Apple silicon Macs, macOS may ignore custom scaled resolutions for some displays.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.source == .installed {
                    Button("Remove Override…", role: .destructive) { isConfirmingRemoval = true }
                    Button("Show in Finder") { model.revealInFinder() }
                }
                Spacer()
                if model.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Revert") { model.revert() }
                    .disabled(!model.hasChanges || model.isWorking)
                Button("Save…") { Task { await model.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .sheet(isPresented: $isAdding) {
            AddResolutionSheet(model: model)
        }
        .confirmationDialog("Remove the custom override for this display?", isPresented: $isConfirmingRemoval) {
            Button("Remove Override", role: .destructive) { Task { await model.removeOverride() } }
        } message: {
            Text("macOS goes back to the display's default resolutions after you reconnect it or restart. A backup is kept.")
        }
        .onChange(of: model.selection) {
            tableSelection.removeAll()
        }
    }
}
```

<!-- file: Sources/ResoluteApp/CustomResolutions/AddResolutionSheet.swift | task: 9 | kind: impl -->
```swift
import ResoluteKit
import SwiftUI

/// Asks for a new custom resolution.
struct AddResolutionSheet: View {
    @Bindable var model: CustomResolutionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var width = 1920
    @State private var height = 1080
    @State private var hiDPI = true
    @State private var ratio: AspectRatio?
    @State private var flagsText = HiDPIFlags.standard.description
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Width", value: $width, format: .number.grouping(.never))
                    TextField("Height", value: $height, format: .number.grouping(.never))
                        .disabled(ratio != nil)
                    Picker("Aspect ratio", selection: $ratio) {
                        Text("Free").tag(AspectRatio?.none)
                        ForEach(AspectRatio.presets, id: \.self) { preset in
                            Text(preset.description).tag(AspectRatio?.some(preset))
                        }
                    }
                    Toggle("HiDPI (Retina)", isOn: $hiDPI)
                } header: {
                    Text("Add a Resolution")
                } footer: {
                    Text(explanation).foregroundStyle(.secondary)
                }
                if hiDPI {
                    Section("Advanced") {
                        TextField("Flags", text: $flagsText).monospaced()
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .onChange(of: width) { applyRatio() }
        .onChange(of: ratio) { applyRatio() }
    }

    private var explanation: String {
        hiDPI
            ? "Looks like \(width) × \(height). macOS renders \(width * 2) × \(height * 2) pixels and scales them to the panel."
            : "\(width) × \(height) pixels, drawn at 1×."
    }

    private func applyRatio() {
        if let ratio { height = ratio.height(forWidth: width) }
    }

    private func add() {
        do {
            let flags = try HiDPIFlags(parsing: flagsText)
            if let message = model.add(width: width, height: height, hiDPI: hiDPI, flags: flags) {
                error = message
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

<!-- file: Sources/ResoluteApp/CustomResolutions/CustomResolutionsWindowController.swift | task: 9 | kind: impl -->
```swift
import AppKit
import ResoluteKit
import SwiftUI

/// Owns the Custom Resolutions window.
@MainActor
final class CustomResolutionsWindowController: NSWindowController {
    let model: CustomResolutionsModel

    init(model: CustomResolutionsModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Custom Resolutions"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: CustomResolutionsView(model: model))
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.setFrameAutosaveName("CustomResolutions")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window, selecting `displayID` when one is given.
    func show(selecting displayID: CGDirectDisplayID?) {
        model.select(displayID: displayID)
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Refreshes the display list after displays are connected or removed.
    func displaysDidChange() {
        guard window?.isVisible == true else { return }
        model.reloadTargets()
    }
}
```

<!-- file: Sources/ResoluteApp/CustomResolutions/EditorSnapshot.swift | task: 9 | kind: impl -->
```swift
import AppKit
import ResoluteKit
import SwiftUI

/// Renders the Custom Resolutions window to a PNG without putting anything on screen.
@MainActor
enum EditorSnapshot {
    static func render(to url: URL, size: NSSize = NSSize(width: 860, height: 560)) -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = CustomResolutionsModel(
            service: SystemDisplayService(),
            installer: OverrideInstaller(runner: RefusingRunner())
        )
        // Prefer a display that already has an override, so the table has rows.
        if let target = model.targets.first(where: \.hasOverride) {
            model.select(target.key)
        }
        let hosting = NSHostingView(rootView: CustomResolutionsView(model: model).frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        return withExtendedLifetime(window) {
            hosting.layoutSubtreeIfNeeded()
            // Let SwiftUI finish its first updates.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return 1 }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return 1 }
            do {
                try png.write(to: url)
                print("Wrote \(url.path(percentEncoded: false))")
                return 0
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                return 1
            }
        }
    }
}

/// Refuses every command, so a snapshot can never change the system.
struct RefusingRunner: CommandRunning {
    func run(_ script: String) async throws {
        throw ResoluteError.cancelled
    }
}
```

<!-- file: Sources/ResoluteApp/Diagnostics.swift | task: 9 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// Command-line switches for checking the app without its menu.
@MainActor
enum Diagnostics {
    /// Handles a diagnostic switch and returns its exit status, or nil to start normally.
    static func run(_ arguments: [String]) -> Int32? {
        if arguments.contains("--version") {
            print(ResoluteVersion.string)
            return 0
        }
        if let index = arguments.firstIndex(of: "--render-editor") {
            guard arguments.indices.contains(index + 1) else {
                FileHandle.standardError.write(Data("usage: Resolute --render-editor <file.png>\n".utf8))
                return 64
            }
            return EditorSnapshot.render(to: URL(filePath: arguments[index + 1]))
        }
        return nil
    }
}
```

<!-- file: Sources/ResoluteApp/main.swift | task: 9 | kind: impl -->
```swift
import AppKit
import ResoluteKit

if let status = Diagnostics.run(CommandLine.arguments) {
    exit(status)
}

let application = NSApplication.shared
let editor = CustomResolutionsWindowController(model: CustomResolutionsModel(service: SystemDisplayService()))
application.setActivationPolicy(.regular)
editor.show(selecting: nil)
application.run()
```

- [ ] **Step 3: Build**

Run: `swift build --product ResoluteApp 2>&1 | grep -E "error|warning|Compiling|Build complete" | tail -5`
Expected: `Build complete!`, no warnings in `Sources/ResoluteApp`.

- [ ] **Step 4: Render the editor offscreen and inspect it**

Run: `"$(swift build --show-bin-path)/ResoluteApp" --render-editor /tmp/resolute-editor.png`
Expected: `Wrote /tmp/resolute-editor.png`. Open the PNG (Read tool) and check: sidebar "Connected" lists "Built-in Retina Display"; "Other Overrides" lists the db4:3401 display; the selected override shows one row `2560 × 1080 | HiDPI | 5120 × 2160 | 64:27`; the "Name shown by macOS" field is empty with its placeholder; Save is disabled; the info note is visible; nothing overlaps or clips.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ResoluteApp
git commit -m "Add the Custom Resolutions editor and the app target"
```

---
### Task 10: Menu-bar app

**Files:**
- Modify: `Sources/ResoluteApp/main.swift`, `Sources/ResoluteApp/Diagnostics.swift` (full replacements below)
- Create: `Sources/ResoluteApp/AppDelegate.swift`, `Sources/ResoluteApp/StatusMenuController.swift`, `Sources/ResoluteApp/MenuRenderer.swift`, `Sources/ResoluteApp/ModeChangeCoordinator.swift`, `Sources/ResoluteApp/ConfirmationPanel.swift`, `Sources/ResoluteApp/LoginItemController.swift`, `Sources/ResoluteApp/Preferences.swift`, `Sources/ResoluteApp/Alerts.swift`, `Sources/ResoluteApp/AboutPanel.swift`
- Test: `--dump-menu` (rendered `NSMenu`) must equal `--dump-menu-model` (pure model, unit-tested in Task 5); the agent must launch and keep running (Step 3).

**Interfaces:**
- Consumes: `MenuModel`, `MenuNode`, `MenuItem`, `MenuAction`, `MenuSettings`, `LaunchAtLoginState`, `RevertCountdown` (Task 5); `DisplayControlling`, `SystemDisplayService`, `ConfigurationScope` (Task 2); `CustomResolutionsWindowController`, `CustomResolutionsModel`, `EditorSnapshot` (Task 9).
- Produces: `MenuRenderer.fill(_:with:target:action:)`, `MenuRenderer.describe(_:)`; `StatusMenuController.nodes(service:preferences:loginItem:showsDetails:)`; `ModeChangeCoordinator.apply(modeID:to:needsConfirmation:)`; `ConfirmationPanel.keepNewMode(countdown:) -> Bool`; `LoginItemController.state`, `.toggle()`; `Preferences.showLowResolutionModes`; `Alerts.show(_:title:)`; `AboutPanel.show()`; diagnostics `--dump-menu [--details]`, `--dump-menu-model [--details]`.

- [ ] **Step 1: Write the app shell**

<!-- file: Sources/ResoluteApp/main.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

if let status = Diagnostics.run(CommandLine.arguments) {
    exit(status)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
```

<!-- file: Sources/ResoluteApp/AppDelegate.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = SystemDisplayService()
    private let preferences = Preferences()
    private let loginItem = LoginItemController()
    private var statusMenu: StatusMenuController?
    private var customResolutions: CustomResolutionsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(
            service: service,
            preferences: preferences,
            loginItem: loginItem,
            modeChanges: ModeChangeCoordinator(service: service)
        ) { [weak self] displayID in
            self?.showCustomResolutions(selecting: displayID)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.customResolutions?.displaysDidChange()
            }
        }
    }

    private func showCustomResolutions(selecting displayID: CGDirectDisplayID?) {
        if customResolutions == nil {
            customResolutions = CustomResolutionsWindowController(model: CustomResolutionsModel(service: service))
        }
        customResolutions?.show(selecting: displayID)
    }
}
```

<!-- file: Sources/ResoluteApp/StatusMenuController.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// The status-bar item. Its menu is rebuilt each time it opens, so it is always current.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let service: any DisplayControlling
    private let preferences: Preferences
    private let loginItem: LoginItemController
    private let modeChanges: ModeChangeCoordinator
    private let openCustomResolutions: (CGDirectDisplayID?) -> Void

    init(
        service: any DisplayControlling,
        preferences: Preferences,
        loginItem: LoginItemController,
        modeChanges: ModeChangeCoordinator,
        openCustomResolutions: @escaping (CGDirectDisplayID?) -> Void
    ) {
        self.service = service
        self.preferences = preferences
        self.loginItem = loginItem
        self.modeChanges = modeChanges
        self.openCustomResolutions = openCustomResolutions
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Resolute")
            button.image?.isTemplate = true
            button.toolTip = "Resolute"
        }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The menu for the current displays and settings.
    static func nodes(
        service: any DisplayControlling,
        preferences: Preferences,
        loginItem: LoginItemController,
        showsDetails: Bool
    ) -> [MenuNode] {
        MenuModel.build(
            displays: service.displays(),
            settings: MenuSettings(
                showLowResolutionModes: preferences.showLowResolutionModes,
                launchAtLogin: loginItem.state,
                showsDetails: showsDetails
            )
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let nodes = Self.nodes(
            service: service, preferences: preferences, loginItem: loginItem,
            showsDetails: NSEvent.modifierFlags.contains(.option)
        )
        MenuRenderer.fill(menu, with: nodes, target: self, action: #selector(menuItemChosen(_:)))
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? MenuActionBox)?.action else { return }
        // Let the menu finish closing before the displays reconfigure.
        Task { self.perform(action) }
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .applyMode(let displayID, let modeID, let needsConfirmation):
            modeChanges.apply(modeID: modeID, to: displayID, needsConfirmation: needsConfirmation)
        case .setMirroring(let enabled):
            do {
                try service.setMirroring(enabled)
            } catch {
                Alerts.show(error, title: "Mirroring could not be changed")
            }
        case .openCustomResolutions(let displayID):
            openCustomResolutions(displayID)
        case .toggleLowResolutionModes:
            preferences.showLowResolutionModes.toggle()
        case .toggleLaunchAtLogin:
            loginItem.toggle()
        case .showAbout:
            AboutPanel.show()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
```

<!-- file: Sources/ResoluteApp/MenuRenderer.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// Turns `MenuNode`s into AppKit menu items.
@MainActor
enum MenuRenderer {
    static func fill(_ menu: NSMenu, with nodes: [MenuNode], target: AnyObject?, action: Selector?) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        for node in nodes {
            menu.addItem(makeItem(node, target: target, action: action))
        }
    }

    static func makeItem(_ node: MenuNode, target: AnyObject?, action: Selector?) -> NSMenuItem {
        switch node {
        case .separator:
            return .separator()
        case .header(let title):
            return .sectionHeader(title: title)
        case .item(let model):
            let item = NSMenuItem(
                title: model.title,
                action: model.action == nil ? nil : action,
                keyEquivalent: model.keyEquivalent
            )
            item.target = model.action == nil ? nil : target
            item.representedObject = model.action.map(MenuActionBox.init)
            item.isEnabled = model.isEnabled
            item.state = model.isChecked ? .on : .off
            if let symbolName = model.symbolName {
                item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            }
            if let badge = model.badge {
                item.badge = NSMenuItemBadge(string: badge)
            }
            if #available(macOS 14.4, *), let subtitle = model.subtitle {
                item.subtitle = subtitle
            }
            if let children = model.submenu {
                let submenu = NSMenu(title: model.title)
                fill(submenu, with: children, target: target, action: action)
                item.submenu = submenu
            }
            return item
        }
    }

    /// The rendered menu in `MenuModel.render`'s format, to check what AppKit received.
    static func describe(_ menu: NSMenu) -> String {
        describe(menu, depth: 0).joined(separator: "\n")
    }

    private static func describe(_ menu: NSMenu, depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        var lines: [String] = []
        for item in menu.items {
            if item.isSeparatorItem {
                lines.append("\(indent)---")
                continue
            }
            if item.isSectionHeader {
                lines.append("\(indent)# \(item.title)")
                continue
            }
            var line = indent + (item.state == .on ? "✓ " : "  ") + item.title
            if #available(macOS 14.4, *), let subtitle = item.subtitle {
                line += " — \(subtitle)"
            }
            if let badge = item.badge?.stringValue {
                line += " [\(badge)]"
            }
            if !item.isEnabled { line += " (disabled)" }
            if item.submenu != nil { line += " ▸" }
            lines.append(line)
            if let submenu = item.submenu {
                lines += describe(submenu, depth: depth + 1)
            }
        }
        return lines
    }
}

/// Carries a `MenuAction` in `NSMenuItem.representedObject`.
final class MenuActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
```

<!-- file: Sources/ResoluteApp/ModeChangeCoordinator.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// Applies mode changes chosen in the menu. Hidden modes are tried for the session first
/// and only kept when the person confirms, so a mode the display cannot show reverts.
@MainActor
final class ModeChangeCoordinator {
    private let service: any DisplayControlling

    init(service: any DisplayControlling) {
        self.service = service
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool) {
        let previous = service.currentModeID(of: displayID)
        guard previous != modeID else { return }
        do {
            try service.apply(modeID: modeID, to: displayID, scope: needsConfirmation ? .session : .permanent)
        } catch {
            Alerts.show(error, title: "The display mode could not be changed")
            return
        }
        guard needsConfirmation else { return }
        if ConfirmationPanel.keepNewMode(countdown: RevertCountdown()) {
            do {
                try service.apply(modeID: modeID, to: displayID, scope: .permanent)
            } catch {
                Alerts.show(error, title: "The display mode could not be saved")
            }
        } else if let previous {
            do {
                try service.apply(modeID: previous, to: displayID, scope: .permanent)
            } catch {
                Alerts.show(error, title: "The previous display mode could not be restored")
            }
        }
    }
}
```

<!-- file: Sources/ResoluteApp/ConfirmationPanel.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// "Keep this display mode?" with an automatic revert.
@MainActor
enum ConfirmationPanel {
    /// Returns true only when the person chooses Keep before the countdown ends. Return
    /// (the default button) reverts, which is the safe choice on an unreadable screen.
    static func keepNewMode(countdown: RevertCountdown) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Keep this display mode?"
        alert.informativeText = countdown.message(at: Date())
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Keep")
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                if countdown.isExpired(at: Date()) {
                    timer.invalidate()
                    NSApp.abortModal()
                } else {
                    alert.informativeText = countdown.message(at: Date())
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        NSApp.activate()
        let response = alert.runModal()
        timer.invalidate()
        return response == .alertSecondButtonReturn
    }
}
```

<!-- file: Sources/ResoluteApp/LoginItemController.swift | task: 10 | kind: impl -->
```swift
import Foundation
import ResoluteKit
import ServiceManagement

/// Launch at Login through `SMAppService`.
@MainActor
final class LoginItemController {
    var state: LaunchAtLoginState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func toggle() {
        do {
            switch state {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .disabled:
                try SMAppService.mainApp.register()
                if state == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            case .unavailable:
                break
            }
        } catch {
            Alerts.show(error, title: "Launch at Login could not be changed")
        }
    }
}
```

<!-- file: Sources/ResoluteApp/Preferences.swift | task: 10 | kind: impl -->
```swift
import Foundation

/// Settings kept in the app's user defaults.
@MainActor
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showLowResolutionModes: Bool {
        get { defaults.object(forKey: Key.showLowResolutionModes) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showLowResolutionModes) }
    }

    private enum Key {
        static let showLowResolutionModes = "ShowLowResolutionModes"
    }
}
```

<!-- file: Sources/ResoluteApp/Alerts.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

@MainActor
enum Alerts {
    /// Shows `error`, unless the person cancelled.
    static func show(_ error: Error, title: String) {
        if let error = error as? ResoluteError, error == .cancelled { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
```

<!-- file: Sources/ResoluteApp/AboutPanel.swift | task: 10 | kind: impl -->
```swift
import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "Switch any display to any mode from the menu bar, including the ones macOS hides.\nA ground-up successor to RDM.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
```

<!-- file: Sources/ResoluteApp/Diagnostics.swift | task: 10 | kind: impl -->
```swift
import AppKit
import ResoluteKit

/// Command-line switches for checking the app without opening its menu or windows.
@MainActor
enum Diagnostics {
    /// Handles a diagnostic switch and returns its exit status, or nil to start normally.
    static func run(_ arguments: [String]) -> Int32? {
        if arguments.contains("--version") {
            print(ResoluteVersion.string)
            return 0
        }
        if arguments.contains("--dump-menu") || arguments.contains("--dump-menu-model") {
            let nodes = StatusMenuController.nodes(
                service: SystemDisplayService(),
                preferences: Preferences(),
                loginItem: LoginItemController(),
                showsDetails: arguments.contains("--details")
            )
            if arguments.contains("--dump-menu-model") {
                print(MenuModel.render(nodes))
            } else {
                let menu = NSMenu()
                MenuRenderer.fill(menu, with: nodes, target: nil, action: nil)
                print(MenuRenderer.describe(menu))
            }
            return 0
        }
        if let index = arguments.firstIndex(of: "--render-editor") {
            guard arguments.indices.contains(index + 1) else {
                FileHandle.standardError.write(Data("usage: Resolute --render-editor <file.png>\n".utf8))
                return 64
            }
            return EditorSnapshot.render(to: URL(filePath: arguments[index + 1]))
        }
        return nil
    }
}
```

- [ ] **Step 2: Build and compare the rendered menu with the model**

```bash
swift build --product ResoluteApp 2>&1 | tail -2
BIN="$(swift build --show-bin-path)/ResoluteApp"
"$BIN" --dump-menu
diff <("$BIN" --dump-menu) <("$BIN" --dump-menu-model) && echo "AppKit menu matches the model"
diff <("$BIN" --dump-menu --details) <("$BIN" --dump-menu-model --details) && echo "details match too"
```

Expected: `Build complete!`; the dump starts with `# Built-in Retina Display`, then `  1728 × 1117 — HiDPI · 3456 × 2234 pixels ▸` with a HiDPI section (✓ on `1728 × 1117 [Default]`) and a Low Resolution section (`3456 × 2234 [Native]`), then `  120 Hz ▸` with six rates; both diffs are empty.

- [ ] **Step 3: Launch the agent and confirm it keeps running**

```bash
"$BIN" & echo $! > /tmp/resolute-agent.pid
# in a later command:
kill -0 "$(cat /tmp/resolute-agent.pid)" && echo "still running" && kill "$(cat /tmp/resolute-agent.pid)"
```

Expected: `still running` (a menu-bar agent with no Dock icon; the status item appears in the menu bar).

- [ ] **Step 4: Commit**

```bash
git add Sources/ResoluteApp
git commit -m "Add the menu-bar app with refresh rates, hidden-mode confirmation and launch at login"
```

---
### Task 11: App bundle, icon, install scripts, README and licence

**Files:**
- Create: `Resources/Info.plist`, `Scripts/make-icon.swift`, `Resources/AppIcon.icns` (generated), `Scripts/build-app.sh`, `Scripts/install.sh`, `Scripts/uninstall.sh`, `Makefile`, `README.md`, `LICENSE`
- Test: bundle checks in Step 4.

**Interfaces:**
- Consumes: products `ResoluteApp` and `resolute`; `ResoluteVersion.string` (read by `build-app.sh` from `Sources/ResoluteKit/Version.swift`).
- Produces: `dist/Resolute.app` (executable `Contents/MacOS/Resolute`, CLI `Contents/Helpers/resolute`), `dist/resolute`; `make build|test|live-test|app|install|uninstall|icon|clean`.

- [ ] **Step 1: Bundle template and icon**

<!-- file: Resources/Info.plist | task: 11 | kind: impl -->
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Resolute</string>
	<key>CFBundleExecutable</key>
	<string>Resolute</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.omarhanafy.Resolute</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Resolute</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>__VERSION__</string>
	<key>CFBundleVersion</key>
	<string>__BUILD__</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Omar Khaled. MIT License.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
```

<!-- file: Scripts/make-icon.swift | task: 11 | kind: impl -->
```swift
#!/usr/bin/env swift
// Draws Resolute's app icon and writes it as an .icns file.
//
//   swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory
    .appending(path: "Resolute-\(UUID().uuidString).iconset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func whiteSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
}

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let unit = CGFloat(pixels) / 1024

    // A rounded square on Apple's 1024-point icon grid, with a soft shadow.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.14, blue: 0.40, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.22, blue: 0.62, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.56, blue: 0.78, alpha: 1),
    ])!.draw(in: shape, angle: 60)

    // A display with "resize" arrows on its screen.
    if let display = whiteSymbol("display", pointSize: 430 * unit, weight: .regular) {
        let size = display.size
        display.draw(in: NSRect(
            x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2 + 6 * unit,
            width: size.width, height: size.height
        ))
    }
    if let arrows = whiteSymbol("arrow.up.left.and.arrow.down.right", pointSize: 150 * unit, weight: .semibold) {
        let size = arrows.size
        arrows.draw(in: NSRect(
            x: (CGFloat(pixels) - size.width) / 2, y: 560 * unit - size.height / 2,
            width: size.width, height: size.height
        ))
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path(percentEncoded: false), "-o", output.path(percentEncoded: false)]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(output.path(percentEncoded: false))")
```

Run: `swift Scripts/make-icon.swift Resources/AppIcon.icns && sips -s format png Resources/AppIcon.icns --out /tmp/resolute-icon.png`
Expected: `Wrote Resources/AppIcon.icns`; view `/tmp/resolute-icon.png` and check that the arrows sit inside the screen of the display glyph. Adjust the arrows' `y` (560) if they do not.

- [ ] **Step 2: Build, install and uninstall scripts, Makefile**

<!-- file: Scripts/build-app.sh | task: 11 | kind: impl -->
```bash
#!/usr/bin/env bash
# Builds dist/Resolute.app and dist/resolute as universal binaries, signed ad hoc.
#   UNIVERSAL=0 Scripts/build-app.sh    # this Mac's architecture only (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/ResoluteKit/Version.swift)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=(--arch arm64 --arch x86_64)
[[ "${UNIVERSAL:-1}" == "0" ]] && ARCHS=()

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

APP="dist/Resolute.app"
rm -rf "$APP" dist/resolute
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ResoluteApp" "$APP/Contents/MacOS/Resolute"
cp "$BIN/resolute" "$APP/Contents/Helpers/resolute"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - --identifier com.omarhanafy.Resolute.cli "$APP/Contents/Helpers/resolute"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
cp "$APP/Contents/Helpers/resolute" dist/resolute

echo "Built $APP and dist/resolute (version $VERSION, build $BUILD)"
```

<!-- file: Scripts/install.sh | task: 11 | kind: impl -->
```bash
#!/usr/bin/env bash
# Installs Resolute.app and links the resolute command.
#   RESOLUTE_APP_DIR=~/Applications RESOLUTE_BIN_DIR=~/.local/bin Scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="com.omarhanafy.Resolute"

[[ -d dist/Resolute.app ]] || Scripts/build-app.sh

osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$APP_DIR/Resolute.app"
ditto dist/Resolute.app "$APP_DIR/Resolute.app"
echo "Installed $APP_DIR/Resolute.app"

CLI="$APP_DIR/Resolute.app/Contents/Helpers/resolute"
if [[ -d "$BIN_DIR" && -w "$BIN_DIR" ]]; then
  ln -sf "$CLI" "$BIN_DIR/resolute"
  echo "Linked $BIN_DIR/resolute"
else
  echo "To use the command-line tool, run: sudo ln -sf \"$CLI\" \"$BIN_DIR/resolute\""
fi

open "$APP_DIR/Resolute.app"
```

<!-- file: Scripts/uninstall.sh | task: 11 | kind: impl -->
```bash
#!/usr/bin/env bash
# Removes Resolute.app, its command-line link and its preferences.
# Override files and their backups are left in place (see README.md).
set -euo pipefail

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="com.omarhanafy.Resolute"

osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$APP_DIR/Resolute.app"
if [[ -L "$BIN_DIR/resolute" && "$(readlink "$BIN_DIR/resolute")" == *"Resolute.app/Contents/Helpers/resolute" ]]; then
  rm -f "$BIN_DIR/resolute" 2>/dev/null || echo "Remove the command-line link with: sudo rm \"$BIN_DIR/resolute\""
fi
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Removed Resolute."
echo "Custom resolution overrides in /Library/Displays and backups in /Library/Application Support/Resolute are untouched."
```

<!-- file: Makefile | task: 11 | kind: impl -->
```make
.PHONY: build test live-test app install uninstall icon clean

build:
	swift build

test:
	swift test

# Also switches the main display's refresh rate for a moment and back.
live-test:
	RESOLUTE_LIVE_TESTS=1 swift test --filter LiveDisplayTests

app:
	Scripts/build-app.sh

install: app
	Scripts/install.sh

uninstall:
	Scripts/uninstall.sh

icon:
	swift Scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build dist
```

Run: `chmod +x Scripts/*.sh Scripts/*.swift`

- [ ] **Step 3: README and licence**

<!-- file: LICENSE | task: 11 | kind: impl -->
```text
MIT License

Copyright (c) 2026 Omar Khaled

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

<!-- file: README.md | task: 11 | kind: impl -->
````markdown
# Resolute

Pick any resolution and refresh rate for your Mac's displays from the menu bar, including the modes System Settings hides.

Resolute is a ground-up successor to [RDM](https://github.com/avibrazil/RDM). On current macOS, RDM misreads refresh rates (it shows 0 Hz and switches to 47.95 Hz when you pick a resolution) and cannot name displays on Apple silicon.

## What it does

- **Every mode in one menu.** HiDPI ("looks like") resolutions, low-resolution 1× modes such as your panel's full native resolution, and, while you hold ⌥, modes macOS lists nowhere.
- **Refresh rates.** Switch between 120, 60, 59.94, 50, 48 and 47.95 Hz, or whatever your display offers, without changing the resolution.
- **Safe hidden modes.** A hidden mode is tried for the current session and reverts after 15 seconds unless you choose Keep, so a mode your display cannot show undoes itself.
- **Mirroring** on or off with one click.
- **Custom HiDPI resolutions** through display override files, like RDM's editor, with automatic backups.
- **A command-line tool,** `resolute`, for scripts and shortcuts, with JSON output.
- **Launch at Login.**

## Requirements

- macOS 14 Sonoma or later. Developed and tested on macOS 27 on Apple silicon.
- To build: Xcode 16 or later (Swift 6).

## Install

```sh
git clone https://github.com/omar-hanafy/Resolute.git
cd Resolute
make install
```

`make install` builds `dist/Resolute.app` (universal, signed ad hoc), copies it to `/Applications`, links the `resolute` command into `/usr/local/bin` when that folder is writable, and opens the app. `make app` only builds; the results are in `dist/`.

If you used RDM, quit it and remove it from System Settings › General › Login Items. Resolute reads the override files RDM wrote.

To uninstall, turn off Launch at Login in the menu, then run `make uninstall`.

## The menu

Click the display icon in the menu bar. Each display shows its current resolution and refresh rate; both open a submenu.

- **HiDPI** resolutions look sharp: macOS draws them at twice the size and scales the result to your panel.
- **Low Resolution (1×)** modes draw one pixel per point. On a Retina display this is how you get the panel's full native resolution (3456 × 2234 on a 16-inch MacBook Pro), at the cost of very small text. Turn the section off with **Show Low-Resolution Modes**.
- **Default** marks macOS's default mode and **Native** the panel's native size.
- Hold **⌥** while opening the menu to see hidden modes, mode IDs and pixel sizes.

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
$ resolute mirror toggle
$ resolute displays --json
```

`-d` takes `main`, an index from `resolute displays`, `id:<number>`, or part of a display's name. `resolute help <command>` explains the rest.

## Custom resolutions

macOS reads per-display override files from `/Library/Displays/Contents/Resources/Overrides`. The **Custom Resolutions…** window, and `resolute overrides`, edit the `scale-resolutions` list in those files, so you can add modes a display does not offer, such as 2560 × 1080 HiDPI on a 5120 × 2160 monitor.

- Saving asks for an administrator password. The file being replaced is first copied to `/Library/Application Support/Resolute/Backups`.
- New modes appear after you reconnect the display or restart the Mac.
- On Apple silicon Macs, macOS may ignore custom scaled resolutions for some displays.
- **Remove Override…** (or `sudo resolute overrides reset -d <display>`) deletes the file and returns the display to its defaults.

```sh
resolute overrides list
sudo resolute overrides add 2560x1080 -d DELL              # HiDPI, looks like 2560 × 1080
sudo resolute overrides add 3440x1440 --standard -d DELL   # a 1× mode
sudo resolute overrides remove 2560x1080 -d DELL
sudo resolute overrides reset -d DELL
```

## How it works

Resolute asks CoreGraphics for every mode, including the low-resolution duplicates it usually hides. It also reads the private SkyLight mode list that RDM relied on, which can include modes CoreGraphics leaves out. Before trusting that list, Resolute decodes every record and checks it against CoreGraphics; if the record layout changes in a future macOS, hidden modes disappear instead of showing wrong values. Listed modes are switched with the public `CGConfigureDisplayWithDisplayMode`; only hidden ones use `CGSConfigureDisplayMode`.

The macOS 27 record layout is documented in [docs/design/2026-09-25-resolute-design.md](docs/design/2026-09-25-resolute-design.md). `swift Scripts/capture-mode-fixture.swift` dumps your main display's raw records, which is how to check a new macOS release.

## Development

```sh
make build       # swift build
make test        # unit tests (Swift Testing)
make live-test   # also switches the main display's refresh rate for a moment and back
make app         # dist/Resolute.app and dist/resolute
make icon        # regenerates Resources/AppIcon.icns
```

`Resolute.app/Contents/MacOS/Resolute --dump-menu` prints the menu as it would appear, and `--render-editor file.png` renders the Custom Resolutions window without showing it.

## Credits

Resolute is new code. The idea and the override-file format come from RDM by Avi Alkalay and its forks, including usr-sse2's resolution editor; display mirroring follows fcanas/mirror-displays.

## License

MIT. See [LICENSE](LICENSE).
````

- [ ] **Step 4: Build the bundle and check it**

```bash
make app
codesign --verify --strict --verbose=2 dist/Resolute.app
lipo -info dist/Resolute.app/Contents/MacOS/Resolute dist/resolute
plutil -p dist/Resolute.app/Contents/Info.plist | grep -E "CFBundleIdentifier|ShortVersion|LSUIElement"
dist/Resolute.app/Contents/MacOS/Resolute --version
dist/resolute --version
dist/Resolute.app/Contents/MacOS/Resolute --dump-menu | head -20
```

Expected: signature valid; both binaries `x86_64 arm64`; identifier `com.omarhanafy.Resolute`, version `0.1.0`, `LSUIElement => true`; both print `0.1.0`; the menu dump matches Task 10's. The dump now shows `Launch at Login` without "Available when Resolute runs from its app bundle", because it runs from the bundle.

Then launch the real app and confirm it stays up without a Dock icon:

```bash
open dist/Resolute.app
pgrep -x Resolute                                   # prints a PID (check in a separate command)
osascript -e 'tell application id "com.omarhanafy.Resolute" to quit'
```

- [ ] **Step 5: Commit**

```bash
git add Resources Scripts Makefile README.md LICENSE
git commit -m "Package Resolute as an app bundle with install scripts, icon and README"
```

---

### Task 12: Final verification and private publication

**Files:** none new. This task proves the whole and publishes it.

- [ ] **Step 1: Full test run**

Run: `swift test 2>&1 | tail -5` and `make live-test 2>&1 | tail -5`
Expected: every suite passes; live tests pass and the display is back on its original mode (`dist/resolute` shows mode 54 on the development Mac).

- [ ] **Step 2: End-to-end from the bundle**

Repeat Task 8 Step 4 with `B=dist/resolute`, run `dist/Resolute.app/Contents/MacOS/Resolute --render-editor /tmp/resolute-editor.png` and inspect the image.

- [ ] **Step 3: Independent review**

Dispatch a code reviewer (superpowers:requesting-code-review) over the whole repository against the spec. Fix confirmed findings with tests, re-run Steps 1–2, and commit.

- [ ] **Step 4: Publish privately under omar-hanafy**

```bash
gh auth switch --hostname github.com --user omar-hanafy
gh api user --jq .login                               # omar-hanafy
gh repo view omar-hanafy/Resolute >/dev/null 2>&1 && echo "exists" || echo "free"
gh repo create omar-hanafy/Resolute --private \
  --description "Menu-bar display mode switcher for macOS: every resolution and refresh rate, including the hidden ones. A ground-up successor to RDM." \
  --source . --remote origin --push
gh repo view omar-hanafy/Resolute --json visibility,url,defaultBranchRef
git status -sb                                        # main tracks origin/main
```

Expected: login `omar-hanafy`; `free` before creation; `"visibility":"PRIVATE"` afterwards; the working tree is clean and in sync with `origin/main`.
