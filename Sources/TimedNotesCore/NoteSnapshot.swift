import Foundation

/// Everything needed to reopen a session exactly as it was left.
public struct NoteSnapshot: Codable, Equatable {
    public struct Line: Codable, Equatable {
        public var text: String
        public var stamp: LineStamp?

        public init(text: String, stamp: LineStamp?) {
            self.text = text
            self.stamp = stamp
        }
    }

    public var version: Int
    public var duration: TimeInterval
    /// Time left when the session was saved, `nil` if the timer never started.
    public var heldRemaining: TimeInterval?
    public var format: StampFormat
    public var lines: [Line]

    public init(
        version: Int = 1,
        duration: TimeInterval,
        heldRemaining: TimeInterval?,
        format: StampFormat,
        lines: [Line]
    ) {
        self.version = version
        self.duration = duration
        self.heldRemaining = heldRemaining
        self.format = format
        self.lines = lines
    }
}

public enum NoteExporter {
    /// Renders the note as plain text with the stamps put back in front of each
    /// line, right-aligned so the text column stays straight.
    public static func plainText(lines: [NoteSnapshot.Line], format: StampFormat) -> String {
        guard !format.isEmpty else {
            return lines.map(\.text).joined(separator: "\n")
        }

        let stamps = lines.map { line in
            line.stamp.map { StampFormatter.string(for: $0.remaining, format: format) }
                ?? StampFormatter.placeholder(for: format)
        }
        let width = stamps.map(\.count).max() ?? 0

        return zip(stamps, lines).map { stamp, line in
            let padded = String(repeating: " ", count: width - stamp.count) + stamp
            return "[\(padded)] \(line.text)"
        }
        .joined(separator: "\n")
    }
}

/// Autosaved single session in Application Support. One note, always where you
/// left it — no save dialogs in the writing path.
public struct SessionStore {
    public let fileURL: URL

    public init(directoryName: String = "TimedNotes", fileName: String = "session.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    }

    public func load() -> NoteSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(NoteSnapshot.self, from: data)
    }

    public func save(_ snapshot: NoteSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
