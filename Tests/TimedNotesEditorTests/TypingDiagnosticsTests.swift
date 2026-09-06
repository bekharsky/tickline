import AppKit
import XCTest
@testable import TimedNotesEditor
@testable import TimedNotesCore

/// Types into the real text view, the way the app does.
@MainActor
final class TypingTests: XCTestCase {
    /// The controller holds the timer weakly, like the app's model does, so the
    /// test has to own it.
    private var timer: TimerEngine?

    private func makeController() -> NoteEditorController {
        let controller = NoteEditorController()
        controller.editorView.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        controller.editorView.layoutSubtreeIfNeeded()
        return controller
    }

    private func timerRunning(on controller: NoteEditorController) -> TimerEngine {
        let timer = TimerEngine(duration: 3600)
        self.timer = timer
        controller.timer = timer
        timer.start()
        return timer
    }

    func testTypedTextLandsInTheEditorAndIsDrawn() throws {
        let controller = makeController()
        _ = timerRunning(on: controller)
        let textView = controller.textView

        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        textView.insertNewline(nil)
        textView.insertText("world", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.string, "hello\nworld")
        XCTAssertEqual(controller.lineCount, 2)

        let rep = try XCTUnwrap(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let background = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide - 2, y: rep.pixelsHigh - 2))
        var ink = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if abs(color.brightnessComponent - background.brightnessComponent) > 0.05 {
                    ink += 1
                }
            }
        }
        XCTAssertGreaterThan(ink, 200, "typed text should be drawn")
    }

    func testReturnStartsANewStampedLine() {
        let controller = makeController()
        _ = timerRunning(on: controller)
        let textView = controller.textView

        textView.insertText("first", replacementRange: NSRange(location: 0, length: 0))
        textView.insertNewline(nil)
        textView.insertText("second", replacementRange: textView.selectedRange())

        XCTAssertEqual(controller.lineCount, 2)
        XCTAssertNotEqual(controller.stampText(forLine: 0), "--:--:--")
        XCTAssertNotEqual(controller.stampText(forLine: 1), "--:--:--")
    }

    /// ⌘⏎ breaks the line but stays on the same stamp.
    func testCommandReturnKeepsTheLineAndItsStamp() throws {
        let controller = makeController()
        _ = timerRunning(on: controller)
        let textView = try XCTUnwrap(controller.textView as? TimedTextView)

        textView.insertText("one long thought", replacementRange: NSRange(location: 0, length: 0))
        let stampBefore = controller.stampText(forLine: 0)
        textView.insertSoftLineBreak()
        textView.insertText("continued below", replacementRange: textView.selectedRange())

        XCTAssertEqual(controller.lineCount, 1, "a soft break must not create a paragraph")
        XCTAssertEqual(controller.stampText(forLine: 0), stampBefore)
        XCTAssertTrue(textView.string.contains(ParagraphIndex.softLineBreak))
    }

    func testCommandReturnIsHandledAsAKeyEquivalent() throws {
        let controller = makeController()
        _ = timerRunning(on: controller)
        let textView = try XCTUnwrap(controller.textView as? TimedTextView)
        textView.insertText("line", replacementRange: NSRange(location: 0, length: 0))

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )

        XCTAssertTrue(textView.performKeyEquivalent(with: event))
        XCTAssertEqual(controller.lineCount, 1)
        XCTAssertTrue(textView.string.hasSuffix(String(ParagraphIndex.softLineBreak)))
    }

    func testCopyingASelectionKeepsTheStampsOfTheSelectedLines() {
        let controller = makeController()
        controller.format = .minutesOnly
        controller.load(lines: [
            NoteSnapshot.Line(text: "first", stamp: LineStamp(remaining: 3600, wallClock: Date())),
            NoteSnapshot.Line(text: "second", stamp: LineStamp(remaining: 3000, wallClock: Date())),
            NoteSnapshot.Line(text: "third", stamp: LineStamp(remaining: 60, wallClock: Date()))
        ])

        // Select the middle line only ("second" starts after "first\n").
        controller.textView.setSelectedRange(NSRange(location: 6, length: 6))
        XCTAssertEqual(controller.stampedText(selectionOnly: true), "[50] second")

        controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(
            controller.stampedText(selectionOnly: true),
            "[60] first\n[50] second\n[01] third",
            "no selection copies the whole note"
        )
    }

    func testExportIndentsSoftBrokenLinesUnderTheStamp() throws {
        let controller = makeController()
        controller.format = .minutesOnly
        // A fixed stamp instead of a live timer: this is about the layout of the
        // exported text, not about the clock.
        controller.load(lines: [
            NoteSnapshot.Line(text: "head", stamp: LineStamp(remaining: 3600, wallClock: Date()))
        ])

        let textView = try XCTUnwrap(controller.textView as? TimedTextView)
        textView.insertSoftLineBreak()
        textView.insertText("tail", replacementRange: textView.selectedRange())

        XCTAssertEqual(controller.stampedText(selectionOnly: false), "[60] head\n     tail")
    }
}
