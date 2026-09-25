import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "Choose available resolutions and refresh rates from the menu bar, including validated modes macOS hides.\nBuilt for Apple silicon. A ground-up successor to RDM.",
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
