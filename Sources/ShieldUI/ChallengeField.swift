import AppKit
import SwiftUI

/// A text view that refuses every way of getting text in other than the
/// keyboard.
///
/// Without this the challenge is theatre: the string is displayed in full on
/// screen, so a single Cmd-V would defeat it. Clamping the input to a valid
/// prefix is not enough on its own — a paste of the whole correct string is a
/// valid prefix.
///
/// Screenshot-and-OCR still works. Nothing here pretends otherwise; the goal
/// is to make skipping cost a deliberate half-minute, not to be unbeatable.
final class NoPasteTextView: NSTextView {
    override func paste(_ sender: Any?) {}
    override func pasteAsPlainText(_ sender: Any?) {}
    override func pasteAsRichText(_ sender: Any?) {}

    /// Services and drag-and-drop both land here.
    override func readSelection(from pboard: NSPasteboard) -> Bool { false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }

    /// Stops the Services menu offering to fill the field for us.
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        returnType == nil ? super.validRequestor(forSendType: sendType, returnType: returnType) : nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        if command, let key = event.charactersIgnoringModifiers?.lowercased() {
            // Paste, paste-and-match-style, and "select all then retype" are
            // all swallowed rather than passed up.
            if ["v", "a"].contains(key) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ChallengeField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NoPasteTextView {
        let view = NoPasteTextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.allowsUndo = false
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.unregisterDraggedTypes()

        // Lockout means there is nowhere else for keystrokes to go, so take
        // the focus rather than making the user click first.
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: NoPasteTextView, context: Context) {
        // Only write back when the clamp actually changed something, so the
        // insertion point is not reset on every keystroke.
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: text.count, length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }

        /// Newlines would let a multi-line paste masquerade as typing, and
        /// there is nothing to submit anyway — completion is detected from the
        /// text itself.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacement = replacementString else { return true }
            return !replacement.contains(where: \.isNewline)
        }
    }
}
