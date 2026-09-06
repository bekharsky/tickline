import Foundation

/// Paragraph ranges of the note text, excluding the trailing newline of each.
///
/// A note with N line breaks always has N + 1 paragraphs, including a final
/// empty one after a trailing newline — that empty line is where the writer is
/// about to type, so it needs a stamp like any other.
public struct ParagraphIndex: Equatable {
    public private(set) var ranges: [NSRange]

    public init(text: String = "") {
        ranges = Self.compute(text)
    }

    public var count: Int { ranges.count }

    public mutating func update(text: String) {
        ranges = Self.compute(text)
    }

    public func range(forLine index: Int) -> NSRange {
        guard ranges.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        return ranges[index]
    }

    public func index(forCharacterAt offset: Int) -> Int {
        var low = 0
        var high = ranges.count - 1
        while low < high {
            let middle = (low + high) / 2
            let range = ranges[middle]
            if offset < range.location {
                high = middle - 1
            } else if offset > range.location + range.length {
                low = middle + 1
            } else {
                return middle
            }
        }
        return max(0, min(low, ranges.count - 1))
    }

    /// Line indices touched by a character range, for drawing or bookkeeping.
    public func indexRange(intersecting characterRange: NSRange) -> Range<Int> {
        let first = index(forCharacterAt: characterRange.location)
        let last = index(forCharacterAt: NSMaxRange(characterRange))
        return first..<min(count, max(first, last) + 1)
    }

    public static func lineBreakCount(in string: String) -> Int {
        string.reduce(into: 0) { count, character in
            if character.isNewline {
                count += 1
            }
        }
    }

    private static func compute(_ string: String) -> [NSRange] {
        let text = string as NSString
        var ranges: [NSRange] = []
        var start = 0
        var index = 0

        while index < text.length {
            let character = text.character(at: index)
            if character == 0x0A || character == 0x0D {
                ranges.append(NSRange(location: start, length: index - start))
                // Treat CRLF as one break.
                if character == 0x0D, index + 1 < text.length, text.character(at: index + 1) == 0x0A {
                    index += 1
                }
                start = index + 1
            }
            index += 1
        }

        ranges.append(NSRange(location: start, length: text.length - start))
        return ranges
    }
}
