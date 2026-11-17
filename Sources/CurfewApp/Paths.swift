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

    /// The layout for a double-clicked `Curfew.app` with no daemon behind it:
    /// everything under the user's own home, so no root is needed to try it.
    ///
    /// This is explicitly not a curfew in the security sense. The state file
    /// belongs to the user who can edit it, which is exactly what ADR 0006 is
    /// about why the real layout does not allow. It exists to live with the
    /// thing before handing it root. There is no socket and no plist here;
    /// nothing in the standalone path reads either.
    static func userMode() -> Paths {
        Paths(prefix: nil, inUserMode: true)
    }

    let prefix: String?
    let inUserMode: Bool

    init(prefix: String?, inUserMode: Bool = false) {
        self.prefix = prefix
        self.inUserMode = inUserMode
    }

    /// Only the real root layout may touch launchd: a relocated run is a
    /// development run and a user-mode run has no root to do it with.
    var supervisesAgent: Bool { prefix == nil && !inUserMode }

    private func path(_ absolute: String) -> String {
        guard let prefix else { return absolute }
        return prefix + absolute
    }

    var supportDirectory: String {
        if inUserMode { return NSHomeDirectory() + "/Library/Application Support/Curfew" }
        return path("/Library/Application Support/Curfew")
    }
    var config: String { supportDirectory + "/config.json" }
    var state: String { supportDirectory + "/state.json" }
    var events: String { supportDirectory + "/events.log" }

    /// Present once Curfew has tried to register itself as a login item.
    var loginItemMarker: String { supportDirectory + "/login-item-registered" }

    /// Short on purpose: `sockaddr_un` has room for about a hundred
    /// characters and silently truncating a socket path is a bug that only
    /// shows up as "connection refused".
    var socket: String { path("/var/run/curfew.sock") }

    var daemonPlist: String { path("/Library/LaunchDaemons/\(Self.daemonLabel).plist") }
    var agentPlist: String { path("/Library/LaunchAgents/\(Self.agentLabel).plist") }
}
