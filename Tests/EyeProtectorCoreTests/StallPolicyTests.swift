import Foundation
import Testing

@testable import EyeProtectorCore

private let second: UInt64 = 1_000_000_000

@Test("Silence beyond the limit is a stall")
func stallBeyondLimit() {
    let policy = StallPolicy(limit: 10)
    #expect(policy.hasStalled(lastBeat: second, now: second + 11 * second))
}

@Test("Silence inside the limit is ordinary slowness")
func noStallInsideLimit() {
    let policy = StallPolicy(limit: 10)
    #expect(!policy.hasStalled(lastBeat: second, now: second + 9 * second))
}

@Test("Exactly the limit is not yet a stall")
func limitBoundaryIsNotAStall() {
    let policy = StallPolicy(limit: 10)
    #expect(!policy.hasStalled(lastBeat: second, now: second + 10 * second))
}

@Test("No heartbeat yet is startup, not a stall")
func noHeartbeatIsNotAStall() {
    let policy = StallPolicy(limit: 10)
    #expect(!policy.hasStalled(lastBeat: 0, now: 999 * second))
}

@Test("A zero limit disables the policy entirely")
func zeroLimitIsInert() {
    let policy = StallPolicy(limit: 0)
    #expect(!policy.hasStalled(lastBeat: second, now: 9_999 * second))
}

@Test("A negative limit is treated as disabled, not as always-stalled")
func negativeLimitIsInert() {
    let policy = StallPolicy(limit: -5)
    #expect(!policy.hasStalled(lastBeat: second, now: 9_999 * second))
}

/// A monotonic clock should never go backwards, but if it did, the wrong
/// answer here would be killing the app.
@Test("A clock that appears to go backwards is not a stall")
func backwardsClockIsNotAStall() {
    let policy = StallPolicy(limit: 10)
    #expect(!policy.hasStalled(lastBeat: 500 * second, now: second))
}
