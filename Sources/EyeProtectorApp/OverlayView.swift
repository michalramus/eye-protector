import SwiftUI

/// What the Overlay is currently showing. Idle and Break look deliberately
/// different: during a Break there is nothing to press but Skip, which is the
/// point.
enum OverlayPhase: Equatable {
    case idle
    case `break`(remaining: TimeInterval, escapable: Bool)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var phase: OverlayPhase = .idle
    @Published var showsSettings = false
    /// Non-nil while the user is working through a retype challenge.
    @Published var challenge: ChallengeModel?

    /// Settings are reachable from the Overlay because Lockout hides the menu
    /// bar: without this, a 180-minute Session could not be corrected without
    /// sitting through it.
    var settings: SettingsModel?

    var onStart: () -> Void = {}
    /// Called only once a skip challenge has been typed out in full.
    var onSkip: () -> Void = {}
    /// Called only once a quit challenge has been typed out in full.
    var onQuit: () -> Void = {}

    func beginSkipChallenge() {
        challenge = ChallengeModel(
            kind: .skip,
            prompt: "Type this exactly to skip the rest of your break."
        ) { [weak self] in
            self?.challenge = nil
            self?.onSkip()
        }
    }

    func beginQuitChallenge() {
        challenge = ChallengeModel(
            kind: .quit,
            prompt: "Type this exactly to quit Eye Protector."
        ) { [weak self] in
            self?.challenge = nil
            self?.onQuit()
        }
    }

    func cancelChallenge() {
        challenge = nil
    }

    /// The Break ended on its own while the user was still typing. Finishing
    /// now would skip nothing, so drop it rather than let them spend another
    /// fifty keystrokes on a no-op.
    func abandonSkipChallenge() {
        if challenge?.kind == .skip {
            challenge = nil
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let challenge = model.challenge {
                ChallengeView(model: challenge) {
                    model.cancelChallenge()
                }
            } else {
                switch model.phase {
                case .idle:
                    idle
                case .break(let remaining, let escapable):
                    breakScreen(remaining: remaining, escapable: escapable)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var idle: some View {
        VStack(spacing: 28) {
            Text("Eye Protector")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Button(action: model.onStart) {
                Text("Start session")
                    .font(.system(size: 20, weight: .medium))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 18) {
                Button {
                    model.showsSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button("Quit", action: model.beginQuitChallenge)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)

            if model.showsSettings, let settings = model.settings {
                SettingsView(model: settings)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func breakScreen(remaining: TimeInterval, escapable: Bool) -> some View {
        VStack(spacing: 20) {
            Text(String(format: "%.0f", max(0, remaining).rounded(.up)))
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Look at something 20 feet away")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)

            if escapable {
                Button("Skip this break", action: model.beginSkipChallenge)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
        }
    }
}
