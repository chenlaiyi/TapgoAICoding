import Foundation

/// Sanitizes model-generated long-term memory before it is persisted or
/// injected into a new harness thread.
///
/// Long-term memory is deliberately narrower than conversation history. It
/// keeps stable user preferences, project identity, and durable workflows;
/// reasoning traces, credentials, temporary paths, current version snapshots,
/// and unfinished-task state are rejected because they become stale quickly
/// and can steer a future conversation away from the user's actual request.
public enum DurableMemory {
    public static let heading = "# 跨会话记忆"

    /// Return safe bullets in canonical chronological order, with exact and
    /// semantic duplicates collapsed. Selection runs newest-first so a recent
    /// user correction wins, then the result is restored to a stable order;
    /// sanitizing canonical output again is therefore idempotent.
    public static func sanitizedBullets(
        from raw: String,
        limit: Int = 48
    ) -> [String] {
        guard limit > 0 else { return [] }
        var accepted: [String] = []
        var fingerprints = Set<String>()
        var topics = Set<String>()

        for line in raw.split(whereSeparator: \.isNewline).reversed() {
            let bullet = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeBullet(bullet) else { continue }

            let fingerprint = semanticFingerprint(bullet)
            guard !fingerprint.isEmpty, fingerprints.insert(fingerprint).inserted else { continue }

            if let topic = semanticTopic(bullet) {
                guard topics.insert(topic).inserted else { continue }
            } else if accepted.contains(where: { isNearDuplicate(bullet, $0) }) {
                continue
            }

            accepted.append(bullet)
            if accepted.count == limit { break }
        }
        return Array(accepted.reversed())
    }

    public static func sanitizedMarkdown(
        from raw: String,
        limit: Int = 48
    ) -> String? {
        let bullets = sanitizedBullets(from: raw, limit: limit)
        guard !bullets.isEmpty else { return nil }
        return ([heading, ""] + bullets).joined(separator: "\n") + "\n"
    }

    /// The model output is untrusted. Only one-line Markdown bullets that look
    /// like durable declarative facts are accepted.
    public static func isSafeBullet(_ bullet: String) -> Bool {
        guard bullet.hasPrefix("- "), bullet.count >= 4, bullet.count <= 600 else { return false }

        let normalized = bullet.lowercased()
        if normalized == "- none" || normalized == "- none." { return false }

        let unsafeMarkers = [
            "<think", "</think", "let me think", "i can infer", "i'll output",
            "nothing worth", "system prompt", "ignore previous", "execute this",
            "系统提示", "忽略以上", "必须遵循", "执行以下",
            "密码", "口令", "令牌", "密钥", "凭据", "api key", "bearer ", "sk-",
        ]
        if unsafeMarkers.contains(where: { normalized.contains($0) }) { return false }

        let temporaryMarkers = [
            "/tmp/", "上次对话", "尚未决定", "可能已丢失", "重启后", "抢救出来",
            "当前版本", "当前最新版本", "当前对外版本", "当前标记版本", "当前 v", "当前为 v",
            "下一个候选版本", "处于半完成", "尚未 push", "领先 origin",
            "origin/main", "head `", "commit `", "遗留 bug", "已生成一张图",
            "运行中的 `.app`", "本次引入", "临时操作", "尝试测试", "尝试体验",
        ]
        return !temporaryMarkers.contains(where: { normalized.contains($0) })
    }

    private static func semanticFingerprint(_ bullet: String) -> String {
        let text = String(bullet.dropFirst(2)).lowercased()
        let scalars = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isNearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let a = semanticFingerprint(lhs)
        let b = semanticFingerprint(rhs)
        guard min(a.count, b.count) >= 16 else { return false }
        return a.contains(b) || b.contains(a)
    }

    private static func semanticTopic(_ bullet: String) -> String? {
        let value = bullet.lowercased()
        if value.contains("小步") || value.contains("增量式输出") || value.contains("攒到最后") {
            return "incremental-progress-style"
        }
        if (value.contains("失败") || value.contains("异常")) && value.contains("立即") {
            return "immediate-failure-reporting"
        }
        if value.contains("tapgo aicoding") &&
            (value.contains("swiftui") || value.contains("codex harness") || value.contains("app-server")) {
            return "tapgo-project-identity"
        }
        if value.contains("evolve.sh") && (value.contains("发布") || value.contains("git tag")) {
            return "tapgo-release-workflow"
        }
        return nil
    }
}
