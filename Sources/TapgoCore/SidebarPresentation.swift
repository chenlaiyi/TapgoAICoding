import Foundation

public enum SidebarPresentation {
    public static func collapsedIDs(_ value: String) -> Set<String> {
        guard let data = value.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }
    public static func encodeCollapsedIDs(_ ids: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
    /// Selection never changes project ordering. Pinning preserves the saved order within each tier.
    public static func projectIDs(_ ids: [String], pinned: Set<String>) -> [String] {
        ids.filter { pinned.contains($0) } + ids.filter { !pinned.contains($0) }
    }
    public static func statusText(_ status: Turn.Status?) -> String? {
        switch status {
        case .running: return "进行中"
        case .awaitingApproval: return "待批准"
        case .failed: return "未完成"
        case .interrupted: return "已中断"
        default: return nil
        }
    }
}
