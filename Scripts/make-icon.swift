#!/usr/bin/env swift
// Draws Resolute's app icon and writes it as an .icns file.
//
//   swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory
    .appending(path: "Resolute-\(UUID().uuidString).iconset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
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

    // A white display with "resize" arrows on its screen.
    if let display = symbol("display", pointSize: 430 * unit, weight: .regular, color: .white) {
        let size = display.size
        display.draw(in: NSRect(
            x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2 + 6 * unit,
            width: size.width, height: size.height
        ))
    }
    let arrowColor = NSColor(srgbRed: 0.12, green: 0.30, blue: 0.68, alpha: 1)
    if let arrows = symbol("arrow.up.left.and.arrow.down.right", pointSize: 170 * unit, weight: .bold, color: arrowColor) {
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
