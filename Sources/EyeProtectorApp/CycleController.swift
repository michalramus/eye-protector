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
    private let nets: SafetyNets

    private var ticker: Timer?
    private var deadMan: Timer?
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// Called after every event so the menu bar can redraw. Set in step 5.
    var onChange: () -> Void = {}

    init(
        overlay: OverlayController,
        lockout: Lockout = Lockout(),
        store: SettingsStore = SettingsStore(),
        nets: SafetyNets = .lenient,
        now: Date = Date()
    ) {
        self.overlay = overlay
        self.lockout = lockout
        self.nets = nets
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

    isolated deinit {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
    }

    func start(trigger: LaunchTrigger) {
        observeSleepAndWake()
        send(.appLaunched(trigger))

        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.tick) }
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
        case .presentOverlay:
            // Windows first, Lockout second: the Overlay has to already be on
            // every Space before the user can be prevented from leaving.
            overlay.present()
            lockout.engage()

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
        case .break(let endsAt, let escapable):
            overlay.model.phase = .break(
                remaining: endsAt.timeIntervalSinceNow,
                escapable: escapable
            )
        case .warning(let endsAt):
            hud.model.remaining = endsAt.timeIntervalSinceNow

        case .session:
            break
        }
    }

    private func updateEscapeArming() {
        if case .break(_, let escapable) = engine.state, escapable {
            escape.arm()
        } else {
            escape.disarm()
            overlay.model.escapeProgress = 0
        }
    }

    /// The guarantee from ADR 0004: the user reaches Idle — where Start is one
    /// click away — no later than `nets.graceAfterBreak` after a Break was due
    /// to end, whatever state the engine has got itself into. Idle is still
    /// locked; what the net restores is the ability to act, not the desktop.
    private func updateDeadMansSwitch() {
        guard case .break(let endsAt, _) = engine.state else {
            deadMan?.invalidate()
            deadMan = nil
            return
        }
        guard deadMan == nil else { return }

        let fireIn = max(1, endsAt.addingTimeInterval(nets.graceAfterBreak).timeIntervalSinceNow)
        deadMan = Timer.scheduledTimer(withTimeInterval: fireIn, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.forceIdle() }
        }
    }

    private func forceIdle() {
        deadMan = nil
        guard case .break(let endsAt, _) = engine.state else { return }

        // Sleep can push the Break's end out from under an already-scheduled
        // timer; in that case re-arm rather than cutting the Break short.
        guard Date() >= endsAt.addingTimeInterval(nets.graceAfterBreak) else {
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

    /// The three ways the user genuinely stops looking at the screen, each as
    /// a matched pair so that a "back" from one source cannot cancel an
    /// "away" from another.
    ///
    /// Display sleep is deliberately absent. `screensDidSleep` is driven by
    /// the system idle timer, so observing it would pause the Session clock
    /// for a user who simply is not typing — which is exactly what the design
    /// rules out: watching a video is still screen time.
    private static let awayAndBack: [(away: NSNotification.Name, back: NSNotification.Name)] = [
        (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
        (
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ),
    ]

    private func observeSleepAndWake() {
        let workspace = NSWorkspace.shared.notificationCenter

        for pair in Self.awayAndBack {
            observe(pair.away, on: workspace, as: .machineSlept)
            observe(pair.back, on: workspace, as: .machineWoke)
        }

        // Screen lock has no `NSWorkspace` equivalent.
        let distributed = DistributedNotificationCenter.default()
        observe(.init("com.apple.screenIsLocked"), on: distributed, as: .machineSlept)
        observe(.init("com.apple.screenIsUnlocked"), on: distributed, as: .machineWoke)
    }

    private func observe(
        _ name: NSNotification.Name,
        on center: NotificationCenter,
        as event: CycleEvent
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(event) }
        }
        observers.append((center, token))
    }
}
