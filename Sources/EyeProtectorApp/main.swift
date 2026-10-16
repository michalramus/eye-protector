import AppKit

let spikeSeconds = ProcessInfo.processInfo.environment["EYE_PROTECTOR_SPIKE_SECONDS"]
    .flatMap(Double.init) ?? 20

let application = NSApplication.shared
let appDelegate = SpikeDelegate(duration: spikeSeconds)
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
