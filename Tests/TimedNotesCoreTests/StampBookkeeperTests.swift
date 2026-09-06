import XCTest
@testable import TimedNotesCore

/// Drives the bookkeeper the same way the text view does: `prepareEdit` on the
/// old text, then `commitEdit` on the new one.
private struct EditorHarness {
    var text = ""
    var bookkeeper = StampBookkeeper()
    var caret = 0

    mutating func type(_ string: String, remaining: TimeInterval?) {
        replace(NSRange(location: caret, length: 0), with: string, remaining: remaining)
    }

    mutating func replace(_ range: NSRange, with string: String, remaining: TimeInterval?) {
        let stamp = remaining.map { LineStamp(remaining: $0, wallClock: Date(timeIntervalSince1970: $0)) }
        bookkeeper.prepareEdit(currentText: text, affectedRange: range, replacement: string, stamp: stamp)
        text = (text as NSString).replacingCharacters(in: range, with: string)
        bookkeeper.commitEdit(newText: text, stamp: stamp)
        caret = range.location + (string as NSString).length
    }

    var stamps: [TimeInterval?] {
        bookkeeper.table.stamps.map { $0?.remaining }
    }

    var lineTexts: [String] {
        bookkeeper.lines(in: text).map(\.text)
    }
}

final class StampBookkeeperTests: XCTestCase {
    func testEachNewLineStartsWithTheTimeLeftAtThatMoment() {
        var editor = EditorHarness()
        editor.type("first thought", remaining: 3600)
        editor.type("\n", remaining: 3570)
        editor.type("second thought", remaining: 3569)
        editor.type("\n", remaining: 3500)
        editor.type("third", remaining: 3499)

        XCTAssertEqual(editor.lineTexts, ["first thought", "second thought", "third"])
        XCTAssertEqual(editor.stamps, [3600, 3570, 3500])
    }

    func testKeepsTypingInsideALineOnTheOriginalStamp() {
        var editor = EditorHarness()
        editor.type("hello", remaining: 3600)
        editor.type("\n", remaining: 3000)
        editor.type("world", remaining: 2999)

        // Go back and extend the first line.
        editor.replace(NSRange(location: 5, length: 0), with: " there", remaining: 1000)

        XCTAssertEqual(editor.lineTexts, ["hello there", "world"])
        XCTAssertEqual(editor.stamps, [3600, 3000])
    }

    func testLinesWrittenBeforeTheTimerHaveNoStampUntilWritingContinues() {
        var editor = EditorHarness()
        editor.type("draft before start", remaining: nil)
        XCTAssertEqual(editor.stamps, [nil])

        editor.type("!", remaining: 3600)
        XCTAssertEqual(editor.stamps, [3600], "the line really begins when the timer is running")
    }

    func testTrailingNewlineLeavesAStampedEmptyLineToWriteOn() {
        var editor = EditorHarness()
        editor.type("done", remaining: 3600)
        editor.type("\n", remaining: 3540)

        XCTAssertEqual(editor.lineTexts, ["done", ""])
        XCTAssertEqual(editor.stamps, [3600, 3540])
    }

    func testDeletingALineBreakMergesIntoTheEarlierLine() {
        var editor = EditorHarness()
        editor.type("one", remaining: 3600)
        editor.type("\n", remaining: 3000)
        editor.type("two", remaining: 2999)

        // Backspace over the line break.
        editor.replace(NSRange(location: 3, length: 1), with: "", remaining: 2000)

        XCTAssertEqual(editor.lineTexts, ["onetwo"])
        XCTAssertEqual(editor.stamps, [3600])
    }

    func testPastedBlockStampsEveryNewLine() {
        var editor = EditorHarness()
        editor.type("intro", remaining: 3600)
        editor.type("\n", remaining: 3590)
        editor.type("a\nb\nc", remaining: 3580)

        XCTAssertEqual(editor.lineTexts, ["intro", "a", "b", "c"])
        XCTAssertEqual(editor.stamps, [3600, 3590, 3580, 3580])
    }

    func testSplittingAnOldLineStampsOnlyTheNewTail() {
        var editor = EditorHarness()
        editor.type("head and tail", remaining: 3600)
        editor.replace(NSRange(location: 4, length: 0), with: "\n", remaining: 1200)

        XCTAssertEqual(editor.lineTexts, ["head", " and tail"])
        XCTAssertEqual(editor.stamps, [3600, 1200])
    }

    func testReplacingASelectionAcrossLines() {
        var editor = EditorHarness()
        editor.type("one", remaining: 3600)
        editor.type("\n", remaining: 3500)
        editor.type("two", remaining: 3499)
        editor.type("\n", remaining: 3400)
        editor.type("three", remaining: 3399)

        // Select from the middle of line 0 through the middle of line 2.
        editor.replace(NSRange(location: 2, length: 8), with: "X", remaining: 600)

        XCTAssertEqual(editor.lineTexts, ["onXree"])
        XCTAssertEqual(editor.stamps, [3600])
    }

    func testOvertimeStampsAreKept() {
        var editor = EditorHarness()
        editor.type("still going", remaining: 5)
        editor.type("\n", remaining: -12.5)
        editor.type("past the deadline", remaining: -13)

        XCTAssertEqual(editor.stamps, [5, -12.5])
        XCTAssertEqual(
            StampFormatter.string(for: editor.stamps[1] ?? 0, format: .clock),
            "-00:00:12"
        )
    }

    func testLineCountAlwaysMatchesTheStampCount() {
        var editor = EditorHarness()
        editor.type("a\nb\nc\n\nd", remaining: 3600)
        editor.replace(NSRange(location: 0, length: 8), with: "", remaining: 3000)
        editor.type("\n\n\n", remaining: 2000)

        XCTAssertEqual(editor.bookkeeper.lineCount, editor.bookkeeper.table.lineCount)
        XCTAssertEqual(editor.bookkeeper.lineCount, editor.lineTexts.count)
    }

    func testRoundTripThroughASnapshot() {
        var editor = EditorHarness()
        editor.type("one", remaining: 3600)
        editor.type("\n", remaining: 3400)
        editor.type("two", remaining: 3399)

        let lines = editor.bookkeeper.lines(in: editor.text)
        let restored = StampBookkeeper(lines: lines)

        XCTAssertEqual(restored.lineCount, 2)
        XCTAssertEqual(restored.stamp(forLine: 0)?.remaining, 3600)
        XCTAssertEqual(restored.stamp(forLine: 1)?.remaining, 3400)
        XCTAssertEqual(
            NoteExporter.plainText(lines: lines, format: .minutesOnly),
            "[60] one\n[56] two"
        )
    }
}
