import AppKit

/// Step 2 of the build order: prove that Lockout actually holds before
/// anything else is built on top of it.
///
/// Shows the Overlay on every Display for a fixed number of seconds, then
/// quits unconditionally. Try, while it is up: the three-finger Space swipe,
/// Mission Control, Cmd-Tab, clicking a second Display, and Cmd-Q.
@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    private let duration: TimeInterval
    private let lockout = Lockout()
    private var windows: [OverlayWindow] = []
    private var labels: [NSTextField] = []
    private var deadline = Date()
    private var ticker: Timer?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        deadline = Date().addingTimeInterval(duration)
        rebuildWindows()
        lockout.engage()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.rebuildWindows() }
        }
    }

    /// Displays attached or removed mid-Break rebuild the Overlays, so a newly
    /// connected screen never shows a gap.
    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        labels = []

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            let caption = NSTextField(labelWithString:
                "Lockout spike — try swiping Spaces, Mission Control, Cmd-Tab")
            caption.font = .systemFont(ofSize: 15)
            caption.textColor = .secondaryLabelColor
            caption.alignment = .center
            caption.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(label)
            content.addSubview(caption)
            window.contentView = content

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                caption.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                caption.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            ])

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            labels.append(label)
        }
    }

    private func tick() {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return finish() }
        let text = String(format: "%.0f", remaining.rounded(.up))
        labels.forEach { $0.stringValue = text }
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        lockout.disengage()
        windows.forEach { $0.orderOut(nil) }
        NSApp.terminate(nil)
    }
}
