import QuickLook
import SwiftUI

/// Native Quick Look preview for one workspace file, with share, save, and retry.
struct MobileFilePreviewSheet: View {
    let path: String
    let load: () async throws -> MobileWorkspaceFile
    @Environment(\.dismiss) private var dismiss
    @State private var file: MobileWorkspaceFile?
    @State private var previewURL: URL?
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            Group {
                if let previewURL {
                    QuickLookView(url: previewURL)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("重试") { revision += 1 }
                            .frame(minHeight: 44)
                    }
                    .padding(24)
                } else {
                    ProgressView("正在读取文件…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if let file, let previewURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: previewURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("分享或保存文件")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Text(MobileFileSize.format(file.byteCount))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: revision) { await loadFile() }
    }

    private var title: String {
        file?.name ?? (path as NSString).lastPathComponent
    }

    private func loadFile() async {
        file = nil
        previewURL = nil
        error = nil
        do {
            let loaded = try await load()
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dsh-preview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = loaded.name.isEmpty ? "file" : loaded.name
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: url.path, contents: loaded.data) else {
                throw MobileFilePreviewError.writeFailed
            }
            file = loaded
            previewURL = url
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Hosts Quick Look as a SwiftUI view.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
