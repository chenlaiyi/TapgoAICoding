import Foundation

/// Adds Chinese punctuation to dictation that returns bare words.
enum MobileVoicePunctuation {
    /// Pause between spoken segments that becomes a comma.
    static let commaPause: TimeInterval = 0.35
    /// Characters that already end a phrase.
    static let punctuation: Set<Character> = ["，", "。", "！", "？", ",", ".", "!", "?", "；", "…"]

    /// Rebuilds a transcript with commas at pauses and a final full stop.
    /// - Parameters:
    ///   - segments: recognized segments with their start time and duration.
    ///   - fallback: the recognizer's formatted string when segments are absent.
    /// - Returns: punctuated text.
    static func punctuated(_ segments: [(text: String, start: TimeInterval, duration: TimeInterval)],
                           fallback: String) -> String {
        let formatted = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatted.isEmpty else { return "" }
        if formatted.contains(where: { punctuation.contains($0) }) { return formatted }
        var output = ""
        var previousEnd: TimeInterval?
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if let previousEnd, segment.start - previousEnd > commaPause, !output.isEmpty {
                output += "，"
            }
            output += text
            previousEnd = segment.start + segment.duration
        }
        guard !output.isEmpty else { return finalStop(formatted) }
        return finalStop(output)
    }

    /// Appends a full stop when the text does not end in punctuation.
    /// - Parameter text: transcript without terminal punctuation.
    /// - Returns: text ending in `。`.
    static func finalStop(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, punctuation.contains(last) { return trimmed }
        return trimmed + "。"
    }
}
