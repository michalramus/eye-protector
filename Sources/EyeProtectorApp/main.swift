import AppKit

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// No Dock icon: Eye Protector lives in the menu bar and the Overlay.
application.setActivationPolicy(.accessory)
application.run()
