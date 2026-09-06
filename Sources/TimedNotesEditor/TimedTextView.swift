import AppKit
import TimedNotesCore

/// Text view that separates the two kinds of line break.
///
/// Return ends a line and starts a new, freshly stamped one. Command-Return
/// breaks the line visually but stays inside the same paragraph, so it keeps the
/// stamp it already has — room for wrapped, richer lines later on.
final class TimedTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if flags == .command, isReturn {
            insertSoftLineBreak()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Also reachable as the standard Insert Line Break action (⌥⏎).
    override func insertLineBreak(_ sender: Any?) {
        insertSoftLineBreak()
    }

    func insertSoftLineBreak() {
        guard isEditable else { return }
        insertText(String(ParagraphIndex.softLineBreak), replacementRange: selectedRange())
    }
}
