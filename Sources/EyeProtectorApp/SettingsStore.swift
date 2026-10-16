import Foundation
import EyeProtectorCore

/// `UserDefaults`-backed storage for the configurable values and the daily
/// counters. Counters are stored as loose keys rather than an encoded blob so
/// that `Counters` can stay a plain value type in the core.
@MainActor
final class SettingsStore {
    private enum Key {
        static let sessionLength = "sessionLength"
        static let breakLength = "breakLength"
        static let warningEnabled = "warningEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let countersDay = "countersDay"
        static let sessionsToday = "sessionsToday"
        static let escapesToday = "escapesToday"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var config: Config {
        get {
            let fallback = Config.default
            return Config(
                sessionLength: defaults.object(forKey: Key.sessionLength) as? TimeInterval
                    ?? fallback.sessionLength,
                breakLength: defaults.object(forKey: Key.breakLength) as? TimeInterval
                    ?? fallback.breakLength,
                warningEnabled: defaults.object(forKey: Key.warningEnabled) as? Bool
                    ?? fallback.warningEnabled,
                launchAtLogin: defaults.object(forKey: Key.launchAtLogin) as? Bool
                    ?? fallback.launchAtLogin
            )
        }
        set {
            defaults.set(newValue.sessionLength, forKey: Key.sessionLength)
            defaults.set(newValue.breakLength, forKey: Key.breakLength)
            defaults.set(newValue.warningEnabled, forKey: Key.warningEnabled)
            defaults.set(newValue.launchAtLogin, forKey: Key.launchAtLogin)
        }
    }

    func loadCounters() -> Counters? {
        guard let day = defaults.object(forKey: Key.countersDay) as? TimeInterval else {
            return nil
        }
        return Counters(
            day: Date(timeIntervalSince1970: day),
            sessionsToday: defaults.integer(forKey: Key.sessionsToday),
            escapesToday: defaults.integer(forKey: Key.escapesToday)
        )
    }

    func save(_ counters: Counters) {
        defaults.set(counters.day.timeIntervalSince1970, forKey: Key.countersDay)
        defaults.set(counters.sessionsToday, forKey: Key.sessionsToday)
        defaults.set(counters.escapesToday, forKey: Key.escapesToday)
    }
}
