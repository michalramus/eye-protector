import CurfewCore

/// What the agent needs from the daemon, whichever way it gets there.
///
/// A socket for the installed root daemon, a plain call for the standalone
/// app where both halves share a process. Every implementation is allowed to
/// throw, and the agent treats a throw as "shield up".
protocol CurfewControl: Sendable {
    func send(_ request: CurfewRequest) throws -> CurfewResponse
}

extension ControlSocketClient: CurfewControl {}

/// The daemon answering in the same process: no socket, no timeout, nothing
/// that can be unreachable.
struct InProcessControl: CurfewControl {
    let daemon: CurfewDaemon

    func send(_ request: CurfewRequest) throws -> CurfewResponse {
        daemon.handle(request)
    }
}
