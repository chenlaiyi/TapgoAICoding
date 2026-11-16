import SwiftUI
import UIKit

/// Full-screen viewer for one durable transcript image: zoom, save to Photos, and share the file.
struct MobileImageViewer: View {
    let reference: MobileImageRef
    let thumbnail: UIImage?
    /// Reads the original bytes from the Host.
    let loader: () async -> Data?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var shareURL: URL?
    @State private var saved = false
    @State private var message: String?
    @State private var saver: MobilePhotoSaver?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) { toolbar }
        .overlay(alignment: .bottom) { messageLabel }
        .task { await load() }
        .accessibilityIdentifier("imageViewer")
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = min(4, max(1, committedScale * value)) }
                        .onEnded { _ in
                            committedScale = scale
                            if scale <= 1.01 {
                                withAnimation(.easeOut(duration: 0.15)) { resetZoom() }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: committedOffset.width + value.translation.width,
                                            height: committedOffset.height + value.translation.height)
                        }
                        .onEnded { _ in committedOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if scale > 1 {
                            resetZoom()
                        } else {
                            scale = 2.5
                            committedScale = 2.5
                        }
                    }
                }
                .accessibilityLabel(reference.name ?? "图片")
        } else if failed {
            VStack(spacing: 12) {
                Text("图片加载失败").font(.subheadline).foregroundStyle(.white)
                Button("重试") { Task { await load() } }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
            }
        } else {
            ProgressView().tint(.white)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("关闭")
            Spacer(minLength: 8)
            if let shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("分享图片")
            }
            Button { save() } label: {
                Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .disabled(image == nil)
            .accessibilityLabel(saved ? "已存储到相册" : "存储图片")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(Color.black.opacity(0.35))
    }

    @ViewBuilder
    private var messageLabel: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.65), in: Capsule())
                .padding(.bottom, 28)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2))
                    self.message = nil
                }
        }
    }

    private func resetZoom() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }

    private func load() async {
        failed = false
        if image == nil { image = thumbnail }
        guard let data = await loader() else {
            if image == nil { failed = true }
            return
        }
        if let decoded = UIImage(data: data) { image = decoded }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapgoShare", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        shareURL = try? MobileImageExport.write(data: data, name: reference.name,
                                                mediaType: reference.mediaType, in: directory)
    }

    private func save() {
        guard let image else { return }
        let saver = MobilePhotoSaver { success in
            self.saver = nil
            saved = success
            message = success ? "已存储到相册" : "无法存储，请在系统设置中允许访问相册"
        }
        self.saver = saver
        saver.save(image)
    }
}

/// Serializes the write into the photo library, which reports its outcome through an ObjC selector.
private final class MobilePhotoSaver: NSObject {
    private var completion: ((Bool) -> Void)?

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: NSError?,
                             contextInfo: UnsafeRawPointer?) {
        let completion = completion
        self.completion = nil
        completion?(error == nil)
    }
}
