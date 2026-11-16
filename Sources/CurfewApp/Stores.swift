import CurfewCore
import Foundation

/// The state file, owned by root and read back fail-closed.
///
/// Anything that goes wrong here — missing file, truncated JSON, a schema
/// from a future version — produces a state with no grace in it. Deleting the
/// file is therefore a way to lock yourself out and never a way in, which is
/// the only direction an error in this app is allowed to point.
struct StateStore: Sendable {
    let path: String

    func load(now: Date) -> CurfewState {
        guard
            let data = FileManager.default.contents(atPath: path),
            let state = try? CurfewCoding.decoder.decode(CurfewState.self, from: data)
        else {
            return CurfewPolicy.freshState(now: now)
        }
        return state
    }

    func save(_ state: CurfewState) throws {
        let data = try CurfewCoding.encoder.encode(state)
        // Atomic: the replacement is a rename, so a crash mid-write leaves
        // the previous state rather than half of this one.
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }
}

/// The config file, owned by root and edited with `sudo` on purpose.
///
/// A config that fails to parse falls back to the default curfew rather than
/// to no curfew: a stray comma must not be a night off.
struct ConfigStore: Sendable {
    let path: String

    func load() -> CurfewConfig {
        guard
            let data = FileManager.default.contents(atPath: path),
            let config = try? CurfewCoding.decoder.decode(CurfewConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    func modifiedAt() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    func writeIfMissing(_ config: CurfewConfig) throws {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let encoder = CurfewCoding.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: URL(fileURLWithPath: path), options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: path
        )
    }
}

/// An append-only record of what the curfew did.
///
/// Kept because the only honest way to find out whether this app helps is to
/// look at how often it was paid off, and memory is a poor witness at 02:00.
struct EventLog: Sendable {
    let path: String

    func record(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: path
            )
        }
    }
}
