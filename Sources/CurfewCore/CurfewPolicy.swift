import Foundation

/// Everything the curfew remembers between one run of the process and the
/// next — which is the part that makes killing the process pointless.
///
/// The opposite choice to Eye Protector's ADR 0002. There, forgetting on
/// restart was the feature; here it would be the bypass: unlock, kill, and the
/// evening is yours. The daemon owns this file, runs as root, and the user it
/// polices cannot write it.
public struct CurfewState: Codable, Equatable, Sendable {
    /// When the current grace runs out. Absent means the shield is due now if
    /// the schedule says so.
    public var unlockedUntil: Date?

    /// The latest instant the daemon has ever observed. Only ever moves
    /// forward, so that winding the system clock back is visible rather than
    /// being free extra grace.
    public var lastSeen: Date

    /// Set when the clock jumped backwards and cleared once real time has
    /// caught up with `lastSeen` again.
    public var clockRolledBack: Bool

    public var unlockCount: Int

    public init(
        unlockedUntil: Date? = nil,
        lastSeen: Date,
        clockRolledBack: Bool = false,
        unlockCount: Int = 0
    ) {
        self.unlockedUntil = unlockedUntil
        self.lastSeen = lastSeen
        self.clockRolledBack = clockRolledBack
        self.unlockCount = unlockCount
    }
}

public enum ShieldReason: Equatable, Sendable {
    case schedule(CurfewPeriod)
    /// The system clock went backwards. Treated as a blocked period in its own
    /// right: the alternative is that the cheapest bypass in the whole design
    /// is the date setting.
    case clockRolledBack
}

public enum ShieldDecision: Equatable, Sendable {
    /// Nothing to show. `nextRise` is when that changes, if it is known.
    case clear(nextRise: Date?)
    /// The shield is about to rise and the user should be told.
    case warning(raisesAt: Date)
    case shielded(ShieldReason)
}

/// The curfew rules, as a pure function of state, config and the clock.
///
/// Holds no file handles, no windows and no timers, so the awkward cases —
/// midnight, Sunday 23:59, a clock wound back an hour — are all reachable from
/// a test rather than only from a Saturday night.
public struct CurfewPolicy: Sendable {
    /// How far the clock may move backwards before it is read as tampering.
    /// Generous enough for an NTP correction, far short of the hour that
    /// moving a curfew would need.
    public static let clockTolerance: TimeInterval = 300

    public let schedule: Schedule

    public init(schedule: Schedule) {
        self.schedule = schedule
    }

    public var config: CurfewConfig { schedule.config }

    /// Folds an observation of the clock into the state. Called on every tick
    /// by the daemon, before `decide`.
    public func observing(_ state: CurfewState, now: Date) -> CurfewState {
        var updated = state

        if now < state.lastSeen.addingTimeInterval(-Self.clockTolerance) {
            updated.clockRolledBack = true
            // The grace that was running when the clock moved goes with it.
            // Without this, winding back an hour is an hour of free time.
            updated.unlockedUntil = nil
        } else if state.clockRolledBack, now >= state.lastSeen {
            updated.clockRolledBack = false
        }

        updated.lastSeen = max(state.lastSeen, now)
        return updated
    }

    public func decide(_ state: CurfewState, now: Date) -> ShieldDecision {
        if state.clockRolledBack {
            return .shielded(.clockRolledBack)
        }

        let period = schedule.period(at: now)

        if period == .free {
            guard let rise = schedule.nextShieldRise(after: now) else {
                return .clear(nextRise: nil)
            }
            return rise.timeIntervalSince(now) <= config.warningLead
                ? .warning(raisesAt: rise)
                : .clear(nextRise: rise)
        }

        guard let until = state.unlockedUntil, until > now else {
            return .shielded(.schedule(period))
        }
        return until.timeIntervalSince(now) <= config.warningLead
            ? .warning(raisesAt: until)
            : .clear(nextRise: until)
    }

    /// The state after a challenge has been typed out in full.
    ///
    /// Grace is measured from now, not from when the challenge was issued: the
    /// typing is part of the toll, not part of the reward.
    public func unlocked(_ state: CurfewState, now: Date) -> CurfewState {
        var updated = state
        let period = schedule.period(at: now)
        updated.unlockedUntil = now.addingTimeInterval(schedule.grace(for: period))
        updated.unlockCount += 1
        updated.lastSeen = max(state.lastSeen, now)
        return updated
    }

    /// What a missing, unreadable or corrupt state file turns into.
    ///
    /// Fail closed, by construction: no grace, and `lastSeen` at the instant
    /// the daemon noticed. Deleting the file is therefore a way to lock
    /// yourself out, never a way in.
    public static func freshState(now: Date) -> CurfewState {
        CurfewState(unlockedUntil: nil, lastSeen: now)
    }
}
