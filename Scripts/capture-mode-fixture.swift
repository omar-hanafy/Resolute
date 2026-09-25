#!/usr/bin/env swift
// Captures a display's public modes and raw private SkyLight mode records as JSON, for
// Resolute's decoder tests. Read-only: it never changes a display.
//
//   swift Scripts/capture-mode-fixture.swift --list          # online displays and their IDs
//   swift Scripts/capture-mode-fixture.swift [display-id] > Tests/ResoluteKitTests/Fixtures/<name>.json
//
// Without a display ID it captures the main display. See docs/new-macos-release.md.
import CoreGraphics
import Foundation

typealias ModeCount = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
typealias ModeDescription = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--list"] {
    for id in onlineDisplays() {
        let traits = [
            "vendor " + String(CGDisplayVendorNumber(id), radix: 16), "product " + String(CGDisplayModelNumber(id), radix: 16),
            CGDisplayIsMain(id) != 0 ? "main" : nil, CGDisplayIsBuiltin(id) != 0 ? "built-in" : nil,
        ].compactMap { $0 }
        print("\(id)  (\(traits.joined(separator: ", ")))")
    }
    exit(0)
}
guard arguments.count <= 1 else { fail("usage: capture-mode-fixture.swift [--list | display-id]") }
let display: CGDirectDisplayID
if let text = arguments.first {
    guard let id = CGDirectDisplayID(text), onlineDisplays().contains(id) else {
        fail("“\(text)” is not an online display's ID. Run with --list to see them.")
    }
    display = id
} else {
    display = CGMainDisplayID()
}

let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
guard let countSymbol = dlsym(everyImage, "CGSGetNumberOfDisplayModes"),
      let descriptionSymbol = dlsym(everyImage, "CGSGetDisplayModeDescriptionOfLength")
else { fail("The SkyLight mode functions are unavailable.") }
let modeCount = unsafeBitCast(countSymbol, to: ModeCount.self)
let modeDescription = unsafeBitCast(descriptionSymbol, to: ModeDescription.self)

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
    "vendorID": String(CGDisplayVendorNumber(display), radix: 16),
    "productID": String(CGDisplayModelNumber(display), radix: 16),
    "isBuiltin": CGDisplayIsBuiltin(display) != 0,
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
