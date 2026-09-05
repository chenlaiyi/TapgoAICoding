import Foundation

/// Deterministic local path for common scheduling requests. Entire-message
/// matching prevents quoted examples, questions and ordinary chat from creating tasks.
public enum ScheduledTaskCommands {
    public struct Request: Equatable {
        public let schedule: ScheduleSpec
        public let applicationName: String
    }
    public static func parse(_ text: String) -> Request? {
        let pattern = #"^(?:请(?:你)?|帮我)?\s*(周一到周五|周一至周五|工作日|每天)(?:每天)?\s*(早上|上午|下午|晚上|中午)?\s*([0-9]{1,2})(?:点|时|:|：)\s*([0-9]{1,2})?分?\s*(?:打开|启动)\s*([\p{L}\p{N} ._-]{1,80}?)(?:\s+[Aa][Pp][Pp])?[。！!]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String {
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
        guard var hour = Int(group(3)) else { return nil }
        let minute = Int(group(4)) ?? 0
        if ["下午", "晚上"].contains(group(2)), hour < 12 { hour += 12 }
        if group(2) == "上午", hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let name = group(5).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Request(schedule: group(1) == "每天" ? .daily(hour: hour, minute: minute) : .weekdays(hour: hour, minute: minute), applicationName: name)
    }
}
