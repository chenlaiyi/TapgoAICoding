import SwiftUI

/// A summary chip opens retained, turn-scoped file comparisons without reading current workspace state.
struct MobileChangesView: View {
    let sequence: Int
    let loadSummary: (Int) async throws -> MobileChangesSummary
    let loadDiff: (Int, Int) async throws -> MobileFileDiff
    @State private var summary: MobileChangesSummary?
    @State private var error: String?
    @State private var expired = false
    @State private var loading = false
    @State private var showing = false
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary, summary.total > 0 {
                Button { showing = true } label: {
                    HStack(spacing: 8) {
                        Text("\(summary.total) 个文件")
                        if summary.added > 0 { Text("+\(summary.added)").foregroundStyle(.green) }
                        if summary.deleted > 0 { Text("−\(summary.deleted)").foregroundStyle(.red) }
                        Image(systemName: "chevron.right").font(.system(size: 9))
                    }
                    .font(.caption).padding(.horizontal, 12).frame(minHeight: 44)
                    .mobileGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityIdentifier("replyFileChanges")
            } else if let error {
                HStack(spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    if !expired { Button("重试") { revision += 1 }.font(.caption).frame(minHeight: 44) }
                }
            } else if loading {
                ProgressView().accessibilityLabel("正在读取文件变更")
            }
        }
        .task(id: "\(sequence)-\(revision)") {
            loading = true
            error = nil
            expired = false
            summary = nil
            defer { if !Task.isCancelled { loading = false } }
            do {
                let value = try await loadSummary(sequence)
                try Task.checkCancellation()
                summary = value
            }
            catch {
                if !Task.isCancelled {
                    expired = (error as? MobileReplyFailure) == .expired
                    self.error = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showing) {
            if let summary {
                NavigationStack {
                    List {
                        Section {
                            ForEach(Array(summary.files.enumerated()), id: \.offset) { index, file in
                                NavigationLink {
                                    MobileFileDiffView(file: file) { try await loadDiff(sequence, index) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(file.display).font(.subheadline).lineLimit(3)
                                        HStack(spacing: 10) {
                                            if file.binary == true { Text("二进制文件") }
                                            else if file.oversized == true { Text("文件过大，无法预览") }
                                            else {
                                                Text("+\(file.added)").foregroundStyle(.green)
                                                Text("−\(file.deleted)").foregroundStyle(.red)
                                            }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .accessibilityIdentifier("changedFile-\(index)")
                            }
                        } header: {
                            Text("\(summary.total) 个文件 · +\(summary.added) −\(summary.deleted)")
                        } footer: {
                            if summary.total > summary.files.count {
                                Text("Host 仅保留前 \(summary.files.count) 个文件的预览，总计包含其余文件")
                            }
                        }
                    }
                    .navigationTitle("文件变更").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showing = false }.accessibilityLabel("关闭文件变更")
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}

private struct MobileFileDiffView: View {
    let file: MobileChangesSummary.File
    let load: () async throws -> MobileFileDiff
    @State private var diff: MobileFileDiff?
    @State private var error: String?
    @State private var expired = false
    @State private var revision = 0

    var body: some View {
        Group {
            if let diff {
                if diff.kind == .binary {
                    Text("二进制文件无法显示文本差异").foregroundStyle(.secondary)
                } else if diff.kind == .oversized {
                    Text("文件过大，Host 未保留文本预览").foregroundStyle(.secondary)
                } else if let hunks = diff.hunks {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if diff.coarse == true {
                                Text("本次比较按整文件替换展示").foregroundStyle(.orange).padding(12)
                            }
                            if diff.before == false { Text("新增文件").foregroundStyle(.secondary).padding(12) }
                            else if diff.after == false { Text("已删除文件").foregroundStyle(.secondary).padding(12) }
                            if hunks.isEmpty { Text("没有文本行差异").padding() }
                            ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                                Text("@@ −\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@")
                                    .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line.isEmpty ? " " : line)
                                        .foregroundStyle(line.hasPrefix("+") ? Color.green : line.hasPrefix("-") ? Color.red : Color.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 2)
                                        .background(line.hasPrefix("+") ? Color.green.opacity(0.1) : line.hasPrefix("-") ? Color.red.opacity(0.1) : Color.clear)
                                }
                            }
                        }
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    .accessibilityIdentifier("replyFileDiff")
                }
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    if !expired { Button("重试") { revision += 1 }.frame(minHeight: 44) }
                }.padding()
            } else { ProgressView().accessibilityLabel("正在读取文件差异") }
        }
        .navigationTitle(file.display).navigationBarTitleDisplayMode(.inline)
        .task(id: revision) {
            error = nil
            expired = false
            do { diff = try await load() }
            catch {
                if !Task.isCancelled {
                    expired = (error as? MobileReplyFailure) == .expired
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
