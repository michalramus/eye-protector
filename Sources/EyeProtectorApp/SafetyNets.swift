import Foundation

/// The deliberate holes in Lockout, gathered in one place so that ADR 0004's
/// claim — that the safeguards are behind flags and can be tightened later —
/// is true of the code rather than only of the prose.
///
/// Every one of these exists because the alternatives all depend on this app's
/// own code being correct. They are the floor underneath that assumption.
struct SafetyNets: Sendable, Equatable {
    /// Cmd-Opt-Esc keeps working while the Overlay is up.
    var forceQuitEnabled: Bool = true

    /// Log out, restart and shut down keep working while the Overlay is up.
    /// Never asked for as part of Lockout: being unable to restart the machine
    /// goes well beyond preventing a glance at another window.
    var sessionTerminationEnabled: Bool = true

    /// The user is guaranteed to reach Idle — where Start is one click away —
    /// no later than this long after a Break was due to end, whatever state
    /// the engine has got itself into.
    var graceAfterBreak: TimeInterval = 60

    /// Today's setting: every net in place.
    static let lenient = SafetyNets()

    /// The eventual destination, once the app has earned trust in daily use.
    static let strict = SafetyNets(
        forceQuitEnabled: false,
        sessionTerminationEnabled: false
    )
}
