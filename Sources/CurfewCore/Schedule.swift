import Foundation

/// Which rule, if any, covers a given instant.
public enum CurfewPeriod: String, Codable, Equatable, Sendable {
    case free
    case night
    case weekend
}

/// The curfew calendar: turns an instant into a period, and finds the next
/// instant at which the shield is due to rise.
///
/// Reads no clock of its own — every instant arrives as an argument — so the
/// whole of a year's worth of boundaries can be checked in a unit test.
public struct Schedule: Sendable {
    public let config: CurfewConfig
    private let calendar: Calendar

    public init(config: CurfewConfig = .default, calendar: Calendar = .current) {
        self.config = config
        self.calendar = calendar
    }

    public func period(at now: Date) -> CurfewPeriod {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard
            let weekday = components.weekday,
            let hour = components.hour,
            let minute = components.minute
        else {
            // A date the calendar cannot decompose is not a reason to hand the
            // night back: everything here fails closed.
            return .night
        }

        if config.weekendDays.contains(weekday) {
            return .weekend
        }
        return isWithinNight(TimeOfDay(hour: hour, minute: minute)) ? .night : .free
    }

    /// Whether the night window covers a time of day, midnight wrap included.
    ///
    /// A zero-length window — `nightStart == nightEnd` — blocks nothing. The
    /// alternative reading, "blocks everything", would turn one fat-fingered
    /// digit in the config file into a machine that never unlocks.
    func isWithinNight(_ time: TimeOfDay) -> Bool {
        if config.nightStart == config.nightEnd { return false }
        if config.nightStart < config.nightEnd {
            return time >= config.nightStart && time < config.nightEnd
        }
        return time >= config.nightStart || time < config.nightEnd
    }

    public func grace(for period: CurfewPeriod) -> TimeInterval {
        switch period {
        case .free: 0
        case .night: config.nightGrace
        case .weekend: config.weekendGrace
        }
    }

    /// The next instant at which a free period turns into a blocked one.
    ///
    /// Deliberately dumb: it walks forward a minute at a time rather than
    /// reasoning about which boundary comes first. Boundaries interact with
    /// weekends, with each other and with the two days a year that are not 24
    /// hours long, and a loop that a reader can check by eye is worth more
    /// here than the microseconds the clever version would save — this runs
    /// once per transition, not once per frame.
    public func nextShieldRise(after now: Date) -> Date? {
        guard period(at: now) == .free else { return nil }
        let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard var cursor = calendar.date(from: fields) else { return nil }

        // Eight days: longer than any gap between blocked periods a weekly
        // schedule can produce, so running out means the config blocks nothing.
        let limit = now.addingTimeInterval(8 * 24 * 3600)
        while cursor <= limit {
            guard let next = calendar.date(byAdding: .minute, value: 1, to: cursor) else {
                return nil
            }
            cursor = next
            if period(at: cursor) != .free {
                return cursor
            }
        }
        return nil
    }
}
