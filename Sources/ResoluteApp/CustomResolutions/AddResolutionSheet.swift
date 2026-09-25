import ResoluteKit
import SwiftUI

/// Asks for a new custom resolution.
///
/// The size fields hold text, which updates on every keystroke. A value-formatted field
/// commits only on Return or focus loss, and clicking Add would read the old number.
struct AddResolutionSheet: View {
    @Bindable var model: CustomResolutionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var widthText = "1920"
    @State private var heightText = "1080"
    @State private var hiDPI = true
    @State private var ratio: AspectRatio?
    @State private var flagsText = HiDPIFlags.standard.description
    @State private var error: String?
    @State private var target: OverrideKey?

    init(model: CustomResolutionsModel) {
        self.model = model
        _target = State(initialValue: model.selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Width", text: $widthText).monospacedDigit()
                    TextField("Height", text: $heightText).monospacedDigit()
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
        .onChange(of: widthText) { applyRatio() }
        .onChange(of: ratio) { applyRatio() }
    }

    private var explanation: String {
        guard let size = ResolutionInput.size(width: widthText, height: heightText) else {
            return ResolutionInput.sizeHint
        }
        guard hiDPI else { return "\(size.width) × \(size.height) pixels, drawn at 1×." }
        let pixels = "\(size.width * 2) × \(size.height * 2)"
        return "Looks like \(size.width) × \(size.height). macOS renders \(pixels) pixels and scales them to the panel. "
            + "A 1× entry at \(pixels) is added with it, unless the list already has one."
    }

    private func applyRatio() {
        guard let ratio, let width = Int(widthText.trimmingCharacters(in: .whitespaces)), width > 0 else { return }
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
