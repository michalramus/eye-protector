import AppKit

/// Lockout: the condition of being unable to reach any other application.
///
/// Which holes are left open is decided by `SafetyNets`, not here — see
/// ADR 0004. The dead-man's switch that guarantees Lockout ends lives in the
/// cycle adapter, so that a wedged engine cannot keep the machine captive.
@MainActor
public final class Lockout {
    private let nets: SafetyNets
    private(set) var isEngaged = false
    private var watchdog: (any NSObjectProtocol)?

    public init(nets: SafetyNets = .lenient) {
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

    public func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        MainThreadWatchdog.shared.setArmed(true)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = options
        redrawCursor()

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
                self.redrawCursor()
            }
        }
    }

    /// Another app's cursor can stay drawn by the window server after we cover
    /// it: setting ours is not enough to make the server drop an image it was
    /// already showing, but hiding and showing the cursor is. That pair looks
    /// like dead code and is not.
    ///
    /// `hide` and `unhide` are counted, so they stay strictly paired inside
    /// this one synchronous block; splitting them across a notification would
    /// leave the cursor hidden whenever the second half never ran.
    private func redrawCursor() {
        NSCursor.arrow.set()
        NSCursor.hide()
        NSCursor.unhide()
    }

    public func disengage() {
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
