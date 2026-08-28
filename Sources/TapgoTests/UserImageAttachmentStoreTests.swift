import Foundation
import TapgoCore

func runUserImageAttachmentStore(_ t: TestRunner) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-image-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let attachmentDirectory = root.appendingPathComponent("attachments", isDirectory: true)
    try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let source = sourceDirectory.appendingPathComponent("clipboard.png")
    let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
    try? bytes.write(to: source)

    let paths = UserImageAttachmentStore.persist(
        [source],
        baseDirectory: attachmentDirectory,
        threadId: "thread/unsafe",
        turnId: "turn:1"
    )

    t.expectEqual(paths.count, 1, "one source produces one persisted path")
    guard let path = paths.first else { return }
    t.expect(path != source.path, "persisted path differs from clipboard source")
    t.expect(FileManager.default.fileExists(atPath: path), "persisted attachment exists")
    t.expectEqual(try? Data(contentsOf: URL(fileURLWithPath: path)), bytes, "persisted bytes match source")
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    t.expectEqual((attrs?[.posixPermissions] as? NSNumber)?.intValue, 0o600, "persisted attachment uses 0600 permissions")
    t.expect(path.contains("thread_unsafe/turn_1"), "thread and turn path components are sanitized")

    let missing = sourceDirectory.appendingPathComponent("missing.png")
    let fallback = UserImageAttachmentStore.persist(
        [missing], baseDirectory: attachmentDirectory, threadId: "t", turnId: "x"
    )
    t.expectEqual(fallback, [missing.path], "copy failure keeps source path for current-launch display")

    t.expect(UserImageAttachmentStore.removeAll(baseDirectory: attachmentDirectory, threadId: "thread/unsafe"),
             "removing a thread attachment directory succeeds")
    t.expectEqual(FileManager.default.fileExists(atPath: path), false,
                  "removing a thread deletes its persisted image")
}
