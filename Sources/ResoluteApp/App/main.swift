import AppKit
import ResoluteKit

if let status = Diagnostics.run(CommandLine.arguments) {
    exit(status)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
