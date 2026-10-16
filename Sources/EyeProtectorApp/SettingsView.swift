import SwiftUI
import EyeProtectorCore

/// Backs both places settings can be reached: the menu-bar popover during a
/// Session, and the gear on the Overlay while Idle. One view, two hosts.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var sessionMinutes: Int { didSet { pushConfig() } }
    @Published var breakSeconds: Int { didSet { pushConfig() } }
    @Published var warningEnabled: Bool { didSet { pushConfig() } }
    @Published var launchAtLogin: Bool { didSet { pushLoginItem() } }

    @Published var sessionsToday = 0
    @Published var escapesToday = 0
    @Published var loginItemError: String?

    var onConfigChange: (Config) -> Void = { _ in }
    var onQuit: () -> Void = {}

    private var isSyncing = false

    init(config: Config) {
        sessionMinutes = Self.minutes(config.sessionLength)
        breakSeconds = Self.seconds(config.breakLength)
        warningEnabled = config.warningEnabled
        launchAtLogin = LoginItem.isEnabled
    }

    private static func minutes(_ interval: TimeInterval) -> Int {
        Int((interval / 60).rounded())
    }

    private static func seconds(_ interval: TimeInterval) -> Int {
        Int(interval.rounded())
    }

    /// Pushed from the controller after every event. Guarded so that writing
    /// the engine's values back into the model does not look like a user edit.
    /// Only writes values that actually differ: this runs on every tick, and
    /// `@Published` republishes on assignment whether or not anything changed.
    func sync(config: Config, counters: Counters) {
        isSyncing = true
        defer { isSyncing = false }

        let minutes = Self.minutes(config.sessionLength)
        if sessionMinutes != minutes { sessionMinutes = minutes }

        let seconds = Self.seconds(config.breakLength)
        if breakSeconds != seconds { breakSeconds = seconds }

        if warningEnabled != config.warningEnabled {
            warningEnabled = config.warningEnabled
        }
        if sessionsToday != counters.sessionsToday {
            sessionsToday = counters.sessionsToday
        }
        if escapesToday != counters.escapesToday {
            escapesToday = counters.escapesToday
        }
    }

    private func pushConfig() {
        guard !isSyncing else { return }
        onConfigChange(
            Config(
                sessionLength: TimeInterval(sessionMinutes) * 60,
                breakLength: TimeInterval(breakSeconds),
                warningEnabled: warningEnabled,
                launchAtLogin: launchAtLogin
            )
        )
    }

    private func pushLoginItem() {
        guard !isSyncing else { return }
        switch LoginItem.set(launchAtLogin) {
        case .success(let actual):
            loginItemError = nil
            if actual != launchAtLogin {
                isSyncing = true
                launchAtLogin = actual
                isSyncing = false
            }
        case .failure(let error):
            loginItemError = error.localizedDescription
            isSyncing = true
            launchAtLogin = LoginItem.isEnabled
            isSyncing = false
        }
        pushConfig()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    /// Derived from `Config` rather than restated, so the stepper cannot
    /// drift away from the bounds the engine actually clamps to.
    private let sessionRange =
        Int(Config.sessionBounds.lowerBound / 60)...Int(Config.sessionBounds.upperBound / 60)
    private let breakRange =
        Int(Config.breakBounds.lowerBound)...Int(Config.breakBounds.upperBound)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper(
                "Session: \(model.sessionMinutes) min",
                value: $model.sessionMinutes,
                in: sessionRange
            )
            Stepper(
                "Break: \(model.breakSeconds) s",
                value: $model.breakSeconds,
                in: breakRange
            )

            Toggle(
                "Warn \(Int(Config.defaultWarningLead))s before a break",
                isOn: $model.warningEnabled
            )
            Toggle("Launch at login", isOn: $model.launchAtLogin)

            if let error = model.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("Today")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.sessionsToday) sessions · \(model.escapesToday) skipped")
                    .monospacedDigit()
            }
            .font(.callout)

            Divider()

            Button("Quit Eye Protector", action: model.onQuit)
        }
        .padding(16)
        .frame(width: 280)
    }
}
