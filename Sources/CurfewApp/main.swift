import CurfewCore
import Darwin
import Foundation

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
    // Launched from Finder rather than from a shell — the only sensible
    // reading is "be the screen".
    if isatty(STDOUT_FILENO) == 1 {
        printStatus()
    } else {
        MainActor.assumeIsolated { CurfewAgent.run() }
    }

case .some(let unknown):
    print("curfew: unknown option \(unknown)")
    usage()
    exit(EXIT_FAILURE)
}
