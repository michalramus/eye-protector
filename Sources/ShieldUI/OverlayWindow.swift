import AppKit

/// A borderless window that covers one Display and is present on every Space,
/// including the Spaces that fullscreen apps create for themselves.
public final class OverlayWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(screen: NSScreen) {
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
