import Foundation

/// The document format: Markdown you can read in any editor.
///
/// Stamps are always written at full precision, whatever the toolbar is set to
/// show, so reopening a note keeps every detail level available:
///
/// ```
/// ---
/// timer: 01:00:00
/// remaining: 00:53:12.400
/// detail: h:m
/// ---
///
/// [00:59:56.246] first thought
/// [00:59:48.401] second thought
///                continued after a soft break
/// [--:--:--.---] written before the timer started
/// ```
public enum MarkdownNote {
    public static let placeholderField = "--:--:--.---"

    // MARK: - Writing

    public static func text(for snapshot: NoteSnapshot) -> String {
        var output = ["---", "timer: \(clockField(snapshot.duration))"]
        if let remaining = snapshot.heldRemaining {
            output.append("remaining: \(preciseField(remaining))")
        }
        output.append("detail: \(detailField(snapshot.format))")
        output.append("---")
        output.append("")

        let softBreak = String(ParagraphIndex.softLineBreak)
        for line in snapshot.lines {
            let field = line.stamp.map { preciseField($0.remaining) } ?? placeholderField
            let prefix = "[\(field)]"
            let indent = String(repeating: " ", count: prefix.count + 1)
            let parts = line.text.components(separatedBy: softBreak)

            output.append(trimmingTrailingSpaces(prefix + " " + (parts.first ?? "")))
            output.append(contentsOf: parts.dropFirst().map { trimmingTrailingSpaces(indent + $0) })
        }

        return output.joined(separator: "\n") + "\n"
    }

    // MARK: - Reading

    public static func snapshot(from text: String) -> NoteSnapshot {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // The file's terminating newline is not an empty note line.
        if body.last?.isEmpty == true {
            body.removeLast()
        }

        var duration: TimeInterval = 3600
        var heldRemaining: TimeInterval?
        var format = StampFormat.clock

        if body.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var index = 1
            while index < body.count, body[index].trimmingCharacters(in: .whitespaces) != "---" {
                let (key, value) = keyValue(in: body[index])
                switch key {
                case "timer": duration = seconds(from: value) ?? duration
                case "remaining": heldRemaining = seconds(from: value)
                case "detail": format = detail(from: value)
                default: break
                }
                index += 1
            }
            body.removeFirst(min(index + 1, body.count))
        }

        var lines: [NoteSnapshot.Line] = []
        var previousPrefixWidth = 0

        for raw in body {
            if let (stamp, text, prefixWidth) = prefixedLine(raw) {
                lines.append(NoteSnapshot.Line(text: text, stamp: stamp))
                previousPrefixWidth = prefixWidth
                continue
            }

            // An indented line continues the paragraph above it; anything else is
            // a line of its own, so plain Markdown opens sensibly too.
            let indent = raw.prefix { $0 == " " }.count
            if indent >= 2, var last = lines.popLast() {
                let content = String(raw.dropFirst(min(indent, previousPrefixWidth)))
                last.text += String(ParagraphIndex.softLineBreak) + content
                lines.append(last)
                continue
            }

            if lines.isEmpty, raw.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            lines.append(NoteSnapshot.Line(text: raw, stamp: nil))
            previousPrefixWidth = 0
        }

        return NoteSnapshot(
            duration: duration,
            heldRemaining: heldRemaining,
            format: format,
            lines: lines.isEmpty ? [NoteSnapshot.Line(text: "", stamp: nil)] : lines
        )
    }

    // MARK: - Fields

    private static func preciseField(_ value: TimeInterval) -> String {
        // Whole milliseconds, so 59.9996 cannot print as 60.000.
        let milliseconds = Int((abs(value) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = Double(milliseconds % 60_000) / 1000

        return String(format: "%@%02d:%02d:%06.3f", value < 0 ? "-" : "", hours, minutes, seconds)
    }

    private static func clockField(_ value: TimeInterval) -> String {
        let total = Int(abs(value).rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private static func detailField(_ format: StampFormat) -> String {
        var units: [String] = []
        if format.hours { units.append("h") }
        if format.minutes { units.append("m") }
        if format.seconds { units.append(format.subseconds ? "s.1" : "s") }
        return units.isEmpty ? "none" : units.joined(separator: ":")
    }

    /// Case-insensitive: notes written before the units went lowercase say
    /// `H:m:s`, and they have to keep opening the same way.
    private static func detail(from value: String) -> StampFormat {
        let units = value.lowercased().split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        return StampFormat(
            hours: units.contains("h"),
            minutes: units.contains("m"),
            seconds: units.contains { $0.hasPrefix("s") },
            subseconds: units.contains("s.1")
        )
    }

    private static func keyValue(in line: String) -> (String, String) {
        guard let separator = line.firstIndex(of: ":") else {
            return (line.trimmingCharacters(in: .whitespaces), "")
        }
        return (
            String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces),
            String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        )
    }

    /// Parses `HH:MM:SS.mmm`, signed. Other shapes are rejected on purpose: a
    /// shortened stamp like `[60]` is ambiguous between minutes and seconds.
    private static func seconds(from field: String) -> TimeInterval? {
        var field = field.trimmingCharacters(in: .whitespaces)
        var sign: TimeInterval = 1
        if field.hasPrefix("-") {
            sign = -1
            field.removeFirst()
        }

        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }

        return sign * (hours * 3600 + minutes * 60 + seconds)
    }

    private static func prefixedLine(_ raw: String) -> (LineStamp?, String, Int)? {
        guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { return nil }

        let field = String(raw[raw.index(after: raw.startIndex)..<close])
        let prefixWidth = raw.distance(from: raw.startIndex, to: close) + 2
        var text = String(raw[raw.index(after: close)...])
        if text.hasPrefix(" ") {
            text.removeFirst()
        }

        if field.allSatisfy({ $0 == "-" || $0 == ":" || $0 == "." }), field.contains("-") {
            return (nil, text, prefixWidth)
        }
        guard let remaining = seconds(from: field) else { return nil }
        return (LineStamp(remaining: remaining), text, prefixWidth)
    }

    private static func trimmingTrailingSpaces(_ line: String) -> String {
        var line = line
        while line.hasSuffix(" ") {
            line.removeLast()
        }
        return line
    }
}
