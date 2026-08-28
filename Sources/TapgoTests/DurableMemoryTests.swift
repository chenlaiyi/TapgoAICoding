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
