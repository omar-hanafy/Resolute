#!/usr/bin/env swift
// Writes Resources/AppIcon.icns from the app icon's Figma artwork, Design/AppIcon/default.pdf
// (Components › App Icon › Default, the master on the App Icon page): every size from 16
// to 512 points at 1× and 2×, each drawn from the vector artwork at its own pixel size in
// sRGB, then packed by iconutil.
//
//   swift Scripts/make-icon.swift [artwork.pdf] [output.icns]
//
// `make icon` runs it with those two files, which are also the defaults. An .icns has one
// appearance; the Dark and Tinted icons need an Icon Composer icon.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
let artwork = URL(filePath: arguments.count > 0 ? arguments[0] : "Design/AppIcon/default.pdf")
let output = URL(filePath: arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

guard let document = CGPDFDocument(artwork as CFURL), let page = document.page(at: 1) else {
    fail("can't read \(artwork.path(percentEncoded: false)) as a PDF.")
}
let box = page.getBoxRect(.mediaBox)
guard box.width > 0, box.width == box.height else {
    fail("the artwork must be square; its page is \(box.width) × \(box.height).")
}

/// The artwork drawn into a `pixels` × `pixels` sRGB bitmap.
func render(pixels: Int) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { fail("can't make a \(pixels)-pixel bitmap.") }
    // The artwork's drop shadow is a bitmap inside the PDF; resample it smoothly.
    context.interpolationQuality = .high
    let scale = CGFloat(pixels) / box.width
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.minX, y: -box.minY)
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { fail("can't draw the \(pixels)-pixel icon.") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("can't write \(url.path(percentEncoded: false)).") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path(percentEncoded: false)).") }
}

let iconset = FileManager.default.temporaryDirectory
    .appending(path: "Resolute-\(UUID().uuidString).iconset", directoryHint: .isDirectory)
do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("can't make \(iconset.path(percentEncoded: false)): \(error.localizedDescription)")
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        writePNG(render(pixels: points * scale), to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path(percentEncoded: false), "-o", output.path(percentEncoded: false)]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    try? FileManager.default.removeItem(at: iconset)
    fail("can't run iconutil: \(error.localizedDescription)")
}
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(output.path(percentEncoded: false))")
