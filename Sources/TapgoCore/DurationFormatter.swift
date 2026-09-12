import Foundation

/// Formats a wall-clock duration into a short, human-readable string
/// used by the trajectory timeline and chat captions.
public enum DurationFormatter {
    /// v0.5.243: 对齐 ZCode 源码(chat.summaryPanel.duration 单位表)——
    /// 中文单位「分」不带「钟」,数字与单位间空格,无零填充。
    /// `5` → "5 秒", `65` → "1 分 5 秒", `3600` → "1 小时",
    /// `3725` → "1 小时 2 分 5 秒".
    public static func string(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 0 { return "0 秒" }
        if total < 60 { return "\(total) 秒" }
        let m = total / 60
        let s = total % 60
        if m < 60 { return "\(m) 分钟 \(s) 秒" }
        let h = m / 60
        let mm = m % 60
        if mm == 0 && s == 0 { return "\(h) 小时" }
        if mm == 0 { return "\(h) 小时 \(s) 秒" }
        if s == 0 { return "\(h) 小时 \(mm) 分钟" }
        return "\(h) 小时 \(mm) 分钟 \(s) 秒"
    }
}
