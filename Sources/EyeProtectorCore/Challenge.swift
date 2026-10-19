import Foundation

/// A string the user must retype, exactly, to skip a Break or quit the app.
///
/// The point is cost, not secrecy: the string is shown in full on screen. What
/// it buys is that abandoning a Break can no longer be done by reflex — a
/// hundred characters is roughly half a minute of deliberate typing, which is
/// long enough to notice you are doing it.
///
/// Pure and here in the core so that generation and matching are tested
/// without a window; the parts that cannot be tested are the ones that stop
/// the string being pasted rather than typed.
public struct Challenge: Equatable, Sendable {
    /// Full alphanumeric, look-alikes included. Chosen deliberately over an
    /// unambiguous alphabet: distinguishing `l` from `1` is part of the cost.
    public static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    public static let defaultLength = 100

    public let text: String

    public init(text: String) {
        self.text = text
    }

    public static func random<G: RandomNumberGenerator>(
        length: Int = defaultLength,
        using generator: inout G
    ) -> Challenge {
        Challenge(
            text: String(
                (0..<max(0, length)).map { _ in
                    alphabet.randomElement(using: &generator)!
                }
            )
        )
    }

    public static func random(length: Int = defaultLength) -> Challenge {
        var generator = SystemRandomNumberGenerator()
        return random(length: length, using: &generator)
    }

    /// The longest leading run of `typed` that still matches.
    ///
    /// This is what makes the live-lock work: the field keeps only what this
    /// returns, so a wrong keystroke never lands and the user is never told at
    /// character 100 that they went wrong at character 12.
    public func acceptedPrefix(of typed: String) -> String {
        var accepted = ""
        for (typedCharacter, expected) in zip(typed, text) {
            guard typedCharacter == expected else { break }
            accepted.append(typedCharacter)
        }
        return accepted
    }

    public func isSatisfied(by typed: String) -> Bool {
        typed == text
    }

    /// 0...1, for a progress indicator.
    public func progress(of typed: String) -> Double {
        guard !text.isEmpty else { return 1 }
        return Double(acceptedPrefix(of: typed).count) / Double(text.count)
    }
}
