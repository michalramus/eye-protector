import Foundation
import Testing

@testable import EyeProtectorCore

/// Deterministic so a generation test cannot flake.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Test("A generated challenge is the requested length")
func generatedLength() {
    var generator = SeededGenerator(seed: 1)
    #expect(Challenge.random(using: &generator).text.count == 100)
    #expect(Challenge.random(length: 7, using: &generator).text.count == 7)
}

@Test("A generated challenge uses only the alphabet")
func generatedAlphabet() {
    var generator = SeededGenerator(seed: 2)
    let allowed = Set(Challenge.alphabet)
    #expect(Challenge.random(using: &generator).text.allSatisfy(allowed.contains))
}

@Test("Two challenges differ")
func generatedChallengesDiffer() {
    var generator = SeededGenerator(seed: 3)
    let first = Challenge.random(using: &generator)
    let second = Challenge.random(using: &generator)
    #expect(first != second)
}

@Test("A negative length yields an empty challenge rather than trapping")
func negativeLengthIsEmpty() {
    var generator = SeededGenerator(seed: 4)
    #expect(Challenge.random(length: -10, using: &generator).text.isEmpty)
}

// MARK: - Matching

private let challenge = Challenge(text: "aB3dE")

@Test("A correct run is accepted in full")
func correctPrefixAccepted() {
    #expect(challenge.acceptedPrefix(of: "aB3") == "aB3")
    #expect(challenge.acceptedPrefix(of: "aB3dE") == "aB3dE")
}

@Test("A wrong character truncates everything after it")
func wrongCharacterTruncates() {
    #expect(challenge.acceptedPrefix(of: "aB4dE") == "aB")
    #expect(challenge.acceptedPrefix(of: "x") == "")
}

@Test("Matching is case sensitive")
func matchingIsCaseSensitive() {
    #expect(challenge.acceptedPrefix(of: "ab3") == "a")
    #expect(!challenge.isSatisfied(by: "ab3de"))
}

@Test("Empty input is accepted as an empty prefix, not an error")
func emptyInputIsEmptyPrefix() {
    #expect(challenge.acceptedPrefix(of: "") == "")
    #expect(!challenge.isSatisfied(by: ""))
}

@Test("Trailing extra characters do not satisfy the challenge")
func overlongInputIsNotSatisfied() {
    #expect(challenge.acceptedPrefix(of: "aB3dEx") == "aB3dE")
    #expect(!challenge.isSatisfied(by: "aB3dEx"))
}

@Test("Only the exact string satisfies it")
func exactMatchSatisfies() {
    #expect(challenge.isSatisfied(by: "aB3dE"))
}

@Test("Progress tracks the accepted prefix, not what was typed")
func progressTracksAcceptedPrefix() {
    #expect(challenge.progress(of: "") == 0)
    #expect(challenge.progress(of: "aB") == 0.4)
    #expect(challenge.progress(of: "aXXXX") == 0.2)
    #expect(challenge.progress(of: "aB3dE") == 1)
}

@Test("An empty challenge is already satisfied rather than dividing by zero")
func emptyChallengeIsComplete() {
    #expect(Challenge(text: "").progress(of: "") == 1)
}
