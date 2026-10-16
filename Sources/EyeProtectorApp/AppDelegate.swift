import AppKit
import EyeProtectorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let overlay = OverlayController()
    private lazy var settings = SettingsModel(config: store.config)
    private lazy var cycle = CycleController(overlay: overlay, store: store)
    private lazy var menuBar = MenuBarController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onConfigChange = { [weak self] config in
            self?.cycle.config = config
        }
        settings.onQuit = { NSApp.terminate(nil) }
        overlay.model.settings = settings

        cycle.onChange = { [weak self] in self?.refresh() }
        _ = menuBar

        cycle.start(trigger: Self.launchTrigger(notification))
        wedgeMainThreadIfAsked()
    }

    /// Fault injection for the safety-net check in `docs/manual-checks.md`.
    ///
    /// A watchdog whose firing has never been observed is a guess, and this is
    /// the one safeguard that cannot be exercised from a unit test: its only
    /// action is ending the process. Setting
    /// `EYE_PROTECTOR_WEDGE_AFTER=<seconds>` deliberately hangs the main
    /// thread so the kill can be watched happening. Never set in normal use.
    private func wedgeMainThreadIfAsked() {
        guard
            let value = ProcessInfo.processInfo.environment["EYE_PROTECTOR_WEDGE_AFTER"],
            let delay = Double(value)
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            FileHandle.standardError.write(
                Data("eye-protector: wedging the main thread on purpose\n".utf8)
            )
            while true {
                Thread.sleep(forTimeInterval: 60)
            }
        }
    }

    private func refresh() {
        menuBar.update(state: cycle.engine.state)
        settings.sync(config: cycle.engine.config, counters: cycle.engine.counters)
    }

    /// A login launch and a manual one behave identically — the user chose an
    /// Overlay at every login over a silent start — but the distinction is
    /// carried through so it can be acted on later without rework.
    private static func launchTrigger(_ notification: Notification) -> LaunchTrigger {
        let wasDefault = notification
            .userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        return wasDefault == false ? .login : .user
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
