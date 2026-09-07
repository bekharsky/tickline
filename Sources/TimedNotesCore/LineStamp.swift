import Foundation

/// The moment a note line was started, kept at full precision.
///
/// Everything the UI shows is derived from `remaining`, so the displayed
/// granularity can be changed at any time — before or long after writing —
/// without losing information.
public struct LineStamp: Codable, Equatable {
    /// Seconds left on the timer when the line was started.
    /// Negative once the timer has run out and writing continues.
    public var remaining: TimeInterval
    /// Calendar time of the same moment. Known while writing, but not carried by
    /// the Markdown file, which records offsets from the timer instead.
    public var wallClock: Date?

    public init(remaining: TimeInterval, wallClock: Date? = nil) {
        self.remaining = remaining
        self.wallClock = wallClock
    }
}
