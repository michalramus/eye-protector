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

    private var ticker: Timer?

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

        case .presentWarning, .dismissWarning:
            // The Warning HUD arrives in step 6 of the build order.
            break

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
        case .working, .warning:
            break
        }
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
