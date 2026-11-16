import Foundation
import Testing

@testable import CurfewCore

// MARK: - Fixtures

/// A fixed zone so the weekday and hour of every instant is known rather than
/// wherever the test happens to run.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func schedule(_ config: CurfewConfig = .default) -> Schedule {
    Schedule(config: config, calendar: calendar)
}

// 2026-11-16 is a Monday, 11-17 Tuesday, 11-20 Friday, 11-21 Saturday, 11-22 Sunday.

// MARK: - Period

@Test("A weekday is free until 20:00, night through to 10:59, and free again at 11:00")
func weekdayBoundaries() {
    let schedule = schedule()
    #expect(schedule.period(at: date(2026, 11, 17, 19, 59)) == .free)
    #expect(schedule.period(at: date(2026, 11, 17, 20, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 17, 3, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 17, 10, 59)) == .night)
    #expect(schedule.period(at: date(2026, 11, 17, 11, 0)) == .free)
}

@Test("Every hour of a Saturday and of a Sunday is weekend")
func weekendIsBlockedEndToEnd() {
    let schedule = schedule()
    for day in [21, 22] {
        for hour in 0..<24 {
            #expect(schedule.period(at: date(2026, 11, day, hour, 0)) == .weekend)
        }
        // Midday is the case a night-only reading would get wrong.
        #expect(schedule.period(at: date(2026, 11, day, 12, 0)) == .weekend)
        #expect(schedule.period(at: date(2026, 11, day, 23, 30)) == .weekend)
    }
}

@Test("Friday night hands over to weekend at midnight, and Monday morning is night until 11:00")
func weekendEdges() {
    let schedule = schedule()
    #expect(schedule.period(at: date(2026, 11, 20, 20, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 21, 0, 0)) == .weekend)
    #expect(schedule.period(at: date(2026, 11, 22, 23, 59)) == .weekend)
    #expect(schedule.period(at: date(2026, 11, 23, 0, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 16, 10, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 16, 11, 0)) == .free)
}

@Test("A window that does not wrap midnight blocks only between its times")
func nonWrappingWindow() {
    let schedule = schedule(CurfewConfig(
        nightStart: TimeOfDay(hour: 13, minute: 0),
        nightEnd: TimeOfDay(hour: 14, minute: 0)
    ))
    #expect(schedule.period(at: date(2026, 11, 17, 12, 59)) == .free)
    #expect(schedule.period(at: date(2026, 11, 17, 13, 0)) == .night)
    #expect(schedule.period(at: date(2026, 11, 17, 13, 59)) == .night)
    #expect(schedule.period(at: date(2026, 11, 17, 14, 0)) == .free)
    // The wrapped reading would block these.
    #expect(schedule.period(at: date(2026, 11, 17, 3, 0)) == .free)
    #expect(schedule.period(at: date(2026, 11, 17, 22, 0)) == .free)
}

@Test("A zero-length window blocks nothing")
func zeroLengthWindowBlocksNothing() {
    let time = TimeOfDay(hour: 20, minute: 0)
    let schedule = schedule(CurfewConfig(nightStart: time, nightEnd: time))
    for hour in 0..<24 {
        #expect(schedule.period(at: date(2026, 11, 17, hour, 0)) == .free)
    }
}

// MARK: - Next rise

@Test("The next rise from a free weekday instant is that day's 20:00")
func riseLandsOnEvening() {
    let schedule = schedule()
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 11, 0)) == date(2026, 11, 17, 20, 0))
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 15, 30)) == date(2026, 11, 17, 20, 0))
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 19, 59)) == date(2026, 11, 17, 20, 0))
}

@Test("The next rise from Friday 11:00 is Friday 20:00, not Saturday")
func riseOnFridayIsEvening() {
    let schedule = schedule()
    #expect(schedule.nextShieldRise(after: date(2026, 11, 20, 11, 0)) == date(2026, 11, 20, 20, 0))
}

@Test("A rise is never reported while the period is already blocked")
func noRiseWhenBlocked() {
    let schedule = schedule()
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 21, 0)) == nil)
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 3, 0)) == nil)
    #expect(schedule.nextShieldRise(after: date(2026, 11, 21, 12, 0)) == nil)
}

@Test("A config that blocks nothing has no next rise, and the search ends")
func noRiseWhenNothingIsBlocked() {
    let time = TimeOfDay(hour: 9, minute: 0)
    let schedule = schedule(CurfewConfig(nightStart: time, nightEnd: time, weekendDays: []))
    #expect(schedule.nextShieldRise(after: date(2026, 11, 17, 12, 0)) == nil)
}

// MARK: - Grace

@Test("Grace is zero when free, and each blocked period buys its own")
func graceByPeriod() {
    let schedule = schedule()
    #expect(schedule.grace(for: .free) == 0)
    #expect(schedule.grace(for: .night) == 20 * 60)
    #expect(schedule.grace(for: .weekend) == 30 * 60)
}
