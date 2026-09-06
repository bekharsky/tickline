import Foundation

/// Units shown in the line prefix. Each unit toggles independently, which is
/// what the H / m / s toolbar buttons drive.
public struct StampFormat: Codable, Equatable {
    public var hours: Bool
    public var minutes: Bool
    public var seconds: Bool
    /// Tenths of a second. Only meaningful together with `seconds`.
    public var subseconds: Bool

    public init(hours: Bool = true, minutes: Bool = true, seconds: Bool = true, subseconds: Bool = false) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.subseconds = subseconds
    }

    /// Everything the stamp knows about itself.
    public static let exact = StampFormat(hours: true, minutes: true, seconds: true, subseconds: true)
    public static let clock = StampFormat(hours: true, minutes: true, seconds: true)
    public static let minutesOnly = StampFormat(hours: false, minutes: true, seconds: false)

    public var isEmpty: Bool { !hours && !minutes && !seconds }

    public var showsFraction: Bool { subseconds && seconds }
}

public enum StampFormatter {
    /// Renders `remaining` using only the enabled units.
    ///
    /// A disabled larger unit rolls into the next enabled one: with hours off,
    /// an hour left reads as `60` minutes rather than `00`.
    public static func string(for remaining: TimeInterval, format: StampFormat) -> String {
        guard !format.isEmpty else { return "" }

        let sign = remaining < 0 ? "-" : ""
        var rest = abs(remaining)
        // Truncate to the smallest displayed unit so the countdown never shows
        // a value the timer has not reached yet.
        rest = format.showsFraction ? (rest * 10).rounded(.down) / 10 : rest.rounded(.down)

        var parts: [String] = []
        if format.hours {
            let value = (rest / 3600).rounded(.down)
            rest -= value * 3600
            parts.append(twoDigits(value))
        }
        if format.minutes {
            let value = (rest / 60).rounded(.down)
            rest -= value * 60
            parts.append(twoDigits(value))
        }
        if format.seconds {
            let value = rest.rounded(.down)
            rest -= value
            parts.append(twoDigits(value))
        }

        var text = sign + parts.joined(separator: ":")
        if format.showsFraction {
            text += String(format: ".%d", min(9, Int((rest * 10).rounded())))
        }
        return text
    }

    /// Same shape as a real stamp, for lines written while the timer was idle.
    public static func placeholder(for format: StampFormat) -> String {
        guard !format.isEmpty else { return "" }

        let unitCount = [format.hours, format.minutes, format.seconds].filter { $0 }.count
        var text = Array(repeating: "--", count: unitCount).joined(separator: ":")
        if format.showsFraction {
            text += ".-"
        }
        return text
    }

    /// Longest stamp the gutter may have to draw, used to size it. One extra
    /// digit of slack covers overtime running past the original duration.
    public static func widestSample(duration: TimeInterval, format: StampFormat) -> String {
        guard !format.isEmpty else { return "" }

        let full = string(for: -abs(duration), format: format)
        let candidates = [full, placeholder(for: format)]
        let widest = candidates.max { $0.count < $1.count } ?? full
        return widest + "0"
    }

    private static func twoDigits(_ value: Double) -> String {
        String(format: "%02.0f", value)
    }
}
