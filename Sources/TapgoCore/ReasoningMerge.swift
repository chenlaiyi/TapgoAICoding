import Foundation

/// Decides what text to show for a completed `reasoning` item.
///
/// The harness streams the detailed reasoning trace live
/// (`reasoning/textDelta`) and then, at item completion, sends a
/// condensed `summary`. Codex-style UIs keep the trace (collapsed by
/// default) rather than throwing it away in favour of the summary, so we
/// only use the summary when no trace actually streamed.
public enum ReasoningMerge {
    public static func finalizeText(streamed: String, summary: [String]) -> String {
        let trimmed = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return streamed }
        return summary.joined(separator: "\n")
    }
}
