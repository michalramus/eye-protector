import Foundation

/// A wall-clock time of day, with no date attached.
///
/// Coded as `"20:00"` rather than as a number of seconds: the config file is
/// meant to be edited by hand — with `sudo`, which is the whole point of where
/// it lives — and a curfew written as `72000` is a curfew nobody can check at
/// a glance.
public struct TimeOfDay: Equatable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    /// Clamped rather than failable: a nonsense hour in a hand-edited file
    /// must not be able to disable the curfew by refusing to parse.
    public init(hour: Int, minute: Int) {
        self.hour = min(max(0, hour), 23)
        self.minute = min(max(0, minute), 59)
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var text: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

extension TimeOfDay: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = TimeOfDay(text) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a time of day like \"20:00\", got \"\(text)\""
                )
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
