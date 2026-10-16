import Foundation

/// Tallies shown back to the user in the menu bar. Reset at local midnight.
public struct Counters: Equatable, Sendable {
    /// Start of the local day these tallies belong to.
    public var day: Date
    /// Incremented when a Session completes, not when one starts: "4 sessions
    /// today" should mean four stretches actually seen through.
    public var sessionsToday: Int
    public var escapesToday: Int

    public init(day: Date, sessionsToday: Int = 0, escapesToday: Int = 0) {
        self.day = day
        self.sessionsToday = sessionsToday
        self.escapesToday = escapesToday
    }
}

/// The hook for capping Escapes later without reshaping anything. Today the
/// user wants Escapes counted but never refused.
public enum EscapePolicy: Equatable, Sendable {
    case unlimited
    case maxPerDay(Int)

    public func allows(escapesToday: Int) -> Bool {
        switch self {
        case .unlimited: return true
        case .maxPerDay(let limit): return escapesToday < limit
        }
    }
}
