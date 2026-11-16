import SwiftUI

/// Workspace directory browser: folders push deeper, files open the existing preview sheet.
struct MobileFileBrowserView: View {
    let loadDirectory: (String) async throws -> MobileDirectoryListing
    let loadFile: (String) async throws -> MobileWorkspaceFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MobileDirectoryView(path: "", loadDirectory: loadDirectory, loadFile: loadFile)
                .navigationDestination(for: MobileBrowserRoute.self) { route in
                    MobileDirectoryView(path: route.path, loadDirectory: loadDirectory, loadFile: loadFile)
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
    @State private var listing: MobileDirectoryListing?
    @State private var error: String?
    @State private var loading = true
    @State private var revision = 0
    @State private var preview: MobileBrowserPreview?

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
                }
                ForEach(MobileFileBrowser.sorted(listing.entries)) { entry in
                    if entry.isDirectory {
                        NavigationLink(value: MobileBrowserRoute(path: MobileFileBrowser.child(entry.name, of: path))) {
                            row(entry, symbol: "folder")
                        }
                    } else if entry.isFile {
                        Button {
                            preview = MobileBrowserPreview(path: MobileFileBrowser.child(entry.name, of: path))
                        } label: {
                            row(entry, symbol: "doc.text")
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(entry, symbol: "questionmark.square.dashed")
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
        .task(id: revision) { await load() }
        .sheet(item: $preview) { request in
            MobileFilePreviewSheet(path: request.path) { try await loadFile(request.path) }
        }
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
