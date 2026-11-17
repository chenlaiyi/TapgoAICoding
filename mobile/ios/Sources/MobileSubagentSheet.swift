import SwiftUI

/// Lists every direct child agent recorded in the parent catalog.
struct MobileSubagentSheet: View {
    let entries: [MobileSubagentEntry]
    let activities: [MobileChatActivity]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("还没有子智能体").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.displayName).font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            Text(status(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(entry.mode) · \(entry.id)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        if let label = entry.label, label != entry.displayName {
                            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("子智能体")
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func status(_ entry: MobileSubagentEntry) -> String {
        if MobileSubagentCatalog.isRunning(entry, activities: activities) { return "正在刷新状态" }
        if MobileSubagentCatalog.hasFailed(entry, activities: activities) { return "运行失败" }
        return "已完成"
    }
}
