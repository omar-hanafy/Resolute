import AppKit
import SwiftUI
import Testing
@testable import ResoluteDesign

@MainActor
@Suite struct PicturesTests {
    /// The repository, found from this file's place in Tests/ResoluteDesignTests.
    nonisolated static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// An image's pixels in sRGB, premultiplied RGBA, top row first.
    struct Pixels {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        init(_ image: CGImage, width: Int? = nil, height: Int? = nil) {
            self.width = width ?? image.width
            self.height = height ?? image.height
            bytes = [UInt8](repeating: 0, count: self.width * self.height * 4)
            let (w, h) = (self.width, self.height)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }

        /// Red, green, blue and alpha at a pixel, counted from the top left.
        subscript(x: Int, y: Int) -> [Int] {
            let index = (y * width + x) * 4
            return (0..<4).map { Int(bytes[index + $0]) }
        }

        /// The share of pixels that are more opaque than not.
        var coverage: Double {
            let opaque = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 127 }.count
            return Double(opaque) / Double(width * height)
        }
    }

    /// `image` drawn `width` pixels wide at its own aspect ratio.
    private func pixels(of image: NSImage, width: Int) throws -> Pixels {
        let height = Int((CGFloat(width) * image.size.height / image.size.width).rounded())
        var rect = NSRect(x: 0, y: 0, width: width, height: height)
        let cgImage = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return Pixels(cgImage, width: width, height: height)
    }

    /// `view` drawn by SwiftUI at `size` points, twice over, in `colorScheme`.
    private func render(_ view: some View, size: CGSize, colorScheme: ColorScheme = .light) throws -> Pixels {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, colorScheme)
        )
        renderer.scale = 2
        return Pixels(try #require(renderer.cgImage))
    }

    // MARK: Display pictures

    @Test(arguments: DisplayPictureModel.allCases)
    func displayPictureArtworkDecodes(_ model: DisplayPictureModel) throws {
        let image = model.nsImage()
        #expect(image.isValid)
        #expect(image.size == CGSize(width: 160, height: 120))
        #expect(image.size.width / image.size.height == DisplayPicture.aspectRatio)
        #expect(image.representations.contains { $0 is NSPDFImageRep }, "Figma's artwork should stay vector")
        #expect(image.accessibilityDescription == model.title)
        // Every model fills at least a third of Figma's frame and leaves room around it.
        let coverage = try pixels(of: image, width: 160).coverage
        #expect(coverage > 0.3 && coverage < 0.9)
    }

    @Test func everyModelHasItsOwnArtwork() {
        let sources = DisplayPictureModel.allCases.map(\.artwork.source)
        #expect(Set(sources).count == DisplayPictureModel.allCases.count)
        #expect(sources.allSatisfy { $0.hasPrefix("Design/DisplayPictures/") })
    }

    @Test func eachImageIsTheCallersOwn() {
        let image = DisplayPictureModel.tv.nsImage()
        image.size = CGSize(width: 16, height: 12)
        #expect(DisplayPictureModel.tv.nsImage().size == CGSize(width: 160, height: 120))
    }

    @Test func displayPictureDrawsInSwiftUI() throws {
        let pixels = try render(DisplayPicture(.studioDisplay), size: CGSize(width: 160, height: 120))
        // The middle of the screen is Figma's blue gradient; the top corner is empty.
        let screen = pixels[160, 100]
        #expect(screen[3] == 255 && screen[2] > 200 && screen[0] < 120, "screen \(screen)")
        #expect(pixels[2, 2][3] == 0)
    }

    // MARK: Space thumbnails

    @Test func thumbnailsClampStops() {
        #expect(SpaceThumbnail(stop: 0, tone: .violet, isSelected: false).stop == 1)
        #expect(SpaceThumbnail(stop: -4, tone: .teal, isSelected: true).stop == 1)
        #expect(SpaceThumbnail(stop: 3, tone: .violet, isSelected: false).stop == 3)
        #expect(SpaceThumbnail(stop: 6, tone: .teal, isSelected: false).stop == 5)
        #expect(SpaceThumbnail(stop: .max, tone: .violet, isSelected: true).stop == 5)
        #expect(SpaceThumbnail.Layout(stop: 9) == SpaceThumbnail.Layout(stop: 5))
        #expect(SpaceThumbnail.Layout(stop: -1) == SpaceThumbnail.Layout(stop: 1))
    }

    /// Figma's geometry for stops 1 and 5, from the variants' SVG export, which rounds to
    /// hundredths of a point.
    @Test func thumbnailLayoutMatchesFigma() {
        let first = SpaceThumbnail.Layout(stop: 1)
        expect(first.window, CGRect(x: 7, y: 8, width: 81, height: 48.6))
        #expect(abs(first.windowCornerRadius - 5.7) < 0.015)
        expect(first.lights[0], CGRect(x: 10.96, y: 11.51, width: 2.88, height: 2.88))
        expect(first.lights[2], CGRect(x: 19.96, y: 11.51, width: 2.88, height: 2.88))
        expect(first.lines[0], CGRect(x: 12.4, y: 18.8, width: 58.97, height: 3.24))
        expect(first.lines[1], CGRect(x: 12.4, y: 26.45, width: 42.12, height: 3.24))
        expect(first.lines[4], CGRect(x: 12.4, y: 49.4, width: 58.97, height: 3.24))

        let last = SpaceThumbnail.Layout(stop: 5)
        expect(last.window, CGRect(x: 7, y: 8, width: 45.9, height: 27.54))
        #expect(abs(last.windowCornerRadius - 4.53) < 0.015)
        expect(last.lights[0], CGRect(x: 9.24, y: 9.98, width: 1.64, height: 1.64))
        expect(last.lines[1], CGRect(x: 10.06, y: 18.46, width: 23.87, height: 1.84))
        expect(last.lines[4], CGRect(x: 10.06, y: 31.46, width: 33.42, height: 1.84))
    }

    @Test func laterStopsLeaveMoreSpace() {
        let widths = SpaceThumbnail.stops.map { SpaceThumbnail.Layout(stop: $0).window.width }
        #expect(widths == widths.sorted(by: >))
        #expect(Set(widths).count == widths.count)
    }

    @Test func selectedThumbnailHasARingOutsideItsFrame() throws {
        // A 100 × 64 thumbnail padded by 4 points: the ring is 2 points outside its frame.
        let size = CGSize(width: 108, height: 72)
        let selected = try render(SpaceThumbnail(stop: 2, tone: .teal, isSelected: true).padding(4), size: size)
        let plain = try render(SpaceThumbnail(stop: 2, tone: .teal, isSelected: false).padding(4), size: size)
        // One point outside the left edge, halfway down, at 2× scale.
        let ring = selected[6, 72]
        #expect(ring[3] == 255 && ring[2] > ring[0], "ring \(ring)")
        #expect(plain[6, 72][3] == 0)
        // Inside, both show the same wallpaper.
        #expect(selected[180, 120] == plain[180, 120])
    }

    // MARK: App icon

    @Test(arguments: AppIconView.Appearance.allCases)
    func appIconArtworkDecodes(_ appearance: AppIconView.Appearance) throws {
        let image = AppIconView.nsImage(appearance)
        #expect(image.isValid)
        #expect(image.size == CGSize(width: 128, height: 128))
        #expect(image.representations.contains { $0 is NSPDFImageRep })
        #expect(try pixels(of: image, width: 128).coverage > 0.6)
    }

    @Test func appIconFollowsTheColorScheme() throws {
        #expect(AppIconView.Appearance(.light) == .default)
        #expect(AppIconView.Appearance(.dark) == .dark)
        let size = CGSize(width: 64, height: 64)
        // Near the top of the rounded square: Default is light blue, Dark is navy under its glow.
        let light = try render(AppIconView(), size: size, colorScheme: .light)[64, 20]
        let dark = try render(AppIconView(), size: size, colorScheme: .dark)[64, 20]
        #expect(light[1] > 130 && dark[1] < 100, "light \(light), dark \(dark)")
        #expect(try render(AppIconView(.default), size: size, colorScheme: .dark)[64, 20] == light)
    }

    @Test func appIconFileHasEverySize() throws {
        let image = try #require(NSImage(contentsOf: Self.root.appending(path: "Resources/AppIcon.icns")))
        let widths = Set(image.representations.map(\.pixelsWide))
        #expect(widths.isSuperset(of: [16, 32, 64, 128, 256, 512, 1024]))
    }

    /// Resources/AppIcon.icns comes from Design/AppIcon/default.pdf: run `make icon` after
    /// changing the artwork.
    @Test func appIconFileMatchesItsArtwork() throws {
        let icns = try #require(NSImage(contentsOf: Self.root.appending(path: "Resources/AppIcon.icns")))
        let rep = try #require(icns.representations.first { $0.pixelsWide == 128 && $0.pixelsHigh == 128 })
        var rect = NSRect(x: 0, y: 0, width: 128, height: 128)
        let packed = Pixels(try #require(rep.cgImage(forProposedRect: &rect, context: nil, hints: nil)))
        let drawn = try pixels(of: AppIconView.nsImage(.default), width: 128)
        let difference = zip(packed.bytes, drawn.bytes).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        #expect(Double(difference) / Double(packed.bytes.count) < 2, "mean difference per channel")
    }

    // MARK: Embedded artwork

    @Test(arguments: Artwork.all.map(\.source))
    func embeddedArtworkMatchesDesign(_ source: String) throws {
        let artwork = try #require(Artwork.all.first { $0.source == source })
        let file = try Data(contentsOf: Self.root.appending(path: source))
        #expect(artwork.data == file, "\(source) changed: run swift Scripts/embed-assets.swift")
    }

    /// Every PDF or PNG in a folder of Design/ is embedded, as Scripts/embed-assets.swift does.
    @Test func everyDesignFileIsEmbedded() throws {
        let design = Self.root.appending(path: "Design")
        let files = try FileManager.default.subpathsOfDirectory(atPath: design.path(percentEncoded: false))
            .filter { $0.split(separator: "/").count == 2 && ["pdf", "png"].contains(URL(filePath: $0).pathExtension.lowercased()) }
            .map { "Design/\($0)" }
        #expect(Set(files) == Set(Artwork.all.map(\.source)))
    }

    // MARK: Catalog

    @Test func everyPictureSceneNamesItsFigmaNode() {
        let scenes = DesignCatalog.pictures
        #expect(scenes.count == 8)
        #expect(scenes.allSatisfy { $0.id.hasPrefix("ds.pictures.") && $0.figmaNode != nil })
    }

    private func expect(_ rect: CGRect, _ figma: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
        let tolerance: CGFloat = 0.015
        let close = abs(rect.minX - figma.minX) < tolerance && abs(rect.minY - figma.minY) < tolerance
            && abs(rect.width - figma.width) < tolerance && abs(rect.height - figma.height) < tolerance
        #expect(close, "\(rect) is not Figma's \(figma)", sourceLocation: sourceLocation)
    }
}
