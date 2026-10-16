import AppKit
import SwiftUI
import EyeProtectorCore

/// The menu bar is only actually visible during a Session — Lockout hides it
/// while the Overlay is up — so this is the Session-time face of the app:
/// time remaining, today's tallies, and the way to settings.
@MainActor
final class MenuBarController {
    private let item: NSStatusItem
    private let popover = NSPopover()

    init(settings: SettingsModel) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "eye",
            accessibilityDescription: "Eye Protector"
        )
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(model: settings)
        )
    }

    func update(state: CycleState) {
        item.button?.title = Self.title(for: state)
    }

    private static func title(for state: CycleState) -> String {
        switch state {
        case .working(let endsAt), .warning(let endsAt):
            let remaining = max(0, endsAt.timeIntervalSinceNow)
            return String(
                format: " %d:%02d",
                Int(remaining) / 60,
                Int(remaining) % 60
            )
        case .idle, .breaking:
            // Hidden behind Lockout anyway, but keep it honest if it shows.
            return ""
        }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
