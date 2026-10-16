import AppKit
import SwiftUI

@MainActor
final class WarningHUDModel: ObservableObject {
    @Published var remaining: TimeInterval = 0
}

struct WarningHUDView: View {
    @ObservedObject var model: WarningHUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
            Text("Break in \(Int(max(0, model.remaining).rounded()))s")
                .monospacedDigit()
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

/// A non-activating panel in the top-right of every Display.
///
/// Deliberately not a `UNUserNotificationCenter` notification: those need a
/// permission prompt, are suppressed by Do Not Disturb, and are exactly the
/// thing a fullscreen app hides — all of which would make the Warning
/// unreliable at precisely the moments it matters.
@MainActor
final class WarningHUD {
    let model = WarningHUDModel()
    private var panels: [NSPanel] = []
    private var builtFor: [String] = []
    private var isPresented = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresented else { return }
                self.present()
            }
        }
    }

    func present() {
        if builtFor != ScreenArrangement.signature {
            rebuild()
        }
        isPresented = true
        panels.forEach { $0.orderFrontRegardless() }
    }

    func dismiss() {
        isPresented = false
        panels.forEach { $0.orderOut(nil) }
    }

    private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        builtFor = ScreenArrangement.signature
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.joinEveryScreenLayer()
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true

            let host = NSHostingView(rootView: WarningHUDView(model: model))
            host.frame.size = host.fittingSize
            panel.contentView = host
            panel.setContentSize(host.fittingSize)

            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - host.fittingSize.width - 20,
                    y: visible.maxY - host.fittingSize.height - 20
                )
            )
            return panel
        }
    }
}
