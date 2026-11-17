import AppKit
import ShieldUI
import SwiftUI

/// One black window per Display, plus Lockout, plus the warning panel.
///
/// Built up front and kept, like Eye Protector's Overlay: a window that is
/// created at the moment the shield rises is a window that is not yet on the
/// Space the user is looking at.
///
/// Lockout here is `SafetyNets.curfew`, a deliberate choice by the user of
/// this app, unlike Eye Protector's lenient one: with the shield up there is
/// no app switching and no Force Quit, but logout, restart and shutdown from
/// the Apple menu still work. `mainThreadStallLimit` still applies. The ways
/// out are typing the string, restart or logout from the Apple menu, ssh,
/// a safe-mode boot and the main-thread watchdog.
///
/// `sizingOptions = []` is load-bearing, not tidiness — without it the SwiftUI
/// content pushes a minimum size onto the window and a full-screen shield
/// grows past the screen, leaving the panel above the top edge and a black
/// rectangle where the challenge should be.
@MainActor
final class ShieldController {
    let model = ShieldModel()

    private var windows: [OverlayWindow] = []
    private var warningPanels: [NSPanel] = []
    private var builtFor: [String] = []
    /// One place for the choice, because the watchdog's stall limit is
    /// part of the same bargain and reading it from a different set of
    /// nets than Lockout engages is how a safeguard quietly stops
    /// matching the lockout it is meant to end.
    static let nets: SafetyNets = .curfew

    private let lockout = Lockout(nets: ShieldController.nets)
    private let warning = WarningModel()
    private var screenObserver: (any NSObjectProtocol)?

    private(set) var isPresented = false
    private(set) var isWarning = false

    @MainActor
    final class WarningModel: ObservableObject {
        @Published var remaining: TimeInterval = 0
    }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// Idempotent on purpose: the agent polls the daemon once a second and
    /// calls this every time the answer is "shield up". Re-keying the window
    /// at 1 Hz would fight the text field for the focus.
    func present() {
        guard !isPresented else { return }
        rebuildIfNeeded()
        for window in windows {
            window.orderFrontRegardless()
        }
        windows.first?.makeKey()
        lockout.engage()
        isPresented = true
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        lockout.disengage()
        for window in windows {
            window.orderOut(nil)
        }
    }

    func showWarning(remaining: TimeInterval) {
        rebuildIfNeeded()
        warning.remaining = remaining
        guard !isWarning else { return }
        isWarning = true
        for panel in warningPanels {
            panel.orderFrontRegardless()
        }
    }

    func hideWarning() {
        guard isWarning else { return }
        isWarning = false
        for panel in warningPanels {
            panel.orderOut(nil)
        }
    }

    /// A Display attached or removed rebuilds everything, so a newly
    /// connected screen never shows a gap in the shield.
    private func screensChanged() {
        let wasPresented = isPresented
        let wasWarning = isWarning
        let remaining = warning.remaining

        isPresented = false
        isWarning = false
        builtFor = []

        if wasPresented { present() }
        if wasWarning { showWarning(remaining: remaining) }
    }

    private func rebuildIfNeeded() {
        guard builtFor != ScreenArrangement.signature else { return }

        for window in windows { window.orderOut(nil) }
        for panel in warningPanels { panel.orderOut(nil) }
        builtFor = ScreenArrangement.signature

        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            let host = NSHostingView(rootView: ShieldView(model: model))
            host.sizingOptions = []
            host.frame = window.contentLayoutRect
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            return window
        }

        warningPanels = NSScreen.screens.map { screen in
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.joinEveryScreenLayer()
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true

            let host = NSHostingView(
                rootView: WarningHost(model: warning)
            )
            host.frame.size = host.fittingSize
            panel.contentView = host
            panel.setContentSize(host.fittingSize)

            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - host.fittingSize.width - 20,
                    y: visible.maxY - host.fittingSize.height - 20
                )
            )
            return panel
        }
    }

    private struct WarningHost: View {
        @ObservedObject var model: WarningModel

        var body: some View {
            CurfewWarningView(remaining: model.remaining)
        }
    }
}
