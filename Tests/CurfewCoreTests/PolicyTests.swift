import Foundation
import Testing

@testable import CurfewCore

// MARK: - Fixtures

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let policy = CurfewPolicy(schedule: Schedule(config: .default, calendar: calendar))

// 2026-11-16 is a Monday, 11-17 Tuesday, 11-21 Saturday.
private let free = date(2026, 11, 17, 12, 0)
private let night = date(2026, 11, 17, 22, 0)
private let weekend = date(2026, 11, 21, 14, 0)

private func state(
    unlockedUntil: Date? = nil,
    lastSeen: Date,
    clockRolledBack: Bool = false
) -> CurfewState {
    CurfewState(unlockedUntil: unlockedUntil, lastSeen: lastSeen, clockRolledBack: clockRolledBack)
}

// MARK: - Deciding

@Test("With no grace, a night instant is shielded as night")
func nightWithoutGrace() {
    #expect(policy.decide(state(lastSeen: night), now: night) == .shielded(.schedule(.night)))
}

@Test("With no grace, a weekend instant is shielded as weekend")
func weekendWithoutGrace() {
    #expect(policy.decide(state(lastSeen: weekend), now: weekend) == .shielded(.schedule(.weekend)))
}

@Test("Grace with more than the warning lead left is clear until it runs out")
func graceWithTimeLeft() {
    let until = night.addingTimeInterval(600)
    let decision = policy.decide(state(unlockedUntil: until, lastSeen: night), now: night)
    #expect(decision == .clear(nextRise: until))
}

@Test("Grace inside the warning lead warns that the shield rises when it ends")
func graceInsideWarningLead() {
    let until = night.addingTimeInterval(60)
    let decision = policy.decide(state(unlockedUntil: until, lastSeen: night), now: night)
    #expect(decision == .warning(raisesAt: until))
}

@Test("Expired grace is shielded again")
func expiredGrace() {
    let until = night.addingTimeInterval(-1)
    let decision = policy.decide(state(unlockedUntil: until, lastSeen: night), now: night)
    #expect(decision == .shielded(.schedule(.night)))
}

@Test("Well before the rise a free instant is clear until it")
func freeWellBeforeRise() {
    let decision = policy.decide(state(lastSeen: free), now: free)
    #expect(decision == .clear(nextRise: date(2026, 11, 17, 20, 0)))
}

@Test("Inside the warning lead a free instant warns of the rise")
func freeInsideWarningLead() {
    let now = date(2026, 11, 17, 19, 59)
    let decision = policy.decide(state(lastSeen: now), now: now)
    #expect(decision == .warning(raisesAt: date(2026, 11, 17, 20, 0)))
}

// MARK: - Unlocking

@Test("Unlocking at night grants exactly the night grace and counts the unlock")
func unlockAtNight() {
    let unlocked = policy.unlocked(state(lastSeen: night), now: night)
    #expect(unlocked.unlockedUntil == night.addingTimeInterval(20 * 60))
    #expect(unlocked.unlockCount == 1)
}

@Test("Unlocking at the weekend grants exactly the weekend grace and counts the unlock")
func unlockAtWeekend() {
    let unlocked = policy.unlocked(state(lastSeen: weekend), now: weekend)
    #expect(unlocked.unlockedUntil == weekend.addingTimeInterval(30 * 60))
    #expect(unlocked.unlockCount == 1)
}

@Test("Unlock counts accumulate")
func unlockCountAccumulates() {
    let first = policy.unlocked(state(lastSeen: night), now: night)
    let second = policy.unlocked(first, now: night.addingTimeInterval(30 * 60))
    #expect(second.unlockCount == 2)
}

// MARK: - Clock tampering

@Test("A clock wound back past the tolerance sets the flag, drops grace and keeps lastSeen")
func clockRollback() {
    let seen = date(2026, 11, 17, 22, 0)
    let before = state(unlockedUntil: seen.addingTimeInterval(600), lastSeen: seen)
    let now = seen.addingTimeInterval(-(CurfewPolicy.clockTolerance + 1))

    let after = policy.observing(before, now: now)

    #expect(after.clockRolledBack)
    #expect(after.unlockedUntil == nil)
    #expect(after.lastSeen == seen)
}

@Test("A rolled-back clock is shielded even at a free instant")
func rollbackShieldsFreeInstant() {
    let seen = date(2026, 11, 17, 22, 0)
    // Wound back ten hours into the free afternoon.
    let now = date(2026, 11, 17, 12, 0)
    let after = policy.observing(state(lastSeen: seen), now: now)
    #expect(policy.decide(after, now: now) == .shielded(.clockRolledBack))
}

@Test("A backwards jump within the tolerance is ignored and lastSeen does not move back")
func smallBackwardsJump() {
    let seen = date(2026, 11, 17, 22, 0)
    let before = state(unlockedUntil: seen.addingTimeInterval(600), lastSeen: seen)
    let now = seen.addingTimeInterval(-(CurfewPolicy.clockTolerance - 1))

    let after = policy.observing(before, now: now)

    #expect(!after.clockRolledBack)
    #expect(after.unlockedUntil == before.unlockedUntil)
    #expect(after.lastSeen == seen)
}

@Test("Once the clock catches up with lastSeen the flag clears and decisions resume")
func clockCatchesUp() {
    let seen = date(2026, 11, 17, 22, 0)
    let rolled = state(lastSeen: seen, clockRolledBack: true)

    // Still behind: stays flagged.
    let behind = policy.observing(rolled, now: seen.addingTimeInterval(-60))
    #expect(behind.clockRolledBack)

    let caughtUp = policy.observing(rolled, now: seen)
    #expect(!caughtUp.clockRolledBack)
    #expect(policy.decide(caughtUp, now: seen) == .shielded(.schedule(.night)))
}

@Test("lastSeen only ever moves forward")
func lastSeenMovesForward() {
    let seen = date(2026, 11, 17, 22, 0)
    let later = seen.addingTimeInterval(60)
    #expect(policy.observing(state(lastSeen: seen), now: later).lastSeen == later)
}

// MARK: - Fresh state

@Test("A fresh state has no grace, so a blocked instant is shielded")
func freshStateFailsClosed() {
    let fresh = CurfewPolicy.freshState(now: night)
    #expect(fresh.unlockedUntil == nil)
    #expect(fresh.lastSeen == night)
    #expect(policy.decide(fresh, now: night) == .shielded(.schedule(.night)))
    #expect(policy.decide(CurfewPolicy.freshState(now: weekend), now: weekend) == .shielded(.schedule(.weekend)))
}
