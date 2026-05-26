import AppKit
import GleanKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // agent app: no dock icon, never frontmost
app.run()
