import Foundation

/// Keeps line stamps aligned with the note text across arbitrary edits.
///
/// This is the whole trick of the app, kept free of AppKit so it can be tested:
/// the text stays plain, and every paragraph has a stamp beside it. The editor
/// calls `prepareEdit` while the old text is still in place, then `commitEdit`
/// once the change went through.
public struct StampBookkeeper {
    public private(set) var table: LineStampTable
    public private(set) var paragraphs: ParagraphIndex

    public init() {
        table = LineStampTable()
        paragraphs = ParagraphIndex()
    }

    public init(lines: [NoteSnapshot.Line]) {
        let lines = lines.isEmpty ? [NoteSnapshot.Line(text: "", stamp: nil)] : lines
        table = LineStampTable(stamps: lines.map(\.stamp))
        paragraphs = ParagraphIndex(text: lines.map(\.text).joined(separator: "\n"))
        table.ensureCount(paragraphs.count, filler: nil)
    }

    public var lineCount: Int { paragraphs.count }

    public func stamp(forLine index: Int) -> LineStamp? {
        table.stamp(forLine: index)
    }

    public func lines(in text: String) -> [NoteSnapshot.Line] {
        let text = text as NSString
        return paragraphs.ranges.enumerated().map { index, range in
            let safeRange = NSRange(
                location: min(range.location, text.length),
                length: min(range.length, max(0, text.length - min(range.location, text.length)))
            )
            return NoteSnapshot.Line(text: text.substring(with: safeRange), stamp: table.stamp(forLine: index))
        }
    }

    public mutating func prepareEdit(
        currentText: String,
        affectedRange: NSRange,
        replacement: String,
        stamp: LineStamp?
    ) {
        let text = currentText as NSString
        let clampedLocation = min(affectedRange.location, text.length)
        let clampedRange = NSRange(
            location: clampedLocation,
            length: min(affectedRange.length, text.length - clampedLocation)
        )
        let startLine = paragraphs.index(forCharacterAt: clampedRange.location)

        table.applyEdit(
            startLine: startLine,
            removedLineBreaks: ParagraphIndex.lineBreakCount(in: text.substring(with: clampedRange)),
            insertedLineBreaks: ParagraphIndex.lineBreakCount(in: replacement),
            newStamp: stamp
        )

        // A line started before the timer was running has no stamp. Writing into
        // it while the timer runs is the moment that line really begins.
        if !replacement.isEmpty, table.stamp(forLine: startLine) == nil, let stamp {
            table.setStamp(stamp, forLine: startLine)
        }
    }

    public mutating func commitEdit(newText: String, stamp: LineStamp?) {
        paragraphs.update(text: newText)
        table.ensureCount(paragraphs.count, filler: stamp)
    }

    public mutating func reset(lines: [NoteSnapshot.Line]) {
        self = StampBookkeeper(lines: lines)
    }
}
