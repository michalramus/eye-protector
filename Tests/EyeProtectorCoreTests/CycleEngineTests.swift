import Foundation
import Testing

@testable import EyeProtectorCore

// MARK: - Fixtures

/// A fixed timezone so midnight is a known instant rather than wherever the
/// test happens to run.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// 2025-10-09, mid-morning UTC: far enough from midnight that a default
/// Session cannot roll the day by accident.
private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

private func engine(
    config: Config = .default,
    escapePolicy: EscapePolicy = .unlimited,
    at now: Date = t0
) -> CycleEngine {
    CycleEngine(now: now, config: config, escapePolicy: escapePolicy, calendar: utc)
}

/// Launches and starts a Session, returning an engine mid-Session.
private func working(
    config: Config = .default,
    escapePolicy: EscapePolicy = .unlimited
) -> CycleEngine {
    var engine = engine(config: config, escapePolicy: escapePolicy)
    _ = engine.handle(.appLaunched(.user), at: t0)
    _ = engine.handle(.startPressed, at: t0)
    return engine
}

extension Date {
    fileprivate func plus(_ seconds: TimeInterval) -> Date {
        addingTimeInterval(seconds)
    }
}

// MARK: - Launch

@Test("Launching shows the Overlay with Lockout engaged")
func launchPresentsLockedOverlay() {
    var engine = engine()
    let effects = engine.handle(.appLaunched(.user), at: t0)

    #expect(engine.state == .idle)
    #expect(effects == [.presentOverlay])
}

@Test("A login launch is treated exactly like a manual one")
func loginLaunchAlsoLocks() {
    var engine = engine()
    let effects = engine.handle(.appLaunched(.login), at: t0)

    #expect(engine.state == .idle)
    #expect(effects == [.presentOverlay])
}

// MARK: - Starting a Session

@Test("Start dismisses the Overlay and begins a Session")
func startBeginsSession() {
    var engine = engine()
    _ = engine.handle(.appLaunched(.user), at: t0)
    let effects = engine.handle(.startPressed, at: t0)

    #expect(engine.state == .session(endsAt: t0.plus(1800)))
    #expect(effects == [.dismissOverlay])
}

@Test("Start is ignored outside Idle")
func startIgnoredWhileWorking() {
    var engine = working()
    let before = engine.state
    let effects = engine.handle(.startPressed, at: t0.plus(60))

    #expect(engine.state == before)
    #expect(effects.isEmpty)
}

// MARK: - Warning

@Test("The Warning appears exactly one lead-time before the Session ends")
func warningFiresAtLeadTime() {
    var engine = working()

    #expect(engine.handle(.tick, at: t0.plus(1769)).isEmpty)
    #expect(engine.state == .session(endsAt: t0.plus(1800)))

    let effects = engine.handle(.tick, at: t0.plus(1770))
    #expect(engine.state == .warning(endsAt: t0.plus(1800)))
    #expect(effects == [.presentWarning])
}

@Test("No Warning when the user has turned it off")
func warningSuppressedWhenDisabled() {
    var engine = working(config: Config(warningEnabled: false))
    let effects = engine.handle(.tick, at: t0.plus(1799))

    #expect(engine.state == .session(endsAt: t0.plus(1800)))
    #expect(effects.isEmpty)
}

@Test("A Warning lead longer than the Session is clamped to the Session")
func warningLeadClampedToSessionLength() {
    let config = Config(sessionLength: 60, warningLead: 300)
    #expect(config.warningLead == 60)

    var engine = working(config: config)
    let effects = engine.handle(.tick, at: t0)

    // Lead == Session length, so the Warning is due the instant work begins.
    #expect(engine.state == .warning(endsAt: t0.plus(60)))
    #expect(effects == [.presentWarning])
}

// MARK: - Break

@Test("A finished Session counts, locks the screen and starts the Break")
func sessionEndBeginsBreak() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1770))
    let effects = engine.handle(.tick, at: t0.plus(1800))

    #expect(engine.state == .break(endsAt: t0.plus(1830), escapable: true))
    #expect(engine.counters.sessionsToday == 1)
    #expect(effects == [
        .dismissWarning,
        .presentOverlay,
        .persistCounters(engine.counters),
    ])
}

@Test("A finished Break returns to Idle with the Overlay still up")
func breakEndReturnsToIdle() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1800))
    let effects = engine.handle(.tick, at: t0.plus(1830))

    #expect(engine.state == .idle)
    #expect(effects == [.presentOverlay])
}

@Test("Break length below the Warning lead still runs a whole cycle")
func shortBreakRunsFullCycle() {
    let config = Config(sessionLength: 60, breakLength: 5, warningLead: 30)
    var engine = working(config: config)

    #expect(engine.handle(.tick, at: t0.plus(30)) == [.presentWarning])
    #expect(engine.handle(.tick, at: t0.plus(60)).contains(.presentOverlay))
    #expect(engine.state == .break(endsAt: t0.plus(65), escapable: true))

    _ = engine.handle(.tick, at: t0.plus(65))
    #expect(engine.state == .idle)
}

