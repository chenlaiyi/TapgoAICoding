import Foundation

/// Formats a wall-clock duration into a short, human-readable string
/// used by the trajectory timeline and chat captions.
public enum DurationFormatter {
    /// `5` → "5s", `65` → "1m 05s", `3600` → "1h 00m", `3725` → "1h 02m".
    public static func string(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 0 { return "0s" }
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let s = total % 60
        if m < 60 { return String(format: "%dm %02ds", m, s) }
        let h = m / 60
        let mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
