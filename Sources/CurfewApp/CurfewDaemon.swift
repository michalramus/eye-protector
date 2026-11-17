import CurfewCore
import EyeProtectorCore
import Foundation
import Synchronization

/// The root half of Curfew: owns the clock, the config, the state file and
/// the challenge, and draws nothing.
///
/// Everything here is behind one lock rather than an actor, because the
/// socket arrives on its own thread and the tick is a bare `Thread` with a
/// sleep in it — the same deliberately dumb shape as Eye Protector's
/// main-thread watchdog. A daemon that needs a concurrency runtime to answer
/// "is the shield up" has already lost.
final class CurfewDaemon: Sendable {
    private struct Box {
        var config: CurfewConfig
        var configModifiedAt: Date?
        var state: CurfewState
        var persisted: CurfewState
        var persistedAt: Date
        var challenge: Challenge?
        var shieldWasUp: Bool?
    }

    /// `lastSeen` is what makes a wound-back clock visible, so it is worth
    /// writing down regularly even when nothing else has changed. Thirty
    /// seconds is the resolution of that detection and the cost is one small
    /// file write a minute.
    private static let persistInterval: TimeInterval = 30
    private static let superviseEvery = 5

    private let paths: Paths
    private let stateStore: StateStore
    private let configStore: ConfigStore
    private let log: EventLog
    private let supervisor: AgentSupervisor
    private let box: Mutex<Box>

    init(paths: Paths = .current) {
        self.paths = paths
        stateStore = StateStore(path: paths.state)
        configStore = ConfigStore(path: paths.config)
        log = EventLog(path: paths.events)
        supervisor = AgentSupervisor(paths: paths)

        let now = Date()
        let config = configStore.load()
        let state = stateStore.load(now: now)
        box = Mutex(
            Box(
                config: config,
                configModifiedAt: configStore.modifiedAt(),
                state: state,
                persisted: state,
                persistedAt: now,
                challenge: nil,
                shieldWasUp: nil
            )
        )
    }

    func run() -> Never {
        prepare()

        do {
            try ControlSocketServer(path: paths.socket) { [self] request in
                handle(request)
            }.start()
        } catch {
            // Without the socket the agent cannot be told anything — and an
            // agent that cannot reach the daemon shields unconditionally, so
            // exiting here is both honest and safe. launchd will retry.
            log.record("socket failed: \(error)")
            exit(EXIT_FAILURE)
        }

        startTicking()
        while true { Thread.sleep(forTimeInterval: 3600) }
    }

    /// Everything `run()` does before it has anything to listen on, split out
    /// so that a standalone process can have the daemon without the socket.
    func prepare() {
        prepareDirectories()
        log.record("daemon started (pid \(getpid()))")
    }

    /// The one-second tick on its own thread, so that a caller that has
    /// other work to do — the standalone app has a run loop — is not blocked.
    func startTicking() {
        let thread = Thread { [self] in
            var counter = 0
            while true {
                tick(now: Date())
                if counter % Self.superviseEvery == 0 {
                    supervisor.ensureAgentIsLoaded()
                }
                counter &+= 1
                Thread.sleep(forTimeInterval: 1)
            }
        }
        thread.name = "curfew.tick"
        thread.start()
    }

