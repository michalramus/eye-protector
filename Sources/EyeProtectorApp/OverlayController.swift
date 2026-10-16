import AppKit
import SwiftUI

/// Owns one `OverlayWindow` per Display, all showing the same model.
///
/// The spike settled that a Space swipe is not blocked — it simply lands on a
/// Space that already has the Overlay. That only holds if every window exists
/// *before* Lockout engages, so windows are built up front rather than lazily.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    private var windows: [OverlayWindow] = []
    private var builtFor: [String] = []
    private(set) var isPresented = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.screensChanged() }
        }
    }

    func present() {
        if builtFor != ScreenArrangement.signature {
            rebuild()
        }
        for window in windows {
            window.orderFrontRegardless()
        }
        windows.first?.makeKey()
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        for window in windows {
            window.orderOut(nil)
        }
    }

    /// A Display attached or removed mid-Break rebuilds the Overlays, so a
    /// newly connected screen never shows a gap.
    private func screensChanged() {
        // While hidden there is nothing to fix up: the next `present()` sees a
        // stale signature and rebuilds before showing anything.
        guard isPresented else { return }
        present()
    }

    private func rebuild() {
        for window in windows {
            window.orderOut(nil)
        }
        builtFor = ScreenArrangement.signature
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            let host = NSHostingView(rootView: OverlayView(model: model))
            host.frame = window.contentLayoutRect
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            return window
        }
    }
}
