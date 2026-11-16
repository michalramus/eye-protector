import CurfewCore
import Darwin
import Foundation

enum SocketError: Error, CustomStringConvertible {
    case failed(String, errno: Int32)
    case pathTooLong(String)
    case malformedResponse

    var description: String {
        switch self {
        case .failed(let what, let code):
            "\(what) failed: \(String(cString: strerror(code))) (\(code))"
        case .pathTooLong(let path):
            "socket path is too long for sockaddr_un: \(path)"
        case .malformedResponse:
            "the daemon sent something that is not a response"
        }
    }
}

/// `sockaddr_un` is a C struct with a fixed-size character array in it, and
/// Swift imports that array as a tuple of 104 `CChar`s. This is the usual
/// dance to get a path into it.
private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }

    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    return address
}

private func withAddress<T>(
    _ address: inout sockaddr_un,
    _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
) -> T {
    withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
            body(rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

/// Reads one newline-terminated message, refusing to grow without bound.
private func readLine(from descriptor: Int32) -> Data? {
    var message = Data()
    var byte: UInt8 = 0
    while message.count < CurfewCoding.maximumMessageBytes {
        let got = read(descriptor, &byte, 1)
        if got <= 0 { return message.isEmpty ? nil : message }
        if byte == UInt8(ascii: "\n") { return message }
        message.append(byte)
    }
    return nil
}

private func write(_ data: Data, to descriptor: Int32) {
    var payload = data
    payload.append(UInt8(ascii: "\n"))
    payload.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let written = write(descriptor, raw.baseAddress! + offset, raw.count - offset)
            if written <= 0 { return }
            offset += written
        }
    }
}

/// The daemon's half: one request per connection, answered and closed.
///
/// Any local user can connect, because the agent runs as whoever is logged
/// in. That is not a hole: the only thing a connection can achieve is to
/// submit text that has to match a challenge the daemon issued and is holding
/// in memory. See ADR 0006 for what this does and does not defend against.
final class ControlSocketServer: @unchecked Sendable {
    private let path: String
    private let handler: @Sendable (CurfewRequest) -> CurfewResponse
    private var listener: Int32 = -1

    init(path: String, handler: @escaping @Sendable (CurfewRequest) -> CurfewResponse) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError.failed("socket", errno: errno) }

        // A socket left behind by a killed daemon would otherwise make every
        // restart fail with EADDRINUSE.
        unlink(path)

        var address = try makeAddress(path)
        let bound = withAddress(&address) { pointer, length in
            bind(descriptor, pointer, length)
        }
        guard bound == 0 else {
            close(descriptor)
            throw SocketError.failed("bind", errno: errno)
        }
        guard listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw SocketError.failed("listen", errno: errno)
        }
        chmod(path, 0o666)

        listener = descriptor
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "curfew.socket"
        thread.start()
    }

    private func acceptLoop() {
        while true {
            let connection = accept(listener, nil, nil)
            if connection < 0 {
                if errno == EINTR { continue }
                // Nothing to be done from here; the daemon is more useful
                // deaf than dead, and launchd restarts it if it exits.
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            defer { close(connection) }

            guard
                let line = readLine(from: connection),
                let request = try? CurfewCoding.decoder.decode(CurfewRequest.self, from: line)
            else { continue }

            let response = handler(request)
            if let data = try? CurfewCoding.encoder.encode(response) {
                write(data, to: connection)
            }
        }
    }
}

/// The agent's half: connect, ask, read, close.
///
/// Every call is allowed to fail, and failing means the shield goes up. The
/// agent must never treat "I could not reach the daemon" as "carry on".
struct ControlSocketClient: Sendable {
    let path: String
    var timeout: TimeInterval = 2

    func send(_ request: CurfewRequest) throws -> CurfewResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError.failed("socket", errno: errno) }
        defer { close(descriptor) }

        var limit = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000)
        )
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = try makeAddress(path)
        let connected = withAddress(&address) { pointer, length in
            connect(descriptor, pointer, length)
        }
        guard connected == 0 else { throw SocketError.failed("connect", errno: errno) }

        write(try CurfewCoding.encoder.encode(request), to: descriptor)

        guard
            let line = readLine(from: descriptor),
            let response = try? CurfewCoding.decoder.decode(CurfewResponse.self, from: line)
        else { throw SocketError.malformedResponse }
        return response
    }
}
