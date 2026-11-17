import SwiftUI
import UIKit

/// Loads and renders transcript thumbnails without exposing the chat view model to this view.
struct MobileAttachmentPreviewSource {
    /// Returns a decoded thumbnail when one is already cached.
    var image: (MobileImageRef) -> UIImage? = { _ in nil }
    /// Whether the last fetch for one image failed.
    var failed: (MobileImageRef) -> Bool = { _ in false }
    /// Starts one fetch for an image that is not cached yet.
    var load: (MobileImageRef) async -> Void = { _ in }
    /// Clears a failed fetch so the tile can try again.
    var retry: (MobileImageRef) -> Void = { _ in }
    /// Last failure reason for the tile, when known.
    var error: (MobileImageRef) -> String? = { _ in nil }
    /// Opens one image in the full-screen viewer.
    var open: (MobileImageRef) -> Void = { _ in }
}

/// Compact attachment chips: an image thumbnail plus its name, or a file name plus its size.
struct MobileMessageAttachmentSummary: View {
    let attachments: [MobileMessageAttachment]
    var preview = MobileAttachmentPreviewSource()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                chip(attachment)
                    .accessibilityIdentifier("messageAttachment-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let images = attachments.compactMap(\.image).count
        let files = attachments.compactMap(\.file).count
        return "\(images) 张图片，\(files) 个文件"
    }

    @ViewBuilder
    private func chip(_ attachment: MobileMessageAttachment) -> some View {
        switch attachment {
        case .image(let image):
            HStack(spacing: 8) {
                thumbnail(image)
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.name ?? "图片")
                        .font(.caption).lineLimit(1)
                    Text(MobileAttachmentFormat.byteText(image.bytes))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let failure = preview.error(image) {
                        Text(failure).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(6)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        case .file(let file):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.caption).lineLimit(1)
                    Text(MobileAttachmentFormat.byteText(file.bytes))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "paperclip").font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func thumbnail(_ reference: MobileImageRef) -> some View {
        if let image = preview.image(reference) {
            Button {
                preview.open(reference)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(reference.name ?? "图片")")
        } else if preview.failed(reference) {
            Button {
                preview.retry(reference)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                    Text("重新加载").font(.caption2)
                }
                .frame(width: 56, height: 56)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新加载图片")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .tertiarySystemBackground))
                ProgressView().controlSize(.mini)
            }
            .frame(width: 56, height: 56)
            .task { await preview.load(reference) }
        }
    }
}
