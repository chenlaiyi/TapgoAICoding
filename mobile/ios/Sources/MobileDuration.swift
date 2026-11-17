import Foundation

/// Compact elapsed-time text for the running turn header.
enum MobileDuration {
    /// Formats whole seconds without zero-valued leading units.
    /// - Parameter seconds: elapsed seconds, clamped at zero.
    /// - Returns: `45 秒`, `1 分 24 秒`, or `2 小时 3 分 4 秒`.
    static func text(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value < 60 { return "\(value) 秒" }
        if value < 3_600 { return "\(value / 60) 分 \(value % 60) 秒" }
        return "\(value / 3_600) 小时 \((value % 3_600) / 60) 分 \(value % 60) 秒"
    }
}
