import SwiftUI
import UIKit

/// Compact attachment chips shown until image thumbnails load in the transcript.
struct MobileMessageAttachmentSummary: View {
    let attachments: [MobileMessageAttachment]

    var body: some View {
        HStack(spacing: 6) {
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
            Label(image.name ?? "图片", systemImage: "photo")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        case .file(let file):
            Label(file.name, systemImage: "paperclip")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
    }
}
