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
