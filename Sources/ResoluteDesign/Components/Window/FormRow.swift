import AppKit
import SwiftUI

/// A settings row in a grouped form, as in System Settings: a title, optional help under
/// it and a trailing control (Figma: Components › Form Row, with a Switch, Pop-Up, Value,
/// Button or Chevron). It is 52 points high with help and 44 without.
///
/// Put rows in a `FormGroup`, which draws the dividers between them. The convenience
/// initializers make Figma's five controls; the general one takes any control.
public struct FormRow<Control: View>: View {
    public var title: String
    public var help: String?
    private var symbol: Symbol?
    private var symbolColor = Palette.green
    /// Makes the whole row a button, for the Chevron row.
    private var action: (() -> Void)?
    private let control: Control

    public init(_ title: String, help: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.help = help
        self.control = control()
    }

    /// Puts a symbol before the title, such as the green check of "resolute 0.4.0 is
    /// installed" in Settings › Command Line & Agents.
    public func symbol(_ symbol: Symbol, color: Color) -> Self {
        var row = self
        row.symbol = symbol
        row.symbolColor = color
        return row
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            } else {
                content
            }
        }
        .formGroupRow()
    }

    private var content: some View {
        HStack(spacing: symbol == nil ? WindowMetrics.Form.spacing : WindowMetrics.Form.symbolSpacing) {
            if let symbol {
                Image(symbol: symbol)
                    .font(.system(size: WindowMetrics.Form.symbolPointSize))
                    .foregroundStyle(symbolColor)
                    .frame(width: WindowMetrics.Form.symbolFrame, height: WindowMetrics.Form.symbolFrame)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: WindowMetrics.Form.textSpacing) {
                Text(title)
                    .textStyle(.body)
                    .foregroundStyle(Palette.labelPrimary)
                if let help {
                    Text(help)
                        .textStyle(.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(SpokenText.sizes(help))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.leading, Metrics.Group.horizontalPadding)
        .padding(.trailing, WindowMetrics.Form.trailingPadding)
        .padding(.vertical, WindowMetrics.Form.verticalPadding)
        .frame(minHeight: FormRowLayout.minimumHeight(hasHelp: help != nil))
    }
}

/// How tall Figma makes a form row.
enum FormRowLayout {
    static func minimumHeight(hasHelp: Bool) -> CGFloat {
        hasHelp ? Metrics.Group.tallRowHeight : Metrics.Group.rowHeight
    }
}

// MARK: - Figma's controls

extension FormRow where Control == FormRowSwitch {
    /// Figma's Switch row: "Launch at Login".
    public init(_ title: String, help: String? = nil, isOn: Binding<Bool>) {
        self.init(title, help: help) {
            FormRowSwitch(title, isOn: isOn)
        }
    }
}

extension FormRow {
    /// Figma's Pop-Up row: "Hidden-mode trial" with "15 seconds".
    public init<Value: Hashable>(
        _ title: String,
        help: String? = nil,
        selection: Binding<Value>,
        options: [FormRowPopUp<Value>.Option]
    ) where Control == FormRowPopUp<Value> {
        self.init(title, help: help) {
            FormRowPopUp(title, selection: selection, options: options)
        }
    }
}

extension FormRow where Control == FormRowValue {
    /// Figma's Value row: a setting shown, not changed, here ("Open the panel" with ⌃⌥R).
    public init(_ title: String, help: String? = nil, value: String) {
        self.init(title, help: help) {
            FormRowValue(value, showsChevron: false)
        }
    }

    /// Figma's Chevron row: the value and a chevron, and the whole row opens something
    /// ("JSON output" with docs/json.md).
    public init(_ title: String, help: String? = nil, value: String, action: @escaping () -> Void) {
        self.init(title, help: help) {
            FormRowValue(value, showsChevron: true)
        }
        self.action = action
    }
}

extension FormRow where Control == FormRowButton {
    /// Figma's Button row: "Install…", "Open…", "Copy Report".
    public init(_ title: String, help: String? = nil, buttonTitle: String, action: @escaping () -> Void) {
        self.init(title, help: help) {
            FormRowButton(buttonTitle, action: action)
        }
    }
}

/// The switch of a form row at Figma's size, 38.88 × 17.28: the kit's switch (the regular
/// switch since macOS 26, 54 × 24) at 72 %. Older designs' regular switch is scaled to fit
/// the same height.
public struct FormRowSwitch: View {
    public var title: String
    @Binding public var isOn: Bool

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    public var body: some View {
        let fit = Self.fit
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.regular)
            .scaleEffect(fit.scale)
            .frame(width: fit.size.width, height: fit.size.height)
    }

    /// The regular switch of the design in use, scaled into Figma's box.
    @MainActor private static let fit = FormSwitchFit(native: NSSwitch().intrinsicContentSize)
}

/// How much to scale a native switch so it fills Figma's switch box without growing past it.
struct FormSwitchFit: Equatable {
    /// Figma's switch: the macOS 27 kit's 54 × 24 switch at 72 %.
    static let box = CGSize(width: 54 * WindowMetrics.Form.switchScale, height: 24 * WindowMetrics.Form.switchScale)
    /// The regular switch before macOS 26's design.
    static let classicSwitch = CGSize(width: 38, height: 22)

    var scale: CGFloat
    /// The scaled switch, which the row lays out.
    var size: CGSize

    init(native: CGSize) {
        let switchSize = native.width > 0 && native.height > 0 ? native : Self.classicSwitch
        scale = min(Self.box.width / switchSize.width, Self.box.height / switchSize.height, 1)
        size = CGSize(width: switchSize.width * scale, height: switchSize.height * scale)
    }
}

/// The pop-up button of a form row: "15 seconds", "ProMotion", "Ask me".
public struct FormRowPopUp<Value: Hashable>: View {
    /// One choice in the menu.
    public struct Option: Identifiable {
        public var value: Value
        public var title: String

        public var id: Value { value }

        public init(_ value: Value, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    public var title: String
    @Binding public var selection: Value
    public var options: [Option]

    public init(_ title: String, selection: Binding<Value>, options: [Option]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// A value shown at the end of a form row, with a chevron when the row opens something.
public struct FormRowValue: View {
    public var text: String
    public var showsChevron: Bool

    public init(_ text: String, showsChevron: Bool) {
        self.text = text
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: WindowMetrics.Form.spacing) {
            Text(text)
                .textStyle(.body)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(1)
            if showsChevron {
                Image(symbol: .chevronRight)
                    .font(.system(size: WindowMetrics.Form.chevronPointSize, weight: .semibold))
                    .foregroundStyle(Palette.labelTertiary)
                    .frame(width: WindowMetrics.Form.chevronFrame, height: WindowMetrics.Form.chevronFrame)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The push button at the end of a form row.
public struct FormRowButton: View {
    public var title: String
    public var action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .fixedSize()
    }
}
