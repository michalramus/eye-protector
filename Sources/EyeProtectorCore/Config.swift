import Foundation

/// The user-configurable values. Out-of-range values are clamped on the way in
/// rather than rejected, so no caller can hold a `Config` that the cycle engine
/// would have to defend itself against.
public struct Config: Equatable, Sendable {
    /// 1 minute to 3 hours. The short minimum is deliberate: it makes the whole
    /// cycle exercisable by hand in seconds.
    public static let sessionBounds: ClosedRange<TimeInterval> = 60...(180 * 60)
    public static let breakBounds: ClosedRange<TimeInterval> = 5...600
    public static let defaultWarningLead: TimeInterval = 30

    public let sessionLength: TimeInterval
    public let breakLength: TimeInterval
    /// How long before a Session ends the Warning appears. Clamped to the
    /// Session length so it can never fall before the Session began.
    public let warningLead: TimeInterval
    public let warningEnabled: Bool
    public let launchAtLogin: Bool

    public init(
        sessionLength: TimeInterval = 30 * 60,
        breakLength: TimeInterval = 30,
        warningLead: TimeInterval = Config.defaultWarningLead,
        warningEnabled: Bool = true,
        launchAtLogin: Bool = false
    ) {
        let session = sessionLength.clamped(to: Self.sessionBounds)
        self.sessionLength = session
        self.breakLength = breakLength.clamped(to: Self.breakBounds)
        self.warningLead = min(max(0, warningLead), session)
        self.warningEnabled = warningEnabled
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = Config()
}

extension TimeInterval {
    func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        guard !isNaN else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
