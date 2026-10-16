import AppKit

/// Watches for the Escape key being held down for long enough to abandon a
/// Break.
///
/// A local monitor is enough — never a `CGEventTap` — because Lockout keeps
/// this app frontmost for the whole Break, so the key events arrive here
/// anyway. ADR 0003 covers why we avoid event taps and the Accessibility
/// permission they drag in.
@MainActor
final class EscapeMonitor {
    private static let escapeKeyCode: UInt16 = 53

    private let holdDuration: TimeInterval
    private var monitor: Any?
    private var pressStartedAt: Date?
    private var progressTimer: Timer?

    /// Reports hold progress, 0...1, so the Overlay can draw it.
    var onProgress: (Double) -> Void = { _ in }
    /// Fired once when the hold completes.
    var onComplete: () -> Void = {}

    init(holdDuration: TimeInterval = 3) {
        self.holdDuration = holdDuration
    }

    /// Only armed during a Break: outside one there is nothing to escape, and
    /// Escape should behave like an ordinary key.
    func arm() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // Read the event's values before hopping isolation: `NSEvent`
            // itself is not `Sendable` and cannot cross the boundary.
            let keyCode = event.keyCode
            let isKeyDown = event.type == .keyDown
            guard keyCode == Self.escapeKeyCode else { return event }

            MainActor.assumeIsolated {
                if isKeyDown {
                    self.beginHold()
                } else {
                    self.cancelHold()
                }
            }
            // Swallowed: Escape during a Break belongs to us alone.
            return nil
        }
    }

    func disarm() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        cancelHold()
    }

    private func beginHold() {
        // keyDown repeats while held; only the first one starts the clock.
        guard pressStartedAt == nil else { return }
        pressStartedAt = Date()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
    }

    private func cancelHold() {
        pressStartedAt = nil
        progressTimer?.invalidate()
        progressTimer = nil
        onProgress(0)
    }

    private func tick() {
        guard let startedAt = pressStartedAt else { return }
        let progress = Date().timeIntervalSince(startedAt) / holdDuration
        onProgress(min(1, progress))
        guard progress >= 1 else { return }
        cancelHold()
        onComplete()
    }
}
