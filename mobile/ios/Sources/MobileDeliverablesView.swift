import SwiftUI

/// Lists files a turn delivered or linked, each opening the shared Quick Look preview.
struct MobileDeliverablesView: View {
    let files: [MobileDeliverable]
    let loadFile: (String) async throws -> MobileWorkspaceFile
    @State private var preview: MobileDeliverableTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("交付文件 \(files.count)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(files) { file in
                Button {
                    preview = MobileDeliverableTarget(path: file.path)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: file.isImage ? "photo" : "doc.text")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).font(.caption).lineLimit(1)
                            if !file.subtitle.isEmpty {
                                Text(file.subtitle)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("预览 \(file.name)")
            }
        }
        .padding(10)
        .mobileGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(item: $preview) { target in
            MobileFilePreviewSheet(path: target.path) { try await loadFile(target.path) }
        }
    }
}

/// One pending file preview.
private struct MobileDeliverableTarget: Identifiable {
    let id = UUID()
    let path: String
}
