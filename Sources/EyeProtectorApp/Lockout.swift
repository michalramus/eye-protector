import AppKit

/// Lockout: the condition of being unable to reach any other application.
///
/// Force Quit is deliberately left enabled — see ADR 0004. The dead-man's
/// switch that guarantees Lockout lifts lives in the cycle adapter, not here,
/// so that a wedged engine cannot keep the machine captive.
@MainActor
final class Lockout {
    static let options: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableProcessSwitching,
        .disableSessionTermination,
        .disableHideApplication,
        .disableAppleMenu,
    ]

    private(set) var isEngaged = false
    private var watchdog: Any?

    func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = Self.options

        // If anything manages to steal focus, take it straight back: losing
        // activation would silently drop the presentation options.
        watchdog = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard NSApp.presentationOptions != Self.options else { return }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.presentationOptions = Self.options
            }
        }
    }

    func disengage() {
        guard isEngaged else { return }
        isEngaged = false
        if let watchdog {
            NotificationCenter.default.removeObserver(watchdog)
        }
        watchdog = nil
        NSApp.presentationOptions = []
    }
}
