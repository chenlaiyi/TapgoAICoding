import Foundation

/// Describes how long a running turn has gone without a new frame.
enum MobileSilenceLabel {
    /// Formats the wait with the largest useful unit so a long silence stays readable.
    /// - Parameter seconds: whole seconds since the last frame.
    /// - Returns: the localized wait phrase, for example `已 28 分 43 秒没有收到新输出`.
    static func text(seconds: Int) -> String {
        let value = max(0, seconds)
        if value < 60 { return "已 \(value) 秒没有收到新输出" }
        if value < 3600 { return "已 \(value / 60) 分 \(value % 60) 秒没有收到新输出" }
        return "已 \(value / 3600) 小时 \(value % 3600 / 60) 分没有收到新输出"
    }
}
