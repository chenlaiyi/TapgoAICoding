import Foundation

/// Tool presentation retains the complete call and returned text independently of its compact summary.
struct MobileChatActivity: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let category: String
    let invocation: String
    let parameters: String
    var finished = false
    var failed = false
    var cancelled = false
    var output: String?
    private(set) var exitCode: Int?
    private(set) var signal: String?

    init(id: String, name: String, detail: String, category: String, arguments: String = "") {
        self.id = id
        self.name = name
        self.detail = detail
        self.category = category
        let parsed = arguments.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        if let parsed, let data = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            parameters = text
        } else {
            parameters = arguments
        }
        invocation = parsed?["command"] as? String ?? parsed?["cmd"] as? String ?? parameters
    }

    mutating func receive(_ data: [String: Any]) {
        guard let message = data["message"] as? [String: Any] else { return }
        finished = true
        let blocks = message["content"] as? [[String: Any]] ?? []
        cancelled = (data["error"] as? [String: Any])?["code"] as? String == "ABORTED"
        failed = !cancelled && (message["isError"] as? Bool == true || blocks.contains { $0["isError"] as? Bool == true })
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n\n")
        output = text.isEmpty ? nil : text
        exitCode = nil
        signal = nil
        // Shell renderers own these trailing markers; arbitrary tool text does not imply an exit status.
        if ["bash", "pwsh"].contains(name), blocks.count == 1, !failed, !cancelled {
            exitCode = trailingMarker(text, pattern: #"\n\[exit code: (\d+)\]\z"#).flatMap(Int.init)
            signal = trailingMarker(text, pattern: #"\n\[killed by signal: ([^\]\n]+)\]\z"#)
            failed = exitCode.map { $0 != 0 } ?? (signal != nil)
        }
    }

    private func trailingMarker(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    var status: String {
        if cancelled { return "已停止" }
        if !finished { return "运行中" }
        if let exitCode { return "退出码 \(exitCode)" }
        if let signal { return "被信号终止 · \(signal)" }
        return failed ? "执行失败" : "已完成"
    }
}

/// Maps durable turn outcomes to distinct user-visible states, including extension-defined outcomes.
func mobileTurnStatus(_ reason: String?) -> String? {
    switch reason {
    case "aborted": return "已停止"
    case "error": return "任务失败"
    case "blocked": return "等待处理"
    case "interrupted": return "任务已中断"
    case "max-tokens": return "已达到输出上限"
    case "forked": return "已创建分支"
    case nil, "completed": return nil
    default: return "任务已结束"
    }
}
