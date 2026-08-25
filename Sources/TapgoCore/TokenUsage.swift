import Foundation

/// Token usage reported by the harness for a completed turn. Mirrors
/// the codex `TokenUsage` shape (`input_tokens`, `output_tokens`,
/// `total_tokens`, `cached_input_tokens`, `reasoning_output_tokens`)
/// so the UI can show a small "tokens used" caption like Codex does.
public struct TokenUsage: Hashable, Codable {
    public var input: Int
    public var output: Int
    public var total: Int
    public var cached: Int
    public var reasoning: Int
    /// Harness model context window, when reported — used to show a
    /// "% context used" figure.
    public var contextWindow: Int?

    public init(
        input: Int = 0,
        output: Int = 0,
        total: Int = 0,
        cached: Int = 0,
        reasoning: Int = 0,
        contextWindow: Int? = nil
    ) {
        self.input = input
        self.output = output
        self.total = total
        self.cached = cached
        self.reasoning = reasoning
        self.contextWindow = contextWindow
    }

    /// Best-effort parse of the usage JSON object. The harness has used
    /// both camelCase and snake_case keys across versions, so we accept
    /// either. Returns nil when there is no usable usage object (so the
    /// UI can hide the caption entirely).
    public static func fromJSON(_ value: JSONValue?) -> TokenUsage? {
        guard let obj = value?.objectValue else { return nil }

        func num(_ keys: [String]) -> Int {
            for k in keys {
                if let n = obj[k]?.intOrBoolAsInt { return n }
            }
            return 0
        }

        let input = num(["inputTokens", "input_tokens"])
        let output = num(["outputTokens", "output_tokens"])
        let total = num(["totalTokens", "total_tokens"])
        let cached = num([
            "cachedTokens", "cachedInputTokens", "cached_input_tokens",
            "cacheWriteInputTokens", "cache_write_input_tokens",
        ])
        let reasoning = num(["reasoningOutputTokens", "reasoning_output_tokens"])
        let contextWindow = obj["modelContextWindow"]?.intOrBoolAsInt
            ?? obj["model_context_window"]?.intOrBoolAsInt

        if input == 0, output == 0, total == 0, cached == 0, reasoning == 0, contextWindow == nil {
            return nil
        }
        return TokenUsage(
            input: input,
            output: output,
            total: total,
            cached: cached,
            reasoning: reasoning,
            contextWindow: contextWindow
        )
    }

    /// Percentage of the model context window used, when the harness
    /// reported a context window and we have a total. `nil` if unknown.
    public var contextPercent: Int? {
        guard let cw = contextWindow, cw > 0, total > 0 else { return nil }
        return Int((Double(total) / Double(cw) * 100).rounded())
    }

    /// Coarse context-pressure level derived from `contextPercent`, so
    /// the UI can colour the context meter like Codex does (green →
    /// yellow → red as the window fills).
    public var contextLevel: ContextLevel? {
        guard let pct = contextPercent else { return nil }
        if pct >= 80 { return .critical }
        if pct >= 50 { return .warn }
        return .normal
    }

    /// A compact human-readable summary, e.g. "1.2k tokens · input 800 · 已用 context 12%".
    public var summary: String {
        let totalPart = total > 0 ? Self.short(total) : "—"
        var parts = ["\(totalPart) tokens"]
        if input > 0 || output > 0 {
            parts.append("↑\(Self.short(input)) ↓\(Self.short(output))")
        }
        if cached > 0 {
            parts.append("cache \(Self.short(cached))")
        }
        if reasoning > 0 {
            parts.append("reasoning \(Self.short(reasoning))")
        }
        if let pct = contextPercent {
            parts.append("context \(pct)%")
        }
        return parts.joined(separator: " · ")
    }

    /// Compact human-readable total (e.g. "1.2k tokens") for an aggregate.
    public static func summary(of total: Int) -> String {
        "\(short(total)) tokens"
    }

    private static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

/// Coarse context-pressure level used to colour the context meter.
public enum ContextLevel: Equatable {
    case normal, warn, critical
}
