import Darwin
import Foundation

/// Keeps the GUI agent loaded in whatever session is currently at the screen.
///
/// This is the half of ADR 0006 that answers "I will just kill it". A plain
/// `kill` is already handled by `KeepAlive`, in under a second. What
/// `KeepAlive` does not survive is `launchctl bootout gui/501/…`, which needs
/// no password and unloads the job for good — so root checks, every few
/// seconds, that the job is still there and bootstraps it back if it is not.
///
/// Doing this from the daemon rather than from the agent is not a style
/// choice: `bootstrap` into another user's GUI domain is a root-only
/// operation, and the agent is not root.
struct AgentSupervisor: Sendable {
    let paths: Paths

    /// The uid of whoever owns the console, or nil at the login window.
    ///
    /// `/dev/console` is owned by the user currently at the screen, which is
    /// the cheapest reliable answer to a question that otherwise needs
    /// SystemConfiguration.
    static func consoleUID() -> uid_t? {
        var info = stat()
        guard stat("/dev/console", &info) == 0 else { return nil }
        // root means nobody is logged in: loginwindow owns the console then.
        return info.st_uid == 0 ? nil : info.st_uid
    }

    func ensureAgentIsLoaded() {
        // Development runs against a relocated prefix have no business
        // touching the real launchd.
        guard !paths.isRelocated else { return }
        guard let uid = Self.consoleUID() else { return }

        if !FileManager.default.fileExists(atPath: paths.agentPlist) {
            // The plist is root-owned, so this only happens after a deliberate
            // `sudo rm`. Put it back and carry on.
            try? Installer(paths: paths).writeAgentPlist()
        }

        let target = "gui/\(uid)/\(Paths.agentLabel)"
        if launchctl(["print", target]) != 0 {
            launchctl(["bootstrap", "gui/\(uid)", paths.agentPlist])
        }
        // A job that is loaded but not running — `KeepAlive` has not caught up
        // yet, or it was stopped rather than booted out — starts here. Without
        // `-k`, so a healthy agent is left alone.
        launchctl(["kickstart", target])
    }

    @discardableResult
    private func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