// MARK: - Escape

@Test("An Escape is counted and starts a fresh Session immediately")
func escapeStartsNewSession() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1800))

    let effects = engine.handle(.escapeCompleted, at: t0.plus(1810))

    #expect(engine.state == .session(endsAt: t0.plus(1810 + 1800)))
    #expect(engine.counters.escapesToday == 1)
    #expect(effects == [.dismissOverlay, .persistCounters(engine.counters)])
}

@Test("An Escape landing on the Break's final instant still counts")
func escapeAtFinalInstantOfBreak() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1800))

    // No tick has moved the engine to Idle yet, so the Break is still running.
    let effects = engine.handle(.escapeCompleted, at: t0.plus(1830))

    #expect(engine.state == .session(endsAt: t0.plus(1830 + 1800)))
    #expect(engine.counters.escapesToday == 1)
    #expect(effects.contains(.dismissOverlay))
}

@Test("Escape does nothing outside a Break")
func escapeIgnoredWhileWorking() {
    var engine = working()
    let effects = engine.handle(.escapeCompleted, at: t0.plus(60))

    #expect(engine.state == .session(endsAt: t0.plus(1800)))
    #expect(engine.counters.escapesToday == 0)
    #expect(effects.isEmpty)
}

@Test("A capping policy marks the Break inescapable and refuses the Escape")
func escapePolicyCanRefuse() {
    var engine = working(escapePolicy: .maxPerDay(0))
    _ = engine.handle(.tick, at: t0.plus(1800))

    #expect(engine.state == .break(endsAt: t0.plus(1830), escapable: false))

    let effects = engine.handle(.escapeCompleted, at: t0.plus(1810))
    #expect(engine.state == .break(endsAt: t0.plus(1830), escapable: false))
    #expect(engine.counters.escapesToday == 0)
    #expect(effects.isEmpty)
}

@Test("Escapes are unlimited by default")
func escapesUnlimitedByDefault() {
    var engine = working()
    var now = t0

    for round in 1...5 {
        now = now.plus(1800)
        _ = engine.handle(.tick, at: now)
        _ = engine.handle(.escapeCompleted, at: now)
        #expect(engine.counters.escapesToday == round)
    }
}

// MARK: - Sleep

@Test("Sleep pauses the Session and wake resumes the same remaining time")
func sleepPausesSession() {
    var engine = working()
    _ = engine.handle(.machineSlept, at: t0.plus(600))
    _ = engine.handle(.machineWoke, at: t0.plus(600 + 8 * 3600))

    // 20 minutes were left when the lid closed; 20 minutes are left now.
    #expect(engine.state == .session(endsAt: t0.plus(600 + 8 * 3600 + 1200)))
}

@Test("Sleep spanning the Session end does not fire the Break on wake")
func sleepSpanningSessionEnd() {
    var engine = working()
    _ = engine.handle(.machineSlept, at: t0.plus(600))
    let wake = t0.plus(600 + 7200)
    _ = engine.handle(.machineWoke, at: wake)

    let effects = engine.handle(.tick, at: wake)
    #expect(engine.state == .session(endsAt: wake.plus(1200)))
    #expect(effects.isEmpty)
}

@Test("Ticks arriving while asleep are ignored")
func ticksIgnoredWhileAsleep() {
    var engine = working()
    _ = engine.handle(.machineSlept, at: t0.plus(600))

    let effects = engine.handle(.tick, at: t0.plus(9999))
    #expect(engine.state == .session(endsAt: t0.plus(1800)))
    #expect(effects.isEmpty)
}

@Test("Sleep pauses a Break too, so closing the lid cannot skip the rest")
func sleepPausesBreak() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1800))
    _ = engine.handle(.machineSlept, at: t0.plus(1810))
    let wake = t0.plus(1810 + 3600)
    _ = engine.handle(.machineWoke, at: wake)

    #expect(engine.state == .break(endsAt: wake.plus(20), escapable: true))
    _ = engine.handle(.tick, at: wake)
    #expect(engine.state == .break(endsAt: wake.plus(20), escapable: true))
}

@Test("A second sleep before waking does not compound the shift")
func repeatedSleepIsIdempotent() {
    var engine = working()
    _ = engine.handle(.machineSlept, at: t0.plus(600))
    _ = engine.handle(.machineSlept, at: t0.plus(900))
    _ = engine.handle(.machineWoke, at: t0.plus(1200))

    // Paused at 600s with 1200s left, slept 600s.
    #expect(engine.state == .session(endsAt: t0.plus(2400)))
}

