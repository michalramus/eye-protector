import Foundation

/// Where everything lives, in one place.
///
/// Every path is under a root-owned directory, which is the point: a config
/// file the user can edit at 19:55 is not a curfew, and a state file the user
/// can edit is not a lock (ADR 0006).
///
/// `CURFEW_ROOT` relocates the whole layout under a prefix. That exists so
/// the daemon can be run by hand against a throwaway directory while it is
/// being written — a half-finished curfew must not be able to lock the
/// machine of the person finishing it.
struct Paths: Sendable {
    static let daemonLabel = "com.michalramus.curfew.daemon"
    static let agentLabel = "com.michalramus.curfew.agent"

    /// Where `--install` expects the binary to be. Inside the app bundle
    /// rather than in `/usr/local/libexec` so that there is exactly one copy
    /// to keep up to date.
    static let installedBinary = "/Applications/Curfew.app/Contents/MacOS/Curfew"

    static let current = Paths(
        prefix: ProcessInfo.processInfo.environment["CURFEW_ROOT"]
    )

    let prefix: String?

    var isRelocated: Bool { prefix != nil }

    private func path(_ absolute: String) -> String {
        guard let prefix else { return absolute }
        return prefix + absolute
    }

    var supportDirectory: String { path("/Library/Application Support/Curfew") }
    var config: String { supportDirectory + "/config.json" }
    var state: String { supportDirectory + "/state.json" }
    var events: String { supportDirectory + "/events.log" }

    /// Short on purpose: `sockaddr_un` has room for about a hundred
    /// characters and silently truncating a socket path is a bug that only
    /// shows up as "connection refused".
    var socket: String { path("/var/run/curfew.sock") }

    var daemonPlist: String { path("/Library/LaunchDaemons/\(Self.daemonLabel).plist") }
    var agentPlist: String { path("/Library/LaunchAgents/\(Self.agentLabel).plist") }
}
