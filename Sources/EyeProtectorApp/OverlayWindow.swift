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

        joinEveryScreenLayer()
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
    }
}
