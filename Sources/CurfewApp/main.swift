import CurfewCore
import Darwin
import Foundation
import ShieldUI

/// One binary, four jobs: the root daemon, the GUI agent, the installer and a
/// way to ask what is going on without either.
///
/// One rather than four because the daemon has to be able to put the agent
/// back, and the surest way to keep two programs in step is for them to be
/// the same program.

let arguments = Array(CommandLine.arguments.dropFirst())
let paths = Paths.current

func usage() {
    print(
        """
        curfew — blocks the machine at night and at weekends, and charges a
        retyped string to buy it back.

          sudo curfew --install     install and start the daemon
          sudo curfew --uninstall   stop and remove it
          curfew --status           what the daemon thinks right now
          curfew --daemon           run the root half in the foreground
          curfew --agent            run the screen half in the foreground

        Config: \(paths.config) (root-owned; edit with sudo, the daemon
        reloads it within a second). CURFEW_ROOT relocates every path for
        development.
        """
    )
}

/// Where this binary actually is, so `--install` writes a plist that points at
/// the copy being run rather than at wherever it is supposed to live.
func runningBinary() -> String {
    let argument = CommandLine.arguments.first ?? Paths.installedBinary
    guard let resolved = realpath(argument, nil) else { return argument }
    defer { free(resolved) }
    return String(cString: resolved)
}

func printStatus() {
    do {
        let response = try ControlSocketClient(path: paths.socket).send(.status)
        guard case .status(let status) = response else {
            print("curfew: unexpected answer")
            exit(EXIT_FAILURE)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm:ss"
        print("period:    \(status.period.rawValue)")
        print("shield:    \(status.shield ? "up (\(status.cause?.rawValue ?? "?"))" : "down")")
        if let raisesAt = status.raisesAt {
            print("rises:     \(formatter.string(from: raisesAt))")
        }
        print("buys:      \(Int(status.grace / 60)) min")
        print("unlocks:   \(status.unlockCount)")
        print("daemon at: \(formatter.string(from: status.now))")
    } catch {
        print("curfew: cannot reach the daemon at \(paths.socket): \(error)")
        exit(EXIT_FAILURE)
    }
}

/// Held for the life of the process and never closed: the lock is the
/// descriptor, and `flock` drops it when the process dies, however it dies.
nonisolated(unsafe) var instanceLockDescriptor: Int32 = -1

/// One standalone Curfew per login session. A login item plus a double-click
/// would otherwise leave two processes ticking on one state file and both
/// engaging lockout, and killing one would leave the other holding the screen.
func takeInstanceLock(_ paths: Paths) {
    let descriptor = open(paths.instanceLock, O_CREAT | O_RDWR, 0o644)
    // If the lock file cannot even be opened, run anyway: refusing to start
    // would leave no curfew at all, which is the worse failure.
    guard descriptor >= 0 else { return }

    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        FileHandle.standardError.write(
            Data("curfew: already running; that copy is responsible for the screen\n".utf8)
        )
        exit(EXIT_SUCCESS)
    }
    instanceLockDescriptor = descriptor
}

/// Attempted once, not on every launch: the switch in System Settings is the
/// user's, and an app that re-registered each time it started would silently
/// undo them turning it off.
func registerLoginItemOnce(_ paths: Paths) {
    guard !FileManager.default.fileExists(atPath: paths.loginItemMarker) else { return }

    switch LoginItem.set(true) {
    case .success:
        FileManager.default.createFile(atPath: paths.loginItemMarker, contents: nil)
    case .failure(let error):
        // Ad-hoc signing may make `SMAppService` refuse (ADR 0001). A refused
        // registration must not stop the curfew from running.
        EventLog(path: paths.events).record("login item not registered: \(error)")
    }
}

switch arguments.first {
case "--daemon":
    CurfewDaemon(paths: paths).run()

case "--agent":
    MainActor.assumeIsolated { CurfewAgent.run() }

case "--install":
    do {
        try Installer(paths: paths).install(binary: runningBinary())
    } catch {
        print("curfew: \(error)")
        exit(EXIT_FAILURE)
    }

case "--uninstall":
    do {
        try Installer(paths: paths).uninstall()
    } catch {
        print("curfew: \(error)")
        exit(EXIT_FAILURE)
    }

case "--status":
    printStatus()

case "--help", "-h":
    usage()

case .none:
    if isatty(STDOUT_FILENO) == 1 {
        printStatus()
    } else {
        // Launched from Finder rather than from a shell. Ask the socket once
        // to find out whether an installed daemon is behind this launch.
        //
        // Unreachable means "standalone" here and not "shield up": the
        // fail-closed rule is about a daemon that was supposed to be there
        // and went quiet. At launch nothing was supposed to be there, and a
        // shield with no challenge would be a black screen with no way out.
        let installed = (try? ControlSocketClient(path: paths.socket).send(.status)) != nil
        if installed {
            MainActor.assumeIsolated { CurfewAgent.run() }
        } else {
            let userPaths = Paths.userMode()
            // Before anything that ticks or touches the state file.
            try? FileManager.default.createDirectory(
                atPath: userPaths.supportDirectory,
                withIntermediateDirectories: true
            )
            takeInstanceLock(userPaths)
            registerLoginItemOnce(userPaths)

            // Both halves in this process, under the user's own home and
            // with nothing to restart them: quitting ends it. Not a curfew,
            // see `Paths.userMode`.
            let daemon = CurfewDaemon(paths: userPaths)
            daemon.prepare()
            daemon.startTicking()
            MainActor.assumeIsolated { CurfewAgent.run(control: InProcessControl(daemon: daemon)) }
        }
    }

case .some(let unknown):
    print("curfew: unknown option \(unknown)")
    usage()
    exit(EXIT_FAILURE)
}
