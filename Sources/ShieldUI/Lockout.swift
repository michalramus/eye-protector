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
    private let yieldingTo: Set<String>
    private var watchdog: (any NSObjectProtocol)?
    private var activations: (any NSObjectProtocol)?
    private var lastActivated: String?

    /// `yieldingTo` names apps (by bundle identifier) that outrank this
    /// Lockout. While one of them is frontmost we leave activation alone:
    /// two Lockouts that each take activation back from the other flicker
    /// forever, and the windows share a level so neither wins visually.
    public init(nets: SafetyNets = .lenient, yieldingTo: Set<String> = []) {
        self.nets = nets
        self.yieldingTo = yieldingTo
    }

    /// Pure so it can be tested without AppKit.
    static func shouldYield(frontmost: String?, lastActivated: String?, to set: Set<String>) -> Bool {
        [frontmost, lastActivated].contains { $0.map(set.contains) ?? false }
    }

    /// `frontmostApplication` can still name the previous app while
    /// `didResignActive` is being delivered, so it is not enough alone.
    /// `lastActivated` is kept current by `didActivateApplication`, and either
    /// one naming a higher-priority app is reason to stand down.
    private var shouldYieldNow: Bool {
        Lockout.shouldYield(
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            lastActivated: lastActivated,
            to: yieldingTo
        )
    }

    private func takeActivation() {
        NSApp.activate(ignoringOtherApps: true)
        // Our windows may have been ordered in over a higher-priority
        // shield's; bring them back on top so it re-covers them.
        for window in NSApp.windows where window.isVisible {
            window.orderFrontRegardless()
        }
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
        lastActivated = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Still present and set state when yielding; only the activation
        // grab is skipped, so we do not steal focus from the higher shield.
        if !shouldYieldNow {
            takeActivation()
        }
        NSApp.presentationOptions = options
        redrawCursor()

        if !yieldingTo.isEmpty {
            activations = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.lastActivated = app?.bundleIdentifier }
            }
        }

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
                guard let self, self.isEngaged, !self.shouldYieldNow else { return }
                self.takeActivation()
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
        if let activations {
            NSWorkspace.shared.notificationCenter.removeObserver(activations)
        }
        activations = nil
        NSApp.presentationOptions = []
    }
}
