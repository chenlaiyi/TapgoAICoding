import SwiftUI

/// Shows the prompts waiting behind the running turn and lets the user edit, remove, or steer them.
struct MobileQueueStrip: View {
    let items: [MobileQueuedItem]
    let running: Bool
    let busyItemID: String?
    let error: String?
    let onEdit: (MobileQueuedItem) -> Void
    let onRemove: (MobileQueuedItem) -> Void
    let onSteer: (MobileQueuedItem) -> Void

    @State private var expanded = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header
                if expanded {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(items) { item in row(item) }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items.count) 条排队消息").font(.caption).foregroundStyle(.secondary)
                    if !expanded, let first = items.first {
                        Text(first.preview).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("queueStripHeader")
        .accessibilityValue(expanded ? "已展开" : "已收起")
    }

    private func row(_ item: MobileQueuedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(item.text.isEmpty ? "附件" : item.text)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isSteering {
                    Text("插话中")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
                if !item.attachments.isEmpty {
                    Label("\(item.attachments.count)", systemImage: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            HStack(spacing: 4) {
                if running {
                    Button("插话") { onSteer(item) }
                        .disabled(busyItemID != nil || !item.isEditable)
                        .accessibilityIdentifier("queueSteer-\(item.id)")
                }
                Button("编辑") { onEdit(item) }
                    .disabled(busyItemID != nil || !item.isEditable)
                    .accessibilityIdentifier("queueEdit-\(item.id)")
                Spacer(minLength: 0)
                Button("删除", role: .destructive) { onRemove(item) }
                    .disabled(busyItemID != nil)
                    .accessibilityIdentifier("queueRemove-\(item.id)")
            }
            .font(.caption)
            .frame(minHeight: 32)
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