    private func prepareDirectories() {
        try? FileManager.default.createDirectory(
            atPath: paths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try? configStore.writeIfMissing(.default)
    }

    // MARK: - The tick

    private func tick(now: Date) {
        box.withLock { box in
            reloadConfigIfChanged(&box)

            let policy = Self.policy(for: box.config)
            box.state = policy.observing(box.state, now: now)
            let decision = policy.decide(box.state, now: now)

            issueOrRetireChallenge(&box, decision: decision)
            announce(&box, decision: decision)
            persistIfDue(&box, now: now)
        }
    }

    private static func policy(for config: CurfewConfig) -> CurfewPolicy {
        CurfewPolicy(schedule: Schedule(config: config))
    }

    private func reloadConfigIfChanged(_ box: inout Box) {
        let modified = configStore.modifiedAt()
        guard modified != box.configModifiedAt else { return }
        box.configModifiedAt = modified

        let config = configStore.load()
        guard config != box.config else { return }
        box.config = config
        log.record("config reloaded: night \(config.nightStart.text)-\(config.nightEnd.text)")
    }

    /// One challenge per episode of the shield being up.
    ///
    /// Not one per request: re-rolling the string every second would make the
    /// first fifty characters you typed wrong, and re-rolling it per
    /// connection would let a client shop for a short one.
    private func issueOrRetireChallenge(_ box: inout Box, decision: ShieldDecision) {
        if case .shielded = decision {
            if box.challenge == nil {
                box.challenge = .random(length: box.config.challengeLength)
            }
        } else {
            box.challenge = nil
        }
    }

    private func announce(_ box: inout Box, decision: ShieldDecision) {
        let isUp: Bool = if case .shielded = decision { true } else { false }
        defer { box.shieldWasUp = isUp }
        guard box.shieldWasUp != isUp else { return }

        if case .shielded(let reason) = decision {
            log.record("shield up (\(Self.describe(reason)))")
        } else if box.shieldWasUp == true {
            log.record("shield down")
        }
    }

    private func persistIfDue(_ box: inout Box, now: Date) {
        let changed = box.state != box.persisted
        let stale = now.timeIntervalSince(box.persistedAt) >= Self.persistInterval
        guard changed || stale else { return }

        do {
            try stateStore.save(box.state)
            box.persisted = box.state
            box.persistedAt = now
        } catch {
            log.record("state write failed: \(error)")
        }
    }

    // MARK: - The socket

    func handle(_ request: CurfewRequest) -> CurfewResponse {
        let now = Date()
        return box.withLock { box in
            let policy = Self.policy(for: box.config)
            let decision = policy.decide(box.state, now: now)
            issueOrRetireChallenge(&box, decision: decision)

            switch request {
            case .status:
                return .status(status(box, policy: policy, decision: decision, now: now))
            case .submit(let text):
                return submit(text, &box, policy: policy, decision: decision, now: now)
            }
        }
    }

    private func status(
        _ box: Box,
        policy: CurfewPolicy,
        decision: ShieldDecision,
        now: Date
    ) -> CurfewStatus {
        let period = policy.schedule.period(at: now)
        let grace = policy.schedule.grace(for: period)

        switch decision {
        case .shielded(let reason):
            return CurfewStatus(
                shield: true,
                cause: Self.cause(for: reason),
                period: period,
                challenge: box.challenge?.text,
                raisesAt: nil,
                grace: grace,
                unlockCount: box.state.unlockCount,
                now: now
            )
        case .warning(let raisesAt):
            return CurfewStatus(
                shield: false,
                period: period,
                warning: true,
                raisesAt: raisesAt,
                grace: grace,
                unlockCount: box.state.unlockCount,
                now: now
            )
        case .clear(let nextRise):
            return CurfewStatus(
                shield: false,
                period: period,
                raisesAt: nextRise,
                grace: grace,
                unlockCount: box.state.unlockCount,
                now: now
            )
        }
    }

    private func submit(
        _ text: String,
        _ box: inout Box,
        policy: CurfewPolicy,
        decision: ShieldDecision,
        now: Date
    ) -> CurfewResponse {
        guard case .shielded(let reason) = decision else {
            return .rejected(reason: "The shield is not up.")
        }

        if case .clockRolledBack = reason {
            // Typing cannot buy back time that was taken off the clock: that
            // would make the date setting the cheapest bypass in the design.
            return .rejected(
                reason: "The system clock was moved backwards. "
                    + "The shield lifts once real time passes "
                    + "\(Self.short(box.state.lastSeen))."
            )
        }

        guard let challenge = box.challenge, challenge.text == text else {
            return .rejected(reason: "That is not the string on the screen.")
        }

        let unlocked = policy.unlocked(box.state, now: now)
        guard let until = unlocked.unlockedUntil else {
            return .rejected(reason: "The schedule granted no time.")
        }

        // Written before the shield is allowed down. If this fails the user
        // stays blocked, which is the right way round: an unlock nobody
        // recorded is an unlock that a kill would erase.
        do {
            try stateStore.save(unlocked)
        } catch {
            log.record("unlock not recorded: \(error)")
            return .rejected(reason: "The state file could not be written.")
        }

        box.state = unlocked
        box.persisted = unlocked
        box.persistedAt = now
        box.challenge = nil
        log.record("unlocked until \(Self.short(until)) (#\(unlocked.unlockCount))")
        return .unlocked(until: until)
    }

    // MARK: - Words

    private static func describe(_ reason: ShieldReason) -> String {
        switch reason {
        case .schedule(let period): period.rawValue
        case .clockRolledBack: "clock rolled back"
        }
    }

    private static func cause(for reason: ShieldReason) -> ShieldCause {
        switch reason {
        case .schedule(.weekend): .weekend
        case .schedule: .night
        case .clockRolledBack: .clockRolledBack
        }
    }

    private static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}
