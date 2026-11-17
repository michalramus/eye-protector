import AppKit
import CurfewCore
import EyeProtectorCore
import Foundation
import ShieldUI

/// The user-session half of Curfew: a screen with no opinions.
///
/// It asks the daemon what to show, shows it, and reports what was typed. It
/// never decides that the shield can come down — not even when it cannot
/// reach the daemon, which is the case it most wants to.
@MainActor
final class CurfewAgent: NSObject, NSApplicationDelegate {
    private let client: any CurfewControl
    private let shield = ShieldController()
    private var ticker: Timer?
    private var requestInFlight = false
    /// The challenge currently on screen, so that a poll every second does
    /// not throw away what is being typed.
    private var shownChallenge: String?

    init(control: any CurfewControl) {
        client = control
    }

    convenience init(paths: Paths = .current) {
        self.init(control: ControlSocketClient(path: paths.socket))
    }

    static func run(control: any CurfewControl = ControlSocketClient(path: Paths.current.socket)) -> Never {
        let app = NSApplication.shared
        let agent = CurfewAgent(control: control)
        app.delegate = agent
        // NSApplication does not retain its delegate.
        objc_setAssociatedObject(app, "curfew.agent", agent, .OBJC_ASSOCIATION_RETAIN)
        app.setActivationPolicy(.accessory)
        app.run()
        exit(EXIT_SUCCESS)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainThreadWatchdog.shared.start(stallLimit: SafetyNets.lenient.mainThreadStallLimit)
        poll()

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                MainThreadWatchdog.shared.beat()
                self?.poll()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Talking to the daemon

    private func poll() {
        guard !requestInFlight else { return }
        requestInFlight = true
        let client = self.client

        DispatchQueue.global(qos: .utility).async {
            let status: CurfewStatus
            if case .status(let fresh)? = try? client.send(.status) {
                status = fresh
            } else {
                // Fail closed. A daemon that cannot be reached is a curfew
                // that cannot be lifted, never one that has been lifted.
                status = .unreachable(now: Date())
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.requestInFlight = false
                    self.apply(status)
                }
            }
        }
    }

    private func submit(_ text: String) {
        let client = self.client
        DispatchQueue.global(qos: .userInitiated).async {
            let response = try? client.send(.submit(text: text))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.handle(response)
                }
            }
        }
    }

    private func handle(_ response: CurfewResponse?) {
        shownChallenge = nil
        shield.model.challenge = nil

        switch response {
        case .unlocked:
            shield.model.note = nil
            shield.dismiss()
        case .rejected(let reason):
            shield.model.note = reason
        default:
            shield.model.note = "The daemon did not answer. Trying again."
        }
        poll()
    }

    // MARK: - Showing it

    private func apply(_ status: CurfewStatus) {
        guard status.shield else {
            shownChallenge = nil
            shield.model.challenge = nil
            shield.model.note = nil
            shield.dismiss()

            if status.warning, let raisesAt = status.raisesAt {
                shield.showWarning(remaining: raisesAt.timeIntervalSince(status.now))
            } else {
                shield.hideWarning()
            }
            return
        }

        shield.model.headline = Self.headline(for: status)
        shield.model.detail = Self.detail(for: status)

        if let text = status.challenge {
            if shownChallenge != text || shield.model.challenge == nil {
                shownChallenge = text
                shield.model.challenge = ChallengeModel(
                    prompt: "Type this exactly. It cannot be pasted.",
                    challenge: Challenge(text: text)
                ) { [weak self] in
                    self?.submit(text)
                }
            }
        } else {
            shownChallenge = nil
            shield.model.challenge = nil
        }

        shield.hideWarning()
        shield.present()
    }

    private static func headline(for status: CurfewStatus) -> String {
        switch status.cause {
        case .night: "Night curfew"
        case .weekend: "Weekend"
        case .clockRolledBack: "Clock moved back"
        case .daemonUnreachable: "Curfew unavailable"
        case nil: "Curfew"
        }
    }

    private static func detail(for status: CurfewStatus) -> String {
        switch status.cause {
        case .daemonUnreachable:
            "The curfew daemon is not answering, so there is nothing to type. "
                + "It is restarted automatically; this screen lifts when it is back."
        case .clockRolledBack:
            "The system clock went backwards. The shield stays up until real time "
                + "catches up with where the clock used to be."
        default:
            "Typing the string below buys \(Int(status.grace / 60)) minutes. "
                + "Bought so far: \(status.unlockCount)."
        }
    }
}
