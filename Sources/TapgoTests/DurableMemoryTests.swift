import Foundation
import TapgoCore

func runDurableMemorySanitization(_ t: TestRunner) {
    let raw = """
    # 跨会话记忆

    - <think>The user asked about memory.</think>
    - NONE
    - 用户环境变量中有 API key `sk-example`
    - 上次对话卡在太华镇配图，/tmp/imagegen/ 旧图可能已丢失
    - 项目源码当前标记版本为 v0.5.1
    - 用户尝试测试/体验小步增量输出功能
    - Tapgo AICoding 是 macOS 原生 SwiftUI 客户端，通过 Codex Harness app-server 工作
    - 用户偏好输出风格：小步增量，每完成一个有意义步骤就立即报告进度
    - 用户偏好小步增量输出，不要把内容攒到最后
    - 失败或异常需立即反馈，不得藏在末尾
    """

    let bullets = DurableMemory.sanitizedBullets(from: raw)
    t.expectEqual(bullets.count, 3, "keeps only three durable semantic topics")
    t.expect(bullets.contains { $0.contains("Tapgo AICoding") }, "keeps stable project identity")
    t.expect(bullets.contains { $0.contains("小步增量") }, "keeps latest progress preference")
    t.expect(bullets.contains { $0.contains("失败或异常") }, "keeps failure-reporting preference")
    t.expect(!bullets.contains { $0.contains("<think>") }, "drops reasoning traces")
    t.expect(!bullets.contains { $0.uppercased().contains("NONE") }, "drops NONE sentinel")
    t.expect(!bullets.contains { $0.contains("sk-example") }, "drops credential material")
    t.expect(!bullets.contains { $0.contains("/tmp/") }, "drops temporary paths")
    t.expect(!bullets.contains { $0.contains("v0.5.1") }, "drops volatile version snapshot")
    t.expect(!bullets.contains { $0.contains("尝试测试") }, "drops transient feature test")
}

func runDurableMemoryMarkdown(_ t: TestRunner) {
    let raw = """
    random prose must not survive
    - 用户偏好简体中文回复
    - 用户偏好简体中文回复
    - 项目发布使用 evolve.sh 串联测试、git tag 与 push
    """

    let markdown = DurableMemory.sanitizedMarkdown(from: raw)
    t.expectNotNil(markdown, "safe bullets produce canonical markdown")
    t.expect(markdown?.hasPrefix("# 跨会话记忆\n\n") == true, "canonical heading is restored")
    t.expectEqual(markdown?.components(separatedBy: "- 用户偏好简体中文回复").count, 2,
                  "exact duplicate appears once")
    t.expect(markdown?.contains("random prose") == false, "free-form prose is removed")
    t.expectEqual(DurableMemory.sanitizedMarkdown(from: markdown ?? ""), markdown,
                  "canonical markdown sanitization is idempotent")
    t.expectEqual(DurableMemory.sanitizedMarkdown(from: "NONE"), nil,
                  "no safe bullets returns nil")
    t.expectEqual(DurableMemory.sanitizedBullets(from: raw, limit: 1).count, 1,
                  "limit is enforced")
    t.expectEqual(DurableMemory.sanitizedBullets(from: raw, limit: 0).count, 0,
                  "zero limit returns empty")
}

func runDurableMemoryTimestampedBullets(_ t: TestRunner) {
    let now = ISO8601DateFormatter().date(from: "2026-08-28T20:00:00Z")!
    let bullet = DurableMemory.Bullet(
        timestamp: now,
        text: "用户偏好小步增量输出"
    )
    let rendered = bullet.rendered(now: now)
    t.expectEqual(rendered, "- [2026-08-28T20:00:00Z] 用户偏好小步增量输出",
                  "rendered form carries ISO-8601 prefix")

    let parsed = DurableMemory.parseBullets(from: rendered)
    t.expectEqual(parsed.count, 1, "round-trips one bullet")
    t.expectEqual(parsed.first?.text, "- 用户偏好小步增量输出",
                  "parsed text strips timestamp but keeps the leading dash")
    t.expectEqual(parsed.first?.timestamp, now, "parsed timestamp equals input")

    // Legacy un-timestamped bullets stay parseable as distantPast.
    let legacy = DurableMemory.parseBullets(from: "- 用户偏好简体中文回复")
    t.expectEqual(legacy.count, 1, "legacy line still parses")
    t.expectEqual(legacy.first?.timestamp, .distantPast, "legacy gets distantPast")

    // Sanitized bullets are timestamped, oldest-first.
    let out = DurableMemory.sanitizedBullets(
        from: "- 用户偏好 A\n- 用户偏好 B\n",
        now: now
    )
    t.expectEqual(out.count, 2, "two safe bullets kept")
    t.expect(out.allSatisfy { $0.hasPrefix("- [") }, "every bullet has timestamp prefix")
}

