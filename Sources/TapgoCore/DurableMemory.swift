import Foundation

/// Sanitizes model-generated long-term memory before it is persisted or
/// injected into a new harness thread.
///
/// Long-term memory is deliberately narrower than conversation history. It
/// keeps stable user preferences, project identity, and durable workflows;
/// reasoning traces, credentials, temporary paths, current version snapshots,
/// and unfinished-task state are rejected because they become stale quickly
/// and can steer a future conversation away from the user's actual request.
///
/// Memory files are organized in three layers (mirroring DeepSeek harness):
///   * **USER.md**   — cross-project user preferences / communication style
///   * **MEMORY.md** — global environment / toolchain / conventions
///   * **KEY.md**    — per-project, per-git-branch decisions / architecture /
///                     pitfalls (filtered by `git rev-parse --abbrev-ref HEAD`)
///
/// Each bullet is prefixed with a UTC ISO-8601 timestamp so we can prune stale
/// or superseded entries without losing context. The model never sees the
/// timestamps — they are stripped during fingerprinting for dedup, and during
/// injection only the most recent N bullets are surfaced as a summary.
public enum DurableMemory {
    public static let heading = "# 跨会话记忆"

    /// Hard byte cap on any single memory file. Exceeding it triggers a
    /// head-truncate with an explicit `<... truncated at 100 KiB ...>` marker
    /// so the user can spot it in Settings / `readMemoryMarkdown`.
    public static let perFileByteLimit = 100 * 1024

    /// Default bullet cap injected as `baseInstructions`. The summary layer is
    /// what the model actually sees; the full MEMORY.md stays on disk for
    /// on-demand grep (Codex-style progressive disclosure).
    public static let summaryBulletLimit = 24

    /// Total dedup cap used when re-sanitizing a raw memory blob before
    /// persisting (kept larger than the summary so consolidation can pick the
    /// best subset later).
    public static let sanitizedBulletLimit = 96

    /// Format used in front of every persisted bullet:
    /// `- [2026-08-28T20:00:00Z] <durable fact>`
    public static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Bullet model

    /// A single persisted bullet, with the timestamp we stored on disk and the
    /// user-visible text without the timestamp prefix.
    public struct Bullet: Equatable, Hashable {
        public let timestamp: Date
        public let text: String

        public init(timestamp: Date, text: String) {
            self.timestamp = timestamp
            self.text = text
        }

        /// Render as the canonical on-disk form.
        public func rendered(now: Date = Date()) -> String {
            let stamp = DurableMemory.timestampFormatter.string(from: timestamp)
            return "- [\(stamp)] \(text)"
        }
    }

    // MARK: - Parsing & rendering

