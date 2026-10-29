import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Asks for a new custom resolution, showing what it would look like (Figma 35:784).
///
/// The size fields hold text, which updates on every keystroke. A value-formatted field
/// commits only on Return or focus loss, and clicking Add would read the old number.
struct AddResolutionSheet: View {
    @Bindable var model: CustomResolutionsModel
    /// The connected display, for its panel and the size it uses now; nil when it is away.
    let display: Display?
    @Environment(\.dismiss) private var dismiss
    @State private var widthText = "1920"
    @State private var heightText = "1080"
    @State private var hiDPI = true
    @State private var aspect: AspectChoice
    @State private var flagsText = HiDPIFlags.standard.description
    @State private var error: String?
    @State private var target: OverrideKey?

    /// Opens on `width` × `height`, 1920 × 1080 unless given.
    init(model: CustomResolutionsModel, display: Display?, width: Int = 1920, height: Int = 1080) {
        self.model = model
        self.display = display
        _target = State(initialValue: model.selection)
        _widthText = State(initialValue: String(width))
        _heightText = State(initialValue: String(height))
        let choices = AspectChoice.choices(panel: display.flatMap { DisplayFacts(display: $0, details: DisplayDetails()).nativeSize })
        let first = choices.first ?? .any
        _aspect = State(initialValue: first.matches(width: width, height: height) ? first : .any)
    }

    private var panel: DisplayFacts.PixelSize? {
        display.flatMap { DisplayFacts(display: $0, details: DisplayDetails()).nativeSize }
    }

    private var preview: AddResolutionPreview? {
        guard let size = ResolutionInput.size(width: widthText, height: heightText) else { return nil }
        return AddResolutionPreview(
            width: size.width, height: size.height, hiDPI: hiDPI, panel: panel,
            current: display?.currentMode.map { (width: $0.width, height: $0.height) },
            existing: model.rows.map(\.entry)
        )
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: Metrics.DisplayPage.Sheet.spacing) {
            Text("Add a Resolution to \(model.selectedTarget?.name ?? "This Display")")
                .textStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: Metrics.DisplayPage.Sheet.fieldSpacing) {
                SizeField(title: "Width", text: $widthText)
                Text("×")
                    .textStyle(.body)
                    .foregroundStyle(Palette.labelSecondary)
                    .accessibilityHidden(true)
                SizeField(title: "Height", text: $heightText)
                    .disabled(aspect != .any)
            }

            SegmentedTabs(
                AspectChoice.choices(panel: panel).map { SegmentedTabs.Item($0, $0.title(panel: panel)) },
                selection: $aspect
            )
            .fixedSize()
            .accessibilityLabel("Aspect ratio")

            HStack(spacing: Metrics.Spacing.large) {
                VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                    Text("HiDPI (sharp text)")
                        .textStyle(.body)
                        .foregroundStyle(Palette.labelPrimary)
                    let help = preview?.renderingHelp ?? ResolutionInput.sizeHint
                    Text(help)
                        .textStyle(.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(SpokenText.sizes(help))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FormRowSwitch("HiDPI (sharp text)", isOn: $hiDPI)
            }

            if let preview {
                ResolutionPreviewCard(
                    stop: preview.stop,
                    tone: DisplayPagePresentation.tone(for: display),
                    title: preview.title,
                    lines: preview.lines
                )
                if let warning = preview.warning {
                    CompactWarning(warning)
                }
            }

            if hiDPI {
                DisclosureGroup("Advanced") {
                    LabeledContent("Flags") {
                        TextField("Flags", text: $flagsText)
                            .textStyle(.mono)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, Metrics.Spacing.xSmall)
                }
                .textStyle(.callout)
            }

            if let error {
                Text(error)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Metrics.DisplayPage.buttonSpacing) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Metrics.DisplayPage.Sheet.insets)
        .frame(width: Metrics.DisplayPage.Sheet.addWidth)
        .onChange(of: widthText) { applyRatio() }
        .onChange(of: aspect) { applyRatio() }
    }

    private func applyRatio() {
        guard case .ratio(let ratio) = aspect,
              let width = Int(widthText.trimmingCharacters(in: .whitespaces)), width > 0
        else { return }
        heightText = String(ratio.height(forWidth: width))
    }

    private func add() {
        do {
            let entry = try ResolutionInput.entry(width: widthText, height: heightText, hiDPI: hiDPI, flags: flagsText)
            if let message = model.add(entry, to: target) {
                error = message
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Width" and its field.
private struct SizeField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Metrics.DisplayPage.Sheet.fieldSpacing) {
            Text(title)
                .textStyle(.body)
                .foregroundStyle(Palette.labelSecondary)
                .accessibilityHidden(true)
            TextField(title, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: Metrics.DisplayPage.Sheet.sizeFieldWidth)
                .accessibilityLabel(title)
        }
    }
}

/// The aspect ratio the height follows: the panel's own ("16:9 · Native"), a common one, or
/// Any, which leaves the height to the person.
enum AspectChoice: Hashable {
    case ratio(AspectRatio)
    case any

