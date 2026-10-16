import SwiftUI

/// What the Overlay is currently showing. Idle and Break look deliberately
/// different: during a Break there is nothing to press, which is the point.
enum OverlayPhase: Equatable {
    case idle
    case breaking(remaining: TimeInterval, escapable: Bool)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var phase: OverlayPhase = .idle
    /// Set while the user is holding the Escape key, 0...1.
    @Published var escapeProgress: Double = 0

    var onStart: () -> Void = {}
    var onQuit: () -> Void = {}
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.phase {
            case .idle:
                idle
            case .breaking(let remaining, let escapable):
                breaking(remaining: remaining, escapable: escapable)
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

            Button("Quit", action: model.onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    private func breaking(remaining: TimeInterval, escapable: Bool) -> some View {
        VStack(spacing: 20) {
            Text(String(format: "%.0f", max(0, remaining).rounded(.up)))
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Look at something 20 feet away")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)

            if escapable {
                escapeHint
            }
        }
    }

    private var escapeHint: some View {
        VStack(spacing: 8) {
            Text("Hold esc to skip")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            ProgressView(value: model.escapeProgress)
                .progressViewStyle(.linear)
                .frame(width: 140)
                .opacity(model.escapeProgress > 0 ? 1 : 0)
        }
        .padding(.top, 24)
    }
}