func runDurableMemoryAppendBullet(_ t: TestRunner) {
    let now = ISO8601DateFormatter().date(from: "2026-08-28T20:00:00Z")!
    let empty = ""
    let first = DurableMemory.appendBullet(to: empty, text: "- 用户偏好小步增量输出", now: now)
    t.expectNotNil(first, "first append succeeds")
    t.expect(first?.contains("[2026-08-28T20:00:00Z]") == true, "first append carries timestamp")

    let second = DurableMemory.appendBullet(
        to: first ?? "",
        text: "- 项目使用 SwiftUI",
        now: now.addingTimeInterval(60)
    )
    t.expectNotNil(second, "second append succeeds")
    t.expectEqual(second?.components(separatedBy: "[2026-08-28T20:01:00Z]").count, 2,
                  "second append present and timestamped")

    // Unsafe text is rejected.
    let rejected = DurableMemory.appendBullet(
        to: first ?? "",
        text: "- 用户环境变量有 sk-12345 API key",
        now: now
    )
    t.expectNil(rejected, "credential bullet is rejected")

    // Idempotency: appending a duplicate (same semantic fingerprint) is a no-op.
    let dup = DurableMemory.appendBullet(
        to: first ?? "",
        text: "- 用户偏好小步增量输出",
        now: now
    )
    t.expectEqual(dup, first, "duplicate append is a no-op after sanitize")
}

func runDurableMemoryByteLimit(_ t: TestRunner) {
    // Build a huge raw blob with many safe bullets.
    // Build a huge raw blob with many safe bullets and a header.
    var raw = "# 跨会话记忆\n\n"
    for i in 0..<2000 {
        raw += "- 用户偏好第 \(i) 条长期稳定事实\n"
    }
    let capped = DurableMemory.enforceByteLimit(raw)
    t.expect(capped.utf8.count <= DurableMemory.perFileByteLimit,
             "byte cap enforced (\(capped.utf8.count) <= \(DurableMemory.perFileByteLimit))")
    t.expect(capped.contains("# 跨会话记忆"), "header preserved under cap")
}

func runDurableMemorySummaryLayer(_ t: TestRunner) {
    let raw = """
    # 跨会话记忆

    - 用户偏好简体中文回复
    - 用户偏好小步增量输出
    - 项目使用 Codex Harness app-server
    """
    let summary = DurableMemory.summaryForInjection(from: raw)
    t.expectNotNil(summary, "summary is non-nil for safe input")
    t.expect(summary?.contains("# 跨会话记忆") == true, "summary keeps heading")
    t.expect(summary?.contains("用户偏好简体中文回复") == true, "summary keeps first bullet")
    t.expect(summary?.contains("Codex Harness") == true, "summary keeps project bullet")

    // Empty / unsafe input → nil summary.
    t.expectNil(DurableMemory.summaryForInjection(from: "NONE"),
                "summary returns nil when nothing is safe")
}

func runMemoryConsolidatorDeterministic(_ t: TestRunner) async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-mem-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Pre-write a tiny memory file with one durable bullet.
    let now = Date()
    let date = ISO8601DateFormatter()
    let body = """
    # 跨会话记忆

    - [\(date.string(from: now))] - 用户偏好小步增量输出
    - [\(date.string(from: now))] - 用户偏好小步增量输出
    """
    try? body.write(to: tmp, atomically: true, encoding: .utf8)

    let outcome = await MemoryConsolidator.consolidate(url: tmp)
    switch outcome {
    case .rewrote, .alreadyConsolidated:
        // Either outcome is acceptable — both indicate the file is in canonical form.
        break
    case .skipped(let reason):
        t.expect(false, "unexpected skip: \(reason)")
    }
    let readBack = try? String(contentsOf: tmp, encoding: .utf8)
    t.expectNotNil(readBack, "consolidated file readable")
    let bulletCount = (readBack?.components(separatedBy: "用户偏好小步增量输出").count ?? 0) - 1
    t.expectEqual(bulletCount, 1, "duplicate bullet collapsed by consolidation")

    // Idempotency: running again returns .alreadyConsolidated.
    let second = await MemoryConsolidator.consolidate(url: tmp)
    t.expectEqual(second, MemoryConsolidator.Outcome.alreadyConsolidated,
                  "second consolidation reports alreadyConsolidated")
}

func runMemoryCloudSyncAvailability(_ t: TestRunner) {
    // We don't know whether the dev machine has iCloud configured, so just
    // assert the type contract holds.
    let _ = MemoryCloudSync.iCloudMirrorURL // must not crash
    let _ = MemoryCloudSync.isICloudAvailable
    t.expect(true, "cloud sync availability probes are non-throwing")
}

func runMemoryCloudSyncRelativePath(_ t: TestRunner) {
    let memDir = URL(fileURLWithPath: "/tmp/fake-memory")
    let url = memDir.appendingPathComponent("user.md")
    let rel = MemoryCloudSync.relativePath(for: url, memoryDirectory: memDir)
    t.expectEqual(rel, "user.md", "relative path strips memory directory")
    let back = MemoryCloudSync.localURL(forRemoteRelativePath: rel, memoryDirectory: memDir)
    t.expectEqual(back.standardizedFileURL.path, url.standardizedFileURL.path,
                  "localURL round-trips")
}
