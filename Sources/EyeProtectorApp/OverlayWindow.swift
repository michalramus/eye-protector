import AppKit

/// A borderless window that covers one Display and is present on every Space,
/// including the Spaces that fullscreen apps create for themselves.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)

        // Above everything the window server will let us sit above, fullscreen
        // apps included.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        // `canJoinAllSpaces` is what makes a Space swipe land on the Overlay
        // rather than escape it; `fullScreenAuxiliary` lets it draw over a
        // fullscreen app without being given a Space of its own.
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}
