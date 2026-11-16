import Foundation

/// The entire conversation between the root daemon and the GUI agent.
///
/// Deliberately tiny. The agent is a screen, not a participant: it can ask
/// what to show and it can report what was typed. There is no "unlock me"
/// message, because there is nothing the agent could say that the daemon
/// would take on trust — the typed text is checked against the challenge the
/// daemon itself issued.
public enum CurfewRequest: Codable, Equatable, Sendable {
    case status
    case submit(text: String)
}

/// Why the shield is up, in a form that survives the wire.
///
/// Not `ShieldReason`: that one carries a `CurfewPeriod` and exists for the
/// policy's benefit. This one exists for the screen's, and adds the case the
/// policy cannot know about — the agent having lost the daemon.
public enum ShieldCause: String, Codable, Equatable, Sendable {
    case night
    case weekend
    case clockRolledBack
    /// The agent could not reach the daemon. Fail closed: a shield with no
    /// way to unlock it, which is recoverable only by the daemon coming back.
    case daemonUnreachable
}

public struct CurfewStatus: Codable, Equatable, Sendable {
    public var shield: Bool
    public var cause: ShieldCause?
    public var period: CurfewPeriod

    /// Present exactly while the shield is up. Issued by the daemon so that
    /// the string the user is typing and the string being checked are the
    /// same object, even across an agent restart mid-type.
    public var challenge: String?

    /// Whether the agent should be showing the notice that the shield is
    /// about to go up. Sent rather than derived, because the lead time is
    /// config the agent does not have.
    public var warning: Bool

    /// When the shield next goes up — either the end of the current grace or
    /// the start of the next blocked period.
    public var raisesAt: Date?

    /// What one passed challenge buys right now.
    public var grace: TimeInterval

    public var unlockCount: Int

    /// The daemon's clock. The agent counts down against this rather than
    /// against its own, so that two processes disagreeing about the time
    /// cannot show a countdown that never reaches zero.
    public var now: Date

    public init(
        shield: Bool,
        cause: ShieldCause? = nil,
        period: CurfewPeriod,
        challenge: String? = nil,
        warning: Bool = false,
        raisesAt: Date? = nil,
        grace: TimeInterval,
        unlockCount: Int,
        now: Date
    ) {
        self.shield = shield
        self.cause = cause
        self.period = period
        self.challenge = challenge
        self.warning = warning
        self.raisesAt = raisesAt
        self.grace = grace
        self.unlockCount = unlockCount
        self.now = now
    }

    /// What the agent shows when the daemon cannot be reached at all.
    public static func unreachable(now: Date) -> CurfewStatus {
        CurfewStatus(
            shield: true,
            cause: .daemonUnreachable,
            period: .night,
            challenge: nil,
            warning: false,
            raisesAt: nil,
            grace: 0,
            unlockCount: 0,
            now: now
        )
    }
}

public enum CurfewResponse: Codable, Equatable, Sendable {
    case status(CurfewStatus)
    case unlocked(until: Date)
    case rejected(reason: String)
}

/// One JSON object per line, UTF-8, newline-terminated.
///
/// A line protocol rather than a length-prefixed one because the whole
/// exchange is request-response over a connection that is closed immediately
/// afterwards: there is nothing to frame that a newline does not frame.
public enum CurfewCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Caps what a single message may be. The socket is reachable by any
    /// local user, so an unbounded read is an invitation.
    public static let maximumMessageBytes = 64 * 1024
}
