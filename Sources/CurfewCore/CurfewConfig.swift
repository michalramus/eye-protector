import Foundation

/// The curfew, as a value.
///
/// Lives on disk under a root-owned directory, so changing it costs a `sudo`.
/// That is deliberate and is half of what this app sells: a curfew you can
/// move at 19:55 is not a curfew.
///
/// Every field decodes to its default when absent, so a config file may hold
/// only the lines being overridden, and a typo in one key cannot wipe the
/// rest of the policy.
public struct CurfewConfig: Equatable, Sendable {
    public static let graceBounds: ClosedRange<TimeInterval> = 60...(4 * 3600)
    public static let challengeBounds: ClosedRange<Int> = 10...1000

    /// The night block runs from `nightStart` to `nightEnd` and is allowed to
    /// wrap midnight — which, at 20:00 to 11:00, it does.
    public let nightStart: TimeOfDay
    public let nightEnd: TimeOfDay

    /// `Calendar` weekday numbers: 1 is Sunday, 7 is Saturday. These days are
    /// blocked end to end rather than only at night.
    public let weekendDays: Set<Int>

    /// How long one passed challenge buys. Separate per period because the
    /// weekend block is longer and the point is a sustainable toll, not a
    /// punishment.
    public let nightGrace: TimeInterval
    public let weekendGrace: TimeInterval

    /// How long before the shield rises the warning appears. Clamped to the
    /// shorter grace, so a warning can never be older than the window it is
    /// warning about.
    public let warningLead: TimeInterval

    public let challengeLength: Int

    public init(
        nightStart: TimeOfDay = TimeOfDay(hour: 20, minute: 0),
        nightEnd: TimeOfDay = TimeOfDay(hour: 11, minute: 0),
        weekendDays: Set<Int> = [1, 7],
        nightGrace: TimeInterval = 20 * 60,
        weekendGrace: TimeInterval = 30 * 60,
        warningLead: TimeInterval = 120,
        challengeLength: Int = 200
    ) {
        self.nightStart = nightStart
        self.nightEnd = nightEnd
        self.weekendDays = weekendDays.filter { (1...7).contains($0) }
        let night = nightGrace.clamped(to: Self.graceBounds)
        let weekend = weekendGrace.clamped(to: Self.graceBounds)
        self.nightGrace = night
        self.weekendGrace = weekend
        self.warningLead = min(max(0, warningLead), min(night, weekend))
        self.challengeLength = min(
            max(Self.challengeBounds.lowerBound, challengeLength),
            Self.challengeBounds.upperBound
        )
    }

    public static let `default` = CurfewConfig()
}

extension CurfewConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case nightStart
        case nightEnd
        case weekendDays
        case nightGrace
        case weekendGrace
        case warningLead
        case challengeLength
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CurfewConfig.default
        self.init(
            nightStart: try container.decodeIfPresent(TimeOfDay.self, forKey: .nightStart)
                ?? fallback.nightStart,
            nightEnd: try container.decodeIfPresent(TimeOfDay.self, forKey: .nightEnd)
                ?? fallback.nightEnd,
            weekendDays: try container.decodeIfPresent(Set<Int>.self, forKey: .weekendDays)
                ?? fallback.weekendDays,
            nightGrace: try container.decodeIfPresent(TimeInterval.self, forKey: .nightGrace)
                ?? fallback.nightGrace,
            weekendGrace: try container.decodeIfPresent(TimeInterval.self, forKey: .weekendGrace)
                ?? fallback.weekendGrace,
            warningLead: try container.decodeIfPresent(TimeInterval.self, forKey: .warningLead)
                ?? fallback.warningLead,
            challengeLength: try container.decodeIfPresent(Int.self, forKey: .challengeLength)
                ?? fallback.challengeLength
        )
    }
}

extension TimeInterval {
    func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        guard !isNaN else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
