import Foundation

public enum LaunchTrigger: Equatable, Sendable {
    case user
    case login
}

public enum CycleState: Equatable, Sendable {
    /// Overlay up, Lockout engaged, Start live. Reached by launching, by a
    /// Break expiring, and by nothing else.
    case idle
    case session(endsAt: Date)
    case warning(endsAt: Date)
    case `break`(endsAt: Date, escapable: Bool)
}

public enum CycleEvent: Equatable, Sendable {
    case appLaunched(LaunchTrigger)
    case startPressed
    case escapeCompleted
    case tick
    case machineSlept
    case machineWoke
    case settingsChanged(Config)
}

public enum CycleEffect: Equatable, Sendable {
    /// Re-emitted on every entry into a state that shows the Overlay, so the
    /// adapter can treat it as "render the Overlay for the current state"
    /// rather than tracking transitions itself. Every state that shows the
    /// Overlay also locks, Idle included, so there is nothing to parameterise.
    case presentOverlay
    case dismissOverlay
    case presentWarning
    case dismissWarning
    case persistCounters(Counters)
}

/// The whole Idle → Session → Warning → Break → Idle cycle as a value.
///
/// Reads no clock and touches no AppKit: every instant arrives as the `now`
/// argument to `handle`, which is what lets a 30-minute Session be tested in
/// microseconds.
///
/// The dead-man's switch that guarantees Lockout lifts within a minute of a
/// Break's due end is deliberately *not* here — it lives in the adapter, so
/// that an engine wedged by a bug cannot keep the machine captive.
public struct CycleEngine: Equatable, Sendable {
    public private(set) var state: CycleState
    public private(set) var counters: Counters
    public private(set) var config: Config
    public var escapePolicy: EscapePolicy

    private let calendar: Calendar
    /// When the current phase began. Kept so a settings change can re-project
    /// the current deadline instead of only affecting the next phase.
    private var phaseStartedAt: Date?
    /// Non-nil while the machine is asleep or locked.
    private var sleepStartedAt: Date?

    public init(
        now: Date,
        config: Config = .default,
        counters: Counters? = nil,
        escapePolicy: EscapePolicy = .unlimited,
        calendar: Calendar = .current
    ) {
        self.state = .idle
        self.config = config
        self.escapePolicy = escapePolicy
        self.calendar = calendar
        self.counters = counters ?? Counters(day: calendar.startOfDay(for: now))
        self.phaseStartedAt = now
        self.sleepStartedAt = nil
    }

    public var isAsleep: Bool { sleepStartedAt != nil }

    public mutating func handle(_ event: CycleEvent, at now: Date) -> [CycleEffect] {
        let countersBefore = counters
        var effects: [CycleEffect] = []
        rollDayIfNeeded(now: now)

        switch event {
        case .appLaunched:
            // Both triggers land in the same place: Overlay up and locked, one
            // click from working. A silent login start was considered and
            // rejected.
            state = .idle
            phaseStartedAt = now
            sleepStartedAt = nil
            effects.append(.presentOverlay)

        case .startPressed:
            guard case .idle = state else { break }
            effects.append(contentsOf: beginSession(at: now))

        case .escapeCompleted:
            guard case .break(_, let escapable) = state, escapable else { break }
            counters.escapesToday += 1
            // An Escape trades the rest away rather than postponing it: a fresh
            // Session starts immediately.
            effects.append(contentsOf: beginSession(at: now))

        case .tick:
            effects.append(contentsOf: advance(to: now))

        case .machineSlept:
            if sleepStartedAt == nil { sleepStartedAt = now }

        case .machineWoke:
            guard let sleptAt = sleepStartedAt else { break }
            sleepStartedAt = nil
            shift(by: max(0, now.timeIntervalSince(sleptAt)))

        case .settingsChanged(let newConfig):
            config = newConfig
            effects.append(contentsOf: reproject(at: now))
            effects.append(contentsOf: advance(to: now))
        }

        if counters != countersBefore {
            effects.append(.persistCounters(counters))
        }
        return effects
    }

    // MARK: - Transitions