    /// The panel's own ratio first, then 16:9, 16:10, 21:9 and 32:9, then Any.
    static func choices(panel: DisplayFacts.PixelSize?) -> [AspectChoice] {
        let common = [(16, 9), (16, 10), (21, 9), (32, 9)].map { AspectRatio(width: $0.0, height: $0.1) }
        let native = panel.map { AspectRatio(width: $0.width, height: $0.height) }
        let ratios = (native.map { [$0] } ?? []) + common.filter { $0 != native }
        return ratios.map(AspectChoice.ratio) + [.any]
    }

    func title(panel: DisplayFacts.PixelSize?) -> String {
        switch self {
        case .any:
            return "Any"
        case .ratio(let ratio):
            let isNative = panel.map { AspectRatio(width: $0.width, height: $0.height) == ratio } ?? false
            return isNative ? "\(ratio) · Native" : ratio.description
        }
    }

    func matches(width: Int, height: Int) -> Bool {
        guard case .ratio(let ratio) = self else { return true }
        return ratio.height(forWidth: width) == height
    }
}

/// What the Add Resolution sheet says about a size before it is added (Figma 35:784).
struct AddResolutionPreview: Equatable {
    /// Under HiDPI (sharp text): "Rendered at 6016 × 3384, then scaled to the 3840 × 2160 panel."
    var renderingHelp: String
    /// "Looks like 3008 × 1692"
    var title: String
    /// "More space than now (2560 × 1440); text about 15% smaller." and "Adds 6016 × 3384
    /// (1×) too, the size it renders at."
    var lines: [String]
    /// Which desktop picture suits it, 1 (largest text) to 5 (most space), 3 being now.
    var stop: Int
    /// Shown for a HiDPI size drawn wider than some Macs can.
    var warning: String?

    /// Pixels wider than this, some Macs can't draw for an external display: their display
    /// ports' limit (see `DrawingLimit`).
    static let wideRenderingLimit = 6144
    /// The sheet cautions from 90% of the limit up: how wide a Mac really draws isn't known
    /// to the pixel, and a size just under the limit is the one people try first.
    static let wideRenderingCaution = wideRenderingLimit * 9 / 10

    init(
        width: Int,
        height: Int,
        hiDPI: Bool,
        panel: DisplayFacts.PixelSize?,
        current: (width: Int, height: Int)?,
        existing: [ScaleResolution]
    ) {
        let pixels = hiDPI ? (width: width * 2, height: height * 2) : (width: width, height: height)
        let pixelText = "\(pixels.width) × \(pixels.height)"
        if hiDPI {
            renderingHelp = panel.map { "Rendered at \(pixelText), then scaled to the \($0.text) panel." }
                ?? "Rendered at \(pixelText), then scaled to the panel."
        } else {
            renderingHelp = "\(pixelText) pixels, drawn at 1×."
        }
        title = "Looks like \(width) × \(height)"
        var lines: [String] = []
        var stop = 3
        if let current {
            let now = "\(current.width) × \(current.height)"
            if width == current.width, height == current.height {
                lines.append("The same size as now.")
            } else if width >= current.width {
                let percent = Int(((1 - Double(current.width) / Double(width)) * 100).rounded())
                lines.append(percent == 0
                    ? "About the same space as now (\(now))."
                    : "More space than now (\(now)); text about \(percent)% smaller.")
                stop = percent == 0 ? 3 : (percent < 10 ? 4 : 5)
            } else {
                let percent = Int(((Double(current.width) / Double(width) - 1) * 100).rounded())
                lines.append(percent == 0
                    ? "About the same space as now (\(now))."
                    : "Less space than now (\(now)); text about \(percent)% larger.")
                stop = percent == 0 ? 3 : (percent < 10 ? 2 : 1)
            }
        }
        if hiDPI {
            let partner = ScaleResolution.standard(width: pixels.width, height: pixels.height)
            if !existing.contains(where: { $0.sameMode(as: partner) }) {
                lines.append("Adds \(pixelText) (1×) too, the size it renders at.")
            }
        }
        self.lines = lines
        self.stop = stop
        warning = hiDPI && pixels.width >= Self.wideRenderingCaution
            ? "Some Macs can’t render scaled modes wider than \(Self.wideRenderingLimit) pixels on this display. If it doesn’t appear after reconnecting, try a smaller size."
            : nil
    }
}

/// Reads what was typed into the Add Resolution sheet.
enum ResolutionInput {
    static let sizeHint = "Enter a width and a height in whole numbers."

    /// The entry the sheet describes. The flags are read only for a HiDPI entry: the field
    /// is hidden for 1× ones, and whatever was left in it must not stop them being added.
    static func entry(width: String, height: String, hiDPI: Bool, flags: String) throws -> ScaleResolution {
        guard let size = size(width: width, height: height) else {
            throw ResoluteError.invalidEntry(sizeHint)
        }
        guard hiDPI else { return .standard(width: size.width, height: size.height) }
        return .hiDPI(width: size.width, height: size.height, flags: try HiDPIFlags(parsing: flags))
    }

    static func size(width: String, height: String) -> (width: Int, height: Int)? {
        let sizes = 1...ModeQuery.maximumDimension
        guard let width = Int(width.trimmingCharacters(in: .whitespaces)),
              let height = Int(height.trimmingCharacters(in: .whitespaces)),
              sizes.contains(width), sizes.contains(height)
        else { return nil }
        return (width, height)
    }
}
