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

        // Without mouse-moved events AppKit's cursor-update machinery never
        // runs for this window, so nothing re-asserts a cursor as the pointer
        // moves and whatever another app left behind stays on screen.
        acceptsMouseMovedEvents = true
    }

    /// Puts `content` inside a container that owns the cursor, rather than
    /// making it the window's content view directly.
    ///
    /// The Overlay covers another app's window, and that app may have set a
    /// cursor programmatically (a pointing hand over a link). Nothing of ours
    /// ever asserts one, so the stale image stays drawn while the live pointer
    /// moves separately: two cursors. A cursor rect on the container makes
    /// AppKit keep setting the arrow over the black area, while a text field's
    /// own rect, being deeper in the view tree, still wins over the field.
    public func install(content: NSView) {
        let container = CursorOwningView(frame: contentLayoutRect)
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        contentView = container
    }
}

private final class CursorOwningView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
