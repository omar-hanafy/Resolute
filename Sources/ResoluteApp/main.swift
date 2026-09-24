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
