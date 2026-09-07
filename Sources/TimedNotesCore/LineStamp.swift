import Foundation

/// The moment a note line was started, kept at full precision.
///
/// A stamp may know the time left on the countdown, the clock on the wall, or
/// both. Display picks one; the other stays available if the writer switches
/// modes later.
public struct LineStamp: Codable, Equatable {
    /// Seconds left on the timer when the line was started.
    /// Negative once the timer has run out and writing continues.
    /// `nil` when the line was written in clock mode with the timer idle.
    public var remaining: TimeInterval?
    /// Calendar time of the same moment, in the writer's local zone.
    public var wallClock: Date?

    public init(remaining: TimeInterval? = nil, wallClock: Date? = nil) {
        self.remaining = remaining
        self.wallClock = wallClock
    }
}
