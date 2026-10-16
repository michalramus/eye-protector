import Foundation

/// When a run of silence from the main thread counts as a stall rather than
/// ordinary slowness.
///
/// Pure, and here rather than in the adapter, so the decision can be tested
/// without a thread, a clock or a process to kill — the acting on it cannot
/// be, since the only available action is ending the process.
public struct StallPolicy: Equatable, Sendable {
    /// Monotonic nanoseconds of silence tolerated before declaring a stall.
    public let limitNanoseconds: UInt64

    public init(limit: TimeInterval) {
        limitNanoseconds = limit > 0 ? UInt64(limit * 1_000_000_000) : 0
    }

    /// For callers that already hold the limit in the units the monotonic
    /// clock reports, so it need not round-trip through `TimeInterval`.
    public init(limitNanoseconds: UInt64) {
        self.limitNanoseconds = limitNanoseconds
    }

    /// `lastBeat` of 0 means the main thread has not checked in yet, which is
    /// startup rather than a stall; a limit of 0 disables the policy. Both
    /// return false so that a misconfigured watchdog is inert rather than
    /// trigger-happy — the cost of a false positive here is killing the app
    /// out from under a working user.
    public func hasStalled(lastBeat: UInt64, now: UInt64) -> Bool {
        guard limitNanoseconds > 0, lastBeat > 0, now > lastBeat else { return false }
        return now - lastBeat > limitNanoseconds
    }
}
