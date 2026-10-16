import AppKit
import EyeProtectorCore

/// The adapter between the pure `CycleEngine` and the machine: it supplies the
/// clock, turns system notifications into events, and performs the effects the
/// engine returns.
@MainActor
final class CycleController {
    private(set) var engine: CycleEngine
    private let overlay: OverlayController
    private let lockout: Lockout
    private let store: SettingsStore
    private let hud = WarningHUD()
    private let escape = EscapeMonitor()

    private var ticker: Timer?
    private var deadMan: Timer?

    /// Called after every event so the menu bar can redraw. Set in step 5.
    var onChange: () -> Void = {}

    init(
        overlay: OverlayController,
        lockout: Lockout = Lockout(),
        store: SettingsStore = SettingsStore(),
        now: Date = Date()
    ) {
        self.overlay = overlay
        self.lockout = lockout
        self.store = store
        self.engine = CycleEngine(
            now: now,
            config: store.config,
            counters: store.loadCounters()
        )

        overlay.model.onStart = { [weak self] in self?.send(.startPressed) }
        overlay.model.onQuit = { NSApp.terminate(nil) }

        escape.onProgress = { [weak self] progress in
            self?.overlay.model.escapeProgress = progress
        }
        escape.onComplete = { [weak self] in self?.send(.escapeCompleted) }
    }

    func start(trigger: LaunchTrigger) {
        observeSleepAndWake()
        send(.appLaunched(trigger))

        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { self.send(.tick) }
        }
    }

    var config: Config {
        get { engine.config }
        set {
            store.config = newValue
            send(.settingsChanged(newValue))
        }
    }

    func send(_ event: CycleEvent) {
        let effects = engine.handle(event, at: Date())
        for effect in effects {
            apply(effect)
        }
        refreshOverlayPhase()
        updateEscapeArming()
        updateDeadMansSwitch()
        onChange()
    }

    private func apply(_ effect: CycleEffect) {
        switch effect {
        case .presentOverlay(let locked):
            // Windows first, Lockout second: the Overlay has to already be on
            // every Space before the user can be prevented from leaving.
            overlay.present()
            if locked {
                lockout.engage()
            } else {
                lockout.disengage()
            }

        case .dismissOverlay:
            lockout.disengage()
            overlay.dismiss()

        case .presentWarning:
            hud.present()

        case .dismissWarning:
            hud.dismiss()

        case .persistCounters(let counters):
            store.save(counters)
        }
    }

    private func refreshOverlayPhase() {
        switch engine.state {
        case .idle:
            overlay.model.phase = .idle
        case .breaking(let endsAt, let escapable):
            overlay.model.phase = .breaking(
                remaining: endsAt.timeIntervalSinceNow,
                escapable: escapable
            )
        case .warning(let endsAt):
            hud.model.remaining = endsAt.timeIntervalSinceNow

        case .working:
            break
        }
    }

    private func updateEscapeArming() {
        if case .breaking(_, let escapable) = engine.state, escapable {
            escape.arm()
        } else {
            escape.disarm()
            overlay.model.escapeProgress = 0
        }
    }

    /// The guarantee from ADR 0004: Lockout lifts — that is, the user reaches
    /// Idle, where Start is one click away — no later than a minute after a
    /// Break was due to end, whatever state the engine has got itself into.
    private func updateDeadMansSwitch() {
        guard case .breaking(let endsAt, _) = engine.state else {
            deadMan?.invalidate()
            deadMan = nil
            return
        }
        guard deadMan == nil else { return }

        let fireIn = max(1, endsAt.addingTimeInterval(60).timeIntervalSinceNow)
        deadMan = Timer.scheduledTimer(withTimeInterval: fireIn, repeats: false) { _ in
            MainActor.assumeIsolated { self.forceIdle() }
        }
    }

    private func forceIdle() {
        deadMan = nil
        guard case .breaking(let endsAt, _) = engine.state else { return }

        // Sleep can push the Break's end out from under an already-scheduled
        // timer; in that case re-arm rather than cutting the Break short.
        guard Date() >= endsAt.addingTimeInterval(60) else {
            updateDeadMansSwitch()
            return
        }

        // Rebuilt rather than transitioned: a safety net that calls back into
        // the thing it is protecting against is not a safety net.
        engine = CycleEngine(
            now: Date(),
            config: engine.config,
            counters: engine.counters,
            escapePolicy: engine.escapePolicy
        )
        hud.dismiss()
        overlay.present()
        lockout.engage()
        refreshOverlayPhase()
        updateEscapeArming()
        onChange()
    }

    /// Every way the user can stop looking at the screen maps onto the same
    /// pair of events; the engine ignores a repeated sleep.
    private func observeSleepAndWake() {
        let workspace = NSWorkspace.shared.notificationCenter
        let away: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let back: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]

        for name in away {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.send(.machineSlept) }
            }
        }
        for name in back {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.send(.machineWoke) }
            }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.send(.machineSlept) }
        }
        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.send(.machineWoke) }
        }
    }
}
