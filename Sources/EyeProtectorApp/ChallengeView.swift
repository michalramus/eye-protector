import EyeProtectorCore
import SwiftUI

/// Which act the challenge is standing in front of. Kept because a skip
/// challenge stops being meaningful the moment the Break ends, while a quit
/// challenge never does.
enum ChallengeKind: Equatable {
    case skip
    case quit
}

@MainActor
final class ChallengeModel: ObservableObject {
    let kind: ChallengeKind
    @Published private(set) var challenge: Challenge
    @Published var typed: String = "" {
        didSet { clampAndCheck() }
    }

    let prompt: String
    private let onPassed: () -> Void
    private var isClamping = false

    init(kind: ChallengeKind, prompt: String, onPassed: @escaping () -> Void) {
        self.kind = kind
        self.prompt = prompt
        self.onPassed = onPassed
        challenge = .random()
    }

    var progress: Double {
        challenge.progress(of: typed)
    }

    /// The part already typed correctly, and the part still to go. Shown as
    /// two differently styled runs so the user can see where they are in a
    /// hundred undifferentiated characters.
    var split: (done: String, remaining: String) {
        let done = challenge.acceptedPrefix(of: typed)
        return (done, String(challenge.text.dropFirst(done.count)))
    }

    private func clampAndCheck() {
        guard !isClamping else { return }

        let accepted = challenge.acceptedPrefix(of: typed)
        if accepted != typed {
            // Live-lock: the wrong keystroke simply never lands, so there is
            // no end-of-run surprise and no restart from zero.
            isClamping = true
            typed = accepted
            isClamping = false
            return
        }

        if challenge.isSatisfied(by: typed) {
            onPassed()
        }
    }
}

struct ChallengeView: View {
    @ObservedObject var model: ChallengeModel
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.prompt)
                .font(.system(size: 13, weight: .medium))

            // Non-selectable by default, which is the point: this must be
            // read and typed, not copied.
            (Text(model.split.done).foregroundStyle(.tertiary)
                + Text(model.split.remaining).foregroundStyle(.primary))
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.disabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ChallengeField(text: $model.typed)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.separator)
                )

            HStack {
                ProgressView(value: model.progress)
                    .frame(width: 120)
                Text("\(model.split.done.count)/\(model.challenge.text.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(16)
        // Fixed rather than a maximum: under a narrow width proposal the
        // challenge string, which has nothing to break on, wraps to one
        // character per line and the panel becomes two thousand points tall.
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
