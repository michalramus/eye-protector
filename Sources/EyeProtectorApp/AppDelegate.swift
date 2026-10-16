import AppKit
import EyeProtectorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private lazy var cycle = CycleController(overlay: overlay)

    func applicationDidFinishLaunching(_ notification: Notification) {
        cycle.start(trigger: Self.launchTrigger(notification))
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