    private mutating func beginSession(at now: Date) -> [CycleEffect] {
        state = .session(endsAt: now.addingTimeInterval(config.sessionLength))
        phaseStartedAt = now
        return [.dismissOverlay]
    }

    private mutating func beginBreak(at now: Date) -> [CycleEffect] {
        counters.sessionsToday += 1
        state = .break(
            endsAt: now.addingTimeInterval(config.breakLength),
            escapable: escapePolicy.allows(escapesToday: counters.escapesToday)
        )
        phaseStartedAt = now
        return [.presentOverlay]
    }

    /// Advances as far as the clock allows. Loops because a single tick can
    /// span more than one phase if the app was stalled — a tick arriving an
    /// hour late must not leave the engine one phase behind reality.
    ///
    /// A late tick never *consumes* a Break: the Break is measured from the
    /// moment the engine notices the Session ended, not from when it was due
    /// to end. If the process was stalled the Overlay never appeared, so the
    /// user kept working and is owed the rest in full. Sleep is the opposite
    /// case and is handled separately, because there the eyes really were away
    /// from the screen.
    private mutating func advance(to now: Date) -> [CycleEffect] {
        guard sleepStartedAt == nil else { return [] }
        var effects: [CycleEffect] = []

        for _ in 0..<8 {
            let before = state
            switch state {
            case .idle:
                break

            case .session(let endsAt):
                if now >= endsAt {
                    effects.append(contentsOf: beginBreak(at: now))
                } else if config.warningEnabled,
                          now >= endsAt.addingTimeInterval(-config.warningLead) {
                    state = .warning(endsAt: endsAt)
                    effects.append(.presentWarning)
                }

            case .warning(let endsAt):
                if now >= endsAt {
                    effects.append(.dismissWarning)
                    effects.append(contentsOf: beginBreak(at: now))
                }

            case .break(let endsAt, _):
                if now >= endsAt {
                    state = .idle
                    phaseStartedAt = now
                    effects.append(.presentOverlay)
                }
            }
            if state == before { break }
        }
        return effects
    }

    /// Sleep pauses whatever phase is running, Breaks included: one rule is
    /// easier to reason about than two, and the alternative — letting sleep
    /// *complete* a Break — would turn closing the lid into an uncounted way to
    /// skip the rest, which is exactly what Escape exists to measure.
    private mutating func shift(by interval: TimeInterval) {
        guard interval > 0 else { return }
        switch state {
        case .idle:
            break
        case .session(let endsAt):
            state = .session(endsAt: endsAt.addingTimeInterval(interval))
        case .warning(let endsAt):
            state = .warning(endsAt: endsAt.addingTimeInterval(interval))
        case .break(let endsAt, let escapable):
            state = .break(endsAt: endsAt.addingTimeInterval(interval), escapable: escapable)
        }
        phaseStartedAt = phaseStartedAt?.addingTimeInterval(interval)
    }

    /// New lengths apply to the phase already running, measured from when that
    /// phase began — shortening the Session while in it is meant to take
    /// effect, not wait for the next one.
    private mutating func reproject(at now: Date) -> [CycleEffect] {
        guard let startedAt = phaseStartedAt else { return [] }

        switch state {
        case .idle:
            return []

        case .session:
            state = .session(endsAt: startedAt.addingTimeInterval(config.sessionLength))
            return []

        case .warning:
            let endsAt = startedAt.addingTimeInterval(config.sessionLength)
            let threshold = endsAt.addingTimeInterval(-config.warningLead)
            if !config.warningEnabled || now < threshold {
                state = .session(endsAt: endsAt)
                return [.dismissWarning]
            }
            state = .warning(endsAt: endsAt)
            return []

        case .break(_, let escapable):
            state = .break(
                endsAt: startedAt.addingTimeInterval(config.breakLength),
                escapable: escapable
            )
            return []
        }
    }

    private mutating func rollDayIfNeeded(now: Date) {
        let today = calendar.startOfDay(for: now)
        guard today != counters.day else { return }
        counters = Counters(day: today)
    }
}