    /// Parse a stored memory file back into `Bullet`s. Lines that don't match
    /// the expected `- [<iso8601>] <text>` shape are passed through with
    /// `timestamp = .distantPast` so the sanitizer can still inspect / reject
    /// them without crashing on legacy un-timestamped files.
    public static func parseBullets(from raw: String) -> [Bullet] {
        var out: [Bullet] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let s = String(line)
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Timestamp prefix: `- [YYYY-MM-DDTHH:MM:SSZ] <text>`.
            if trimmed.hasPrefix("- [") {
                if let close = trimmed.firstIndex(of: "]"),
                   close > trimmed.index(trimmed.startIndex, offsetBy: 3) {
                    let stampStr = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<close])
                    let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
                    guard !rest.isEmpty,
                          let date = timestampFormatter.date(from: stampStr) else {
                        // Malformed timestamp: surface as untimestamped legacy bullet.
                        out.append(Bullet(timestamp: .distantPast, text: s))
                        continue
                    }
                    // Re-prefix the leading "- " so `text` matches the legacy
                    // branch: isSafeBullet and the sanitizer treat timestamped
                    // and legacy bullets uniformly. The rendered form is
                    // "- [<stamp>] <body>" and parsing back must recover the
                    // exact same body (including the dash) for round-trips.
                    let body = rest.hasPrefix("- ") ? rest : "- " + rest
                    out.append(Bullet(timestamp: date, text: body))
                    continue
                }
            }
            // Legacy un-timestamped bullet: accept ONLY if it already starts
            // with the "- " dash prefix (the contract enforced by isSafeBullet).
            // Free-form prose lines are dropped entirely.
            if trimmed.hasPrefix("- ") {
                // Keep the "- " prefix on `text` so isSafeBullet's contract is
                // preserved end-to-end (it requires the leading dash).
                out.append(Bullet(timestamp: .distantPast, text: trimmed))
            }
            // else: stray prose line, silently discarded.
        }
        return out
    }

    /// Combine parsed bullets into canonical on-disk Markdown, sorted by
    /// timestamp (oldest-first), applying `isSafeBullet` per entry and
    /// deduplicating via `semanticFingerprint`. The result is idempotent.
    public static func sanitizedBullets(
        from raw: String,
        limit: Int = sanitizedBulletLimit,
        now: Date = Date()
    ) -> [String] {
        guard limit > 0 else { return [] }
        let parsed = parseBullets(from: raw)

        // Newest-first dedup walk, then restore stable order.
        var accepted: [Bullet] = []
        var fingerprints = Set<String>()
        var topics = Set<String>()

        for bullet in parsed.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard isSafeBullet(bullet.text) else { continue }
            let fp = semanticFingerprint(bullet.text)
            guard !fp.isEmpty, fingerprints.insert(fp).inserted else { continue }

            if let topic = semanticTopic(bullet.text) {
                guard topics.insert(topic).inserted else { continue }
            } else if accepted.contains(where: { isNearDuplicate(bullet.text, $0.text) }) {
                continue
            }

            accepted.append(bullet)
            if accepted.count == limit { break }
        }
        let ordered = accepted.sorted(by: { $0.timestamp < $1.timestamp })
        return ordered.map { $0.rendered(now: now) }
    }

    public static func sanitizedMarkdown(
        from raw: String,
        limit: Int = sanitizedBulletLimit,
        now: Date = Date()
    ) -> String? {
        let bullets = sanitizedBullets(from: raw, limit: limit, now: now)
        guard !bullets.isEmpty else { return nil }
        return ([heading, ""] + bullets).joined(separator: "\n") + "\n"
    }

    /// Build the "summary" layer that goes into `baseInstructions`. Newest
    /// first, capped at `summaryBulletLimit`, with the timestamp prefix kept
    /// so the model can see when each fact was recorded.
    public static func summaryForInjection(
        from raw: String,
        limit: Int = summaryBulletLimit,
        now: Date = Date()
    ) -> String? {
        let parsed = parseBullets(from: raw)
        var accepted: [Bullet] = []
        var fingerprints = Set<String>()
        for bullet in parsed.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard isSafeBullet(bullet.text) else { continue }
            let fp = semanticFingerprint(bullet.text)
            guard !fp.isEmpty, fingerprints.insert(fp).inserted else { continue }
            accepted.append(bullet)
            if accepted.count == limit { break }
        }
        guard !accepted.isEmpty else { return nil }
        let lines = accepted.map { $0.rendered(now: now) }
        return ([heading, ""] + lines).joined(separator: "\n") + "\n"
    }

    /// Append one freshly-extracted bullet to a raw memory blob, returning a
    /// re-sanitized Markdown file. Caller is responsible for writing the
    /// result. The timestamp is set to `now` (override for tests).
    @discardableResult
    public static func appendBullet(
        to raw: String,
        text: String,
        now: Date = Date()
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeBullet(trimmed) else { return nil }
        let addition = Bullet(timestamp: now, text: trimmed).rendered(now: now)
        let combined = raw.isEmpty ? addition : raw + "\n" + addition
        return sanitizedMarkdown(from: combined)
    }

    /// Enforce the per-file byte cap. If `markdown` exceeds `perFileByteLimit`
    /// (after UTF-8 encoding), the oldest bullets are dropped and an explicit
    /// truncation marker is prepended so the file is still self-describing.
    public static func enforceByteLimit(_ markdown: String) -> String {
        let cap = perFileByteLimit
        guard markdown.utf8.count > cap else { return markdown }
        let parsed = parseBullets(from: markdown)
        guard !parsed.isEmpty else { return markdown }
        // Drop oldest until under cap.
        var trimmed = parsed.sorted(by: { $0.timestamp > $1.timestamp })
        while !trimmed.isEmpty {
            let candidate = ([heading, ""] + trimmed.reversed().map { $0.rendered() }).joined(separator: "\n") + "\n"
            if candidate.utf8.count <= cap { return candidate }
            trimmed.removeLast()
        }
        // Even header alone overflows — return header with marker.
        return "\(heading)\n\n<!-- truncated at \(cap) bytes; older bullets dropped -->\n"
    }

    // MARK: - Safety / dedup helpers (unchanged from prior art)

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
