import Foundation

/// Phase 2 of the memory pipeline (Codex-style "consolidation"). Runs after
/// `MemoryWriter` has appended fresh bullets and produces a compact summary
/// suitable for `baseInstructions` injection.
///
/// Unlike Phase 1 — which only appends raw bullets and re-sanitizes — Phase 2
/// has the explicit job of:
///
///   1. Reading the persisted raw file.
///   2. Asking the model (or a deterministic heuristic) to merge duplicates,
///      supersede stale facts, and prune entries older than the configured
///      horizon.
///   3. Rewriting the file in canonical form so future readers see a clean,
///      deduped state.
///
/// Consolidation is **idempotent**: running it twice on the same file is a
/// no-op. It also never throws — failures are returned as `.skipped` so the
/// caller can log and move on without blocking a turn.
public enum MemoryConsolidator {

    /// Result categories so callers / tests can tell apart a true no-op
    /// (already consolidated) from a transient skip (network failure).
    public enum Outcome: Equatable {
        /// Rewrote the file with a more compact / deduped form.
        case rewrote
        /// Source file already in canonical form; no change needed.
        case alreadyConsolidated
        /// Could not consolidate right now (e.g. no model call made). The
        /// source file is untouched.
        case skipped(reason: String)
    }

    /// Run a single consolidation pass against `url`. The caller decides when
    /// to invoke this — typically on App startup and after each successful
    /// Phase 1 extraction. The function is async because the LLM-backed path
    /// may need to round-trip; pass `modelRunner = nil` to use the
    /// deterministic fast path that only re-sanitizes / dedups.
    public static func consolidate(
        url: URL,
        modelRunner: ModelRunner? = nil,
        maxAge: TimeInterval = 60 * 60 * 24 * 90,
        now: Date = Date()
    ) async -> Outcome {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .skipped(reason: "file missing")
        }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return .skipped(reason: "read failure")
        }
        let parsed = DurableMemory.parseBullets(from: raw)
        guard !parsed.isEmpty else {
            return .skipped(reason: "empty file")
        }

        // 1. Deterministic pruning: drop anything older than `maxAge`.
        let cutoff = now.addingTimeInterval(-maxAge)
        let fresh = parsed.filter { $0.timestamp >= cutoff || $0.timestamp == .distantPast }

        // 2. Re-sanitize (idempotent dedup + canonical ordering + byte cap).
        let canonical = fresh.map { $0.text }
            .joined(separator: "\n")
        let sanitized = DurableMemory.sanitizedMarkdown(from: canonical)
            ?? DurableMemory.enforceByteLimit(canonical)
        let capped = DurableMemory.enforceByteLimit(sanitized)

        // 3. Optional model pass for richer merge / supersession.
        var final = capped
        if let runner = modelRunner {
            if let merged = await runner.consolidate(raw: capped, now: now) {
                final = DurableMemory.enforceByteLimit(merged)
            }
        }

        // 4. Idempotency: bail if nothing changed.
        if final == raw {
            return .alreadyConsolidated
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try final.write(to: url, atomically: true, encoding: .utf8)
            return .rewrote
        } catch {
            return .skipped(reason: "write failure: \(error.localizedDescription)")
        }
    }
}

/// Pluggable LLM runner for Phase 2. Production code passes
/// `MemoryConsolidationLLM` (which calls MiniMax-M3 with the same model name
/// and key plumbing as `MemoryWriter`); tests pass a deterministic fake.
public protocol ModelRunner: Sendable {
    func consolidate(raw: String, now: Date) async -> String?
}
