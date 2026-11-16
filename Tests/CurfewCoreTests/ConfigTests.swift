import Foundation
import Testing

@testable import CurfewCore

private func decode(_ json: String) throws -> CurfewConfig {
    try JSONDecoder().decode(CurfewConfig.self, from: Data(json.utf8))
}

// MARK: - TimeOfDay

@Test("A well-formed time of day parses")
func parsesTime() {
    #expect(TimeOfDay("20:00") == TimeOfDay(hour: 20, minute: 0))
    #expect(TimeOfDay("00:00") == TimeOfDay(hour: 0, minute: 0))
    #expect(TimeOfDay("23:59") == TimeOfDay(hour: 23, minute: 59))
}

@Test("Malformed times of day do not parse")
func rejectsMalformedTimes() {
    for text in ["24:00", "7", "ab:cd", "", "12:60", "-1:00", "1:2:3"] {
        #expect(TimeOfDay(text) == nil)
    }
}

@Test("A nonsense hour and minute clamp rather than fail")
func clampsTime() {
    #expect(TimeOfDay(hour: 99, minute: 99) == TimeOfDay(hour: 23, minute: 59))
    #expect(TimeOfDay(hour: -5, minute: -5) == TimeOfDay(hour: 0, minute: 0))
}

@Test("A time of day round-trips through JSON as a plain string")
func timeRoundTrips() throws {
    let time = TimeOfDay(hour: 20, minute: 0)
    let data = try JSONEncoder().encode([time])
    #expect(String(decoding: data, as: UTF8.self) == "[\"20:00\"]")
    #expect(try JSONDecoder().decode([TimeOfDay].self, from: data) == [time])
}

// MARK: - CurfewConfig decoding

@Test("A config holding one key keeps every other field at its default")
func partialConfig() throws {
    let config = try decode(#"{"nightStart":"22:30"}"#)
    #expect(config.nightStart == TimeOfDay(hour: 22, minute: 30))
    #expect(
        config == CurfewConfig(nightStart: TimeOfDay(hour: 22, minute: 30))
    )
    #expect(config.nightEnd == CurfewConfig.default.nightEnd)
    #expect(config.weekendDays == CurfewConfig.default.weekendDays)
    #expect(config.nightGrace == CurfewConfig.default.nightGrace)
    #expect(config.weekendGrace == CurfewConfig.default.weekendGrace)
    #expect(config.warningLead == CurfewConfig.default.warningLead)
    #expect(config.challengeLength == CurfewConfig.default.challengeLength)
}

@Test("An empty config decodes to the default")
func emptyConfigIsDefault() throws {
    #expect(try decode("{}") == CurfewConfig.default)
}

@Test("A full config round-trips")
func configRoundTrips() throws {
    let config = CurfewConfig(
        nightStart: TimeOfDay(hour: 21, minute: 15),
        nightEnd: TimeOfDay(hour: 7, minute: 30),
        weekendDays: [6, 7],
        nightGrace: 600,
        weekendGrace: 900,
        warningLead: 60,
        challengeLength: 50
    )
    let data = try JSONEncoder().encode(config)
    #expect(try JSONDecoder().decode(CurfewConfig.self, from: data) == config)
}

@Test("A nightStart that is not a valid time fails to decode")
func invalidTimeThrows() {
    #expect(throws: DecodingError.self) { try decode(#"{"nightStart":"25:00"}"#) }
    #expect(throws: DecodingError.self) { try decode(#"{"nightStart":"banana"}"#) }
    #expect(throws: DecodingError.self) { try decode(#"{"nightStart":2000}"#) }
}

// MARK: - CurfewConfig clamping

@Test("Grace is clamped to its bounds")
func graceClamps() {
    let tooShort = CurfewConfig(nightGrace: 1, weekendGrace: 1)
    #expect(tooShort.nightGrace == CurfewConfig.graceBounds.lowerBound)
    #expect(tooShort.weekendGrace == CurfewConfig.graceBounds.lowerBound)

    let tooLong = CurfewConfig(nightGrace: 10 * 3600, weekendGrace: 10 * 3600)
    #expect(tooLong.nightGrace == CurfewConfig.graceBounds.upperBound)
    #expect(tooLong.weekendGrace == CurfewConfig.graceBounds.upperBound)
}

@Test("Challenge length is clamped to its bounds")
func challengeClamps() {
    #expect(CurfewConfig(challengeLength: 3).challengeLength == CurfewConfig.challengeBounds.lowerBound)
    #expect(CurfewConfig(challengeLength: 5000).challengeLength == CurfewConfig.challengeBounds.upperBound)
}

@Test("Out-of-range values clamp when decoded too")
func decodedValuesClamp() throws {
    let config = try decode(#"{"nightGrace":1,"challengeLength":5000}"#)
    #expect(config.nightGrace == CurfewConfig.graceBounds.lowerBound)
    #expect(config.challengeLength == CurfewConfig.challengeBounds.upperBound)
}

@Test("The warning lead is clamped to the shorter grace")
func warningLeadClamps() {
    let config = CurfewConfig(nightGrace: 300, weekendGrace: 1800, warningLead: 1000)
    #expect(config.warningLead == 300)

    let swapped = CurfewConfig(nightGrace: 1800, weekendGrace: 300, warningLead: 1000)
    #expect(swapped.warningLead == 300)
}

@Test("Weekday numbers outside 1 to 7 are dropped")
func weekendDaysFilter() {
    let config = CurfewConfig(weekendDays: [0, 1, 7, 8, -3])
    #expect(config.weekendDays == [1, 7])
}
