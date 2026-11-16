import SwiftUI

/// Workspace directory browser: folders push deeper, files open the existing preview sheet.
struct MobileFileBrowserView: View {
    let loadDirectory: (String) async throws -> MobileDirectoryListing
    let loadFile: (String) async throws -> MobileWorkspaceFile
    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [MobileBrowserRoute] = []

    var body: some View {
        NavigationStack(path: $pathStack) {
            MobileDirectoryView(path: "", loadDirectory: loadDirectory, loadFile: loadFile,
                                goToRoot: { pathStack.removeAll() })
                .navigationDestination(for: MobileBrowserRoute.self) { route in
                    MobileDirectoryView(path: route.path, loadDirectory: loadDirectory, loadFile: loadFile,
                                        goToRoot: { pathStack.removeAll() })
                }
                .navigationTitle("文件")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }.accessibilityLabel("关闭文件浏览")
                    }
                }
        }
    }
}

private struct MobileBrowserRoute: Hashable {
    let path: String
}

private struct MobileBrowserPreview: Identifiable {
    let id = UUID()
    let path: String
}

private struct MobileDirectoryView: View {
    let path: String
    let loadDirectory: (String) async throws -> MobileDirectoryListing
    let loadFile: (String) async throws -> MobileWorkspaceFile
    let goToRoot: () -> Void
    @State private var listing: MobileDirectoryListing?
    @State private var error: String?
    @State private var loading = true
    @State private var revision = 0
    @State private var preview: MobileBrowserPreview?
    @State private var search = ""

    var body: some View {
        List {
            if loading && listing == nil {
                ProgressView("正在读取目录…")
            } else if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { revision += 1 }.frame(minHeight: 44)
                }
            } else if let listing {
                if listing.entries.isEmpty {
                    Text("空目录").foregroundStyle(.secondary)
                } else if filteredEntries.isEmpty {
                    Text("没有匹配的文件").foregroundStyle(.secondary)
                }
                ForEach(MobileFileBrowser.sorted(filteredEntries)) { entry in
                    if entry.isDirectory {
                        NavigationLink(value: MobileBrowserRoute(path: MobileFileBrowser.child(entry.name, of: path))) {
                            row(entry, symbol: "folder")
                        }
                        .accessibilityLabel(MobileFileBrowser.accessibilityLabel(for: entry))
                        .accessibilityHint("进入文件夹")
                    } else if entry.isFile {
                        Button {
                            preview = MobileBrowserPreview(path: MobileFileBrowser.child(entry.name, of: path))
                        } label: {
                            row(entry, symbol: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MobileFileBrowser.accessibilityLabel(for: entry))
                        .accessibilityHint("打开文件预览")
                    } else {
                        row(entry, symbol: "questionmark.square.dashed")
                            .accessibilityLabel(MobileFileBrowser.accessibilityLabel(for: entry))
                    }
                }
                if listing.truncated {
                    Text("目录项过多，Host 仅返回前 \(listing.entries.count) 项")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(MobileFileBrowser.display(path))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "筛选当前目录")
        .toolbar {
            if !path.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("根目录") { goToRoot() }.accessibilityLabel("回到工作区根目录")
                }
            }
        }
        .task(id: revision) { await load() }
        .sheet(item: $preview) { request in
            MobileFilePreviewSheet(path: request.path) { try await loadFile(request.path) }
        }
    }

    /// Entries matching the current search text.
    private var filteredEntries: [MobileDirectoryEntry] {
        MobileFileBrowser.filtered(listing?.entries ?? [], search: search)
    }

    private func row(_ entry: MobileDirectoryEntry, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(entry.name).lineLimit(2)
            Spacer()
            if let size = entry.size {
                Text(MobileFileSize.format(size)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }

    private func load() async {
        loading = true
        error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let value = try await loadDirectory(path)
            try Task.checkCancellation()
            listing = value
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
