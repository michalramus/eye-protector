import Foundation

/// The deliberate holes in Lockout, gathered in one place so that ADR 0004's
/// claim — that the safeguards are behind flags and can be tightened later —
/// is true of the code rather than only of the prose.
///
/// Every one of these exists because the alternatives all depend on this app's
/// own code being correct. They are the floor underneath that assumption.
public struct SafetyNets: Sendable, Equatable {
    /// Cmd-Opt-Esc keeps working while the Overlay is up.
    var forceQuitEnabled: Bool

    /// Log out, restart and shut down keep working while the Overlay is up.
    /// Never asked for as part of Lockout: being unable to restart the machine
    /// goes well beyond preventing a glance at another window.
    var sessionTerminationEnabled: Bool

    /// The user is guaranteed to reach Idle — where Start is one click away —
    /// no later than this long after a Break was due to end, whatever state
    /// the engine has got itself into.
    public var graceAfterBreak: TimeInterval

    /// How long the main thread may be unresponsive during Lockout before the
    /// process ends itself to release the screen. Generous, because a brief
    /// stall under load is normal and killing the app over one would be worse
    /// than the stall.
    public var mainThreadStallLimit: TimeInterval

    public init(
        forceQuitEnabled: Bool = true,
        sessionTerminationEnabled: Bool = true,
        graceAfterBreak: TimeInterval = 60,
        mainThreadStallLimit: TimeInterval = 10
    ) {
        self.forceQuitEnabled = forceQuitEnabled
        self.sessionTerminationEnabled = sessionTerminationEnabled
        self.graceAfterBreak = graceAfterBreak
        self.mainThreadStallLimit = mainThreadStallLimit
    }

    /// Today's setting: every net in place.
    public static let lenient = SafetyNets()

    /// The eventual destination, once the app has earned trust in daily use.
    ///
    /// `mainThreadStallLimit` survives even here: it is not a concession to
    /// the user's willpower, it is the floor under our own correctness.
    public static let strict = SafetyNets(
        forceQuitEnabled: false,
        sessionTerminationEnabled: false
    )
}

extension SafetyNets {
    /// Curfew's setting, chosen by the user of it: Force Quit goes, because
    /// an app that can be dismissed with a keystroke is not a curfew, while
    /// ending the session stays, because turning every problem into a held
    /// power button is a worse bargain than any discipline it buys.
    public static let curfew = SafetyNets(
        forceQuitEnabled: false,
        sessionTerminationEnabled: true
    )
}
