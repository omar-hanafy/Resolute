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
