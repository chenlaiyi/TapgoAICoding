import Foundation

/// One direct child listed by the parent's durable subagent catalog.
struct MobileSubagentEntry: Identifiable, Equatable {
    let id: String
    let name: String?
    let label: String?
    let mode: String
    let createdAt: TimeInterval

    /// Display name prefers the unique agent name, then the creation label.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let label, !label.isEmpty { return label }
        return id
    }
}

/// Folds `subagentCatalog` projection values and live `subagent/catalog` events.
enum MobileSubagentCatalog {
    /// Whether a tool name delegates to a child agent.
    /// - Parameter name: tool name from an activity.
    /// - Returns: true for `subagent` and its configured variants.
    static func isDelegation(_ name: String) -> Bool {
        name == "subagent" || name.hasPrefix("subagent_")
    }

    /// Parses the projection array.
    /// - Parameter value: `subagentCatalog` wire value.
    /// - Returns: entries in catalog order.
    static func parse(_ value: Any?) -> [MobileSubagentEntry] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap(entry)
    }

    /// Adds or replaces one live `subagent/catalog` event.
    /// - Parameters:
    ///   - entries: current catalog.
    ///   - data: catalog event payload.
    /// - Returns: updated catalog in event order.
    static func upsert(_ entries: [MobileSubagentEntry], data: [String: Any]) -> [MobileSubagentEntry] {
        guard let next = entry(data) else { return entries }
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == next.id }) {
            updated[index] = next
        } else {
            updated.append(next)
        }
        return updated
    }

    /// Whether the catalog row's delegation is still running.
    /// - Parameters:
    ///   - entry: catalog row.
    ///   - activities: the turn's tool activities.
    /// - Returns: true when a matching delegation has not finished.
    static func isRunning(_ entry: MobileSubagentEntry, activities: [MobileChatActivity]) -> Bool {
        activities.contains { activity in
            guard isDelegation(activity.name), !activity.finished else { return false }
            return matches(entry, activity: activity)
        }
    }

    /// Whether the catalog row's delegation failed.
    /// - Parameters:
    ///   - entry: catalog row.
    ///   - activities: the turn's tool activities.
    /// - Returns: true when a matching delegation failed.
    static func hasFailed(_ entry: MobileSubagentEntry, activities: [MobileChatActivity]) -> Bool {
        activities.contains { activity in
            guard isDelegation(activity.name), activity.failed else { return false }
            return matches(entry, activity: activity)
        }
    }

    private static func matches(_ entry: MobileSubagentEntry, activity: MobileChatActivity) -> Bool {
        guard let data = activity.parameters.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let candidates = [object["description"], object["label"], object["name"]].compactMap { $0 as? String }
        if let name = entry.name, candidates.contains(name) { return true }
        if let label = entry.label, candidates.contains(label) { return true }
        return candidates.isEmpty
    }

    private static func entry(_ wire: [String: Any]) -> MobileSubagentEntry? {
        guard let id = (wire["childId"] as? String) ?? (wire["id"] as? String), !id.isEmpty else { return nil }
        let createdAt = (wire["childCreatedAt"] as? Double) ?? (wire["createdAt"] as? Double) ?? 0
        return MobileSubagentEntry(
            id: id,
            name: wire["name"] as? String,
            label: wire["label"] as? String,
            mode: wire["mode"] as? String ?? "one-shot",
            createdAt: createdAt)
    }
}