// MARK: - Settings changes

@Test("Shortening the Session mid-Session ends it straight away")
func shorteningSessionAppliesImmediately() {
    var engine = working()
    let effects = engine.handle(
        .settingsChanged(Config(sessionLength: 60)),
        at: t0.plus(300)
    )

    // The phase began at t0, so a 60s Session is already long over.
    #expect(engine.state == .break(endsAt: t0.plus(330), escapable: true))
    #expect(engine.counters.sessionsToday == 1)
    #expect(effects.contains(.presentOverlay))
}

@Test("Lengthening the Session during the Warning withdraws the Warning")
func lengtheningDuringWarningDismissesIt() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1770))
    #expect(engine.state == .warning(endsAt: t0.plus(1800)))

    let effects = engine.handle(
        .settingsChanged(Config(sessionLength: 3600)),
        at: t0.plus(1770)
    )

    #expect(engine.state == .session(endsAt: t0.plus(3600)))
    #expect(effects == [.dismissWarning])
}

@Test("A Break length change re-projects the running Break")
func breakLengthChangeAppliesToRunningBreak() {
    var engine = working()
    _ = engine.handle(.tick, at: t0.plus(1800))

    _ = engine.handle(.settingsChanged(Config(breakLength: 120)), at: t0.plus(1810))
    #expect(engine.state == .break(endsAt: t0.plus(1920), escapable: true))
}

@Test("Out-of-range settings are clamped rather than rejected")
func configClampsOutOfRangeValues() {
    let tooSmall = Config(sessionLength: 1, breakLength: 0)
    #expect(tooSmall.sessionLength == 60)
    #expect(tooSmall.breakLength == 5)

    let tooLarge = Config(sessionLength: 99 * 3600, breakLength: 99 * 3600)
    #expect(tooLarge.sessionLength == 180 * 60)
    #expect(tooLarge.breakLength == 600)

    #expect(Config(warningLead: -5).warningLead == 0)
}

// MARK: - Counters

@Test("Crossing local midnight mid-Session resets and persists the counters")
func midnightRollsCountersOver() {
    let dayStart = utc.startOfDay(for: t0)
    // An hour before midnight, so the Session completes on the old day and it
    // is the Break that straddles the boundary.
    let beforeMidnight = dayStart.plus(86_400 - 3600)

    var engine = engine(at: beforeMidnight)
    _ = engine.handle(.appLaunched(.user), at: beforeMidnight)
    _ = engine.handle(.startPressed, at: beforeMidnight)
    _ = engine.handle(.tick, at: beforeMidnight.plus(1800))
    #expect(engine.counters.sessionsToday == 1)

    let afterMidnight = dayStart.plus(86_400 + 5)
    var next = engine
    let effects = next.handle(.tick, at: afterMidnight)

    #expect(next.counters.sessionsToday == 0)
    #expect(next.counters.escapesToday == 0)
    #expect(next.counters.day == dayStart.plus(86_400))
    #expect(effects.contains(.persistCounters(next.counters)))
}

@Test("Counters are persisted only when they actually change")
func noPersistWhenCountersUnchanged() {
    var engine = working()
    let effects = engine.handle(.tick, at: t0.plus(60))

    #expect(!effects.contains { if case .persistCounters = $0 { true } else { false } })
}

// MARK: - Catching up

@Test("A very late tick still owes the user a full Break")
func lateTickStillTakesTheBreak() {
    var engine = working()
    // The Session was due to end at +1800 but no tick arrived until +4000:
    // the process was stalled, so the Overlay never appeared and the user kept
    // working. The Break is owed in full from now, not treated as time served.
    let effects = engine.handle(.tick, at: t0.plus(4000))

    #expect(engine.state == .break(endsAt: t0.plus(4030), escapable: true))
    #expect(engine.counters.sessionsToday == 1)
    #expect(effects.contains(.presentOverlay))

    _ = engine.handle(.tick, at: t0.plus(4030))
    #expect(engine.state == .idle)
}

// MARK: - Whole cycle

@Test("Two full cycles run end to end")
func twoFullCycles() {
    var engine = engine()
    _ = engine.handle(.appLaunched(.login), at: t0)

    var now = t0
    for cycle in 1...2 {
        _ = engine.handle(.startPressed, at: now)
        #expect(engine.state == .session(endsAt: now.plus(1800)))

        now = now.plus(1770)
        #expect(engine.handle(.tick, at: now) == [.presentWarning])

        now = now.plus(30)
        _ = engine.handle(.tick, at: now)
        #expect(engine.state == .break(endsAt: now.plus(30), escapable: true))
        #expect(engine.counters.sessionsToday == cycle)

        now = now.plus(30)
        _ = engine.handle(.tick, at: now)
        #expect(engine.state == .idle)
    }

    #expect(engine.counters.escapesToday == 0)
}
