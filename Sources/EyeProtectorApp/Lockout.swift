import AppKit

/// Lockout: the condition of being unable to reach any other application.
///
/// Which holes are left open is decided by `SafetyNets`, not here — see
/// ADR 0004. The dead-man's switch that guarantees Lockout ends lives in the
/// cycle adapter, so that a wedged engine cannot keep the machine captive.
@MainActor
final class Lockout {
    private let nets: SafetyNets
    private(set) var isEngaged = false
    private var watchdog: (any NSObjectProtocol)?

    init(nets: SafetyNets = .lenient) {
        self.nets = nets
    }

    var options: NSApplication.PresentationOptions {
        var options: NSApplication.PresentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableHideApplication,
            .disableAppleMenu,
        ]
        if !nets.forceQuitEnabled {
            options.insert(.disableForceQuit)
        }
        if !nets.sessionTerminationEnabled {
            options.insert(.disableSessionTermination)
        }
        return options
    }

    func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        MainThreadWatchdog.shared.setArmed(true)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = options

        // Presentation options only apply while this app is active, so losing
        // activation silently ends Lockout however intact the options look.
        // Take activation straight back; do not try to infer from
        // `presentationOptions` whether that is needed, because the property
        // keeps its assigned value even when it has stopped having an effect.
        watchdog = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEngaged else { return }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.presentationOptions = self.options
            }
        }
    }

    func disengage() {
        guard isEngaged else { return }
        isEngaged = false
        MainThreadWatchdog.shared.setArmed(false)
        if let watchdog {
            NotificationCenter.default.removeObserver(watchdog)
        }
        watchdog = nil
        NSApp.presentationOptions = []
    }
}
