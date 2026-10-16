import EyeProtectorCore
import Foundation
import Synchronization

/// The only safeguard that does not run on the main thread, and so the only
/// one that still works when the main thread is the thing that has failed.
///
/// Every other way out of Lockout — the Break timer, the Escape hold, the
/// dead-man's switch — is main-thread code. If the main thread wedges while
/// Lockout is engaged, none of them can run, and the user is held on a black
/// screen until they find Force Quit.
///
/// There is no way to release Lockout from another thread: presentation
/// options are AppKit state and must be changed on the main thread. The one
/// remaining lever is ending the process, which makes the window server
/// restore the Dock and menu bar. So that is what this does. Losing an
/// in-progress Session is a cheap price — nothing about it is persisted
/// anyway (ADR 0002) — and the alternative is holding the user's machine
/// hostage on behalf of a bug.
///
/// Lock-free on purpose: a mutex would be held by the main thread at exactly
/// the wrong moment, and the watchdog would block on the stall it exists to
/// notice.
final class MainThreadWatchdog: Sendable {
    static let shared = MainThreadWatchdog()

    /// Monotonic nanoseconds at the last main-thread heartbeat; 0 before the
    /// first one.
    private let lastBeat = Atomic<UInt64>(0)
    /// Only act while the user is actually locked out.
    private let isArmed = Atomic<Bool>(false)
    private let limitNanoseconds = Atomic<UInt64>(0)
    private let hasStarted = Atomic<Bool>(false)

    private init() {}

    func start(stallLimit limit: TimeInterval) {
        limitNanoseconds.store(StallPolicy(limit: limit).limitNanoseconds, ordering: .relaxed)

        let (exchanged, _) = hasStarted.compareExchange(
            expected: false,
            desired: true,
            ordering: .relaxed
        )
        guard exchanged else { return }

        // A bare thread with a sleep loop rather than a timer: no run loop, no
        // dispatch queue, nothing that a wedged main thread could starve.
        let thread = Thread { [self] in
            while true {
                Thread.sleep(forTimeInterval: 1)
                checkForStall()
            }
        }
        thread.name = "eye-protector.watchdog"
        thread.qualityOfService = .background
        thread.start()
    }

    /// Called from the main thread on every tick of the cycle.
    func beat() {
        lastBeat.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
    }

    func setArmed(_ armed: Bool) {
        if armed {
            beat()
        }
        isArmed.store(armed, ordering: .relaxed)
    }

    private func checkForStall() {
        guard isArmed.load(ordering: .relaxed) else { return }

        let limit = limitNanoseconds.load(ordering: .relaxed)
        let policy = StallPolicy(limitNanoseconds: limit)
        guard
            policy.hasStalled(
                lastBeat: lastBeat.load(ordering: .relaxed),
                now: DispatchTime.now().uptimeNanoseconds
            )
        else { return }

        FileHandle.standardError.write(
            Data(
                """
                eye-protector: main thread unresponsive for over \
                \(limit / 1_000_000_000)s while locked out; ending the process \
                so the Dock and menu bar come back.

                """.utf8
            )
        )
        exit(EXIT_FAILURE)
    }
}
