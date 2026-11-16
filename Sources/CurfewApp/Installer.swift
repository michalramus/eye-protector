import Darwin
import Foundation

/// Puts the two launchd jobs in place, and takes them away again.
///
/// Both plists are written as root into root-owned directories, which is what
/// makes `sudo` the price of removing the curfew. The daemon is bootstrapped
/// here; the agent is left to the daemon, which knows which session is at the
/// screen and will put it back every few seconds anyway.
struct Installer: Sendable {
    enum Failure: Error, CustomStringConvertible {
        case notRoot
        case missingBinary(String)

        var description: String {
            switch self {
            case .notRoot:
                "this needs root: sudo \(Paths.installedBinary) --install"
            case .missingBinary(let path):
                "no binary at \(path)"
            }
        }
    }

    let paths: Paths

    func install(binary: String) throws {
        guard geteuid() == 0 else { throw Failure.notRoot }
        guard FileManager.default.fileExists(atPath: binary) else {
            throw Failure.missingBinary(binary)
        }

        try FileManager.default.createDirectory(
            atPath: paths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0]
        )
        try ConfigStore(path: paths.config).writeIfMissing(.default)

        try write(daemonPlist(binary: binary), to: paths.daemonPlist)
        try write(agentPlist(binary: binary), to: paths.agentPlist)

        launchctl(["bootout", "system/\(Paths.daemonLabel)"])
        launchctl(["bootstrap", "system", paths.daemonPlist])
        launchctl(["kickstart", "system/\(Paths.daemonLabel)"])

        print("installed.")
        print("  daemon:  \(paths.daemonPlist)")
        print("  agent:   \(paths.agentPlist)")
        print("  config:  \(paths.config)   (edit with sudo, the daemon reloads it)")
        print("  state:   \(paths.state)")
        print("  log:     \(paths.events)")
        print("")
        print("to remove: sudo \(binary) --uninstall")
    }

    func uninstall() throws {
        guard geteuid() == 0 else { throw Failure.notRoot }

        if let uid = AgentSupervisor.consoleUID() {
            launchctl(["bootout", "gui/\(uid)/\(Paths.agentLabel)"])
        }
        launchctl(["bootout", "system/\(Paths.daemonLabel)"])

        try? FileManager.default.removeItem(atPath: paths.daemonPlist)
        try? FileManager.default.removeItem(atPath: paths.agentPlist)
        try? FileManager.default.removeItem(atPath: paths.state)

        print("removed. \(paths.supportDirectory) kept: the config and the log are in there.")
    }

    /// Also called by the daemon, which puts the agent plist back if it goes
    /// missing between installs.
    func writeAgentPlist() throws {
        try write(agentPlist(binary: Paths.installedBinary), to: paths.agentPlist)
    }

    private func write(_ contents: String, to path: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
            ofItemAtPath: path
        )
    }

    private func daemonPlist(binary: String) -> String {
        plist(
            label: Paths.daemonLabel,
            arguments: [binary, "--daemon"],
            extra: """
                    <key>StandardErrorPath</key>
                    <string>\(paths.supportDirectory)/daemon.log</string>
                """
        )
    }

    private func agentPlist(binary: String) -> String {
        plist(
            label: Paths.agentLabel,
            arguments: [binary, "--agent"],
            // Aqua only: a shield has nothing to draw on in an ssh session,
            // and loading it there would only produce a crash loop.
            extra: """
                    <key>LimitLoadToSessionType</key>
                    <string>Aqua</string>
                """
        )
    }

    private func plist(label: String, arguments: [String], extra: String) -> String {
        let argumentXML = arguments
            .map { "        <string>\($0)</string>" }
            .joined(separator: "\n")

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
            \(argumentXML)
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            \(extra)
            </dict>
            </plist>

            """
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
