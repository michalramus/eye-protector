import AppKit

extension NSWindow {
    /// The window configuration both the Overlay and the Warning depend on:
    /// above everything the window server will allow, and present on every
    /// Space — including the ones fullscreen apps create for themselves.
    ///
    /// `canJoinAllSpaces` is load-bearing, not decoration. ADR 0003 records
    /// that the Space swipe is *not* blocked; what makes it pointless is the
    /// window already being on the Space the user arrives at.
    func joinEveryScreenLayer() {
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

/// Identity of the current Display arrangement.
///
/// Deliberately not a count: swapping one Display for another leaves the count
/// unchanged while the frames move, which would strand windows on stale
/// geometry and leave part of a screen uncovered.
enum ScreenArrangement {
    static var signature: [String] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
            return "\(number?.intValue ?? -1)@\(NSStringFromRect(screen.frame))"
        }
    }
}
