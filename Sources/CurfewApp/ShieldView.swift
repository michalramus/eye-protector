import CurfewCore
import ShieldUI
import SwiftUI

/// What the shield is currently saying. Assembled by the agent from whatever
/// the daemon last answered, and nothing else: the screen holds no policy.
@MainActor
final class ShieldModel: ObservableObject {
    @Published var headline = "Curfew"
    @Published var detail = ""
    /// Why the last attempt was turned down, when it was.
    @Published var note: String?
    @Published var challenge: ChallengeModel?
}

struct ShieldView: View {
    @ObservedObject var model: ShieldModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                Text(model.headline)
                    .font(.system(size: 44, weight: .light))

                Text(model.detail)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let challenge = model.challenge {
                    ChallengeView(model: challenge) {
                        // Nothing to cancel to — the shield is the only thing
                        // on screen. Clearing what has been typed is the only
                        // honest meaning the button has here.
                        model.challenge = nil
                    }
                    .padding(.top, 8)
                }

                if let note = model.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(40)
        }
        .foregroundStyle(.white)
    }
}

/// The two-minute notice before the shield goes up.
struct CurfewWarningView: View {
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Curfew in \(Self.clock(remaining))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Text("Save what you are doing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    static func clock(_ remaining: TimeInterval) -> String {
        let seconds = Int(max(0, remaining).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
