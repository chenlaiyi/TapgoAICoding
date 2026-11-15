import Foundation

/// Bounded, process-local preview of job.follow; offsets are UTF-8 bytes, independent of the model cursor.
struct MobileToolOutput: Equatable, Identifiable {
    enum Phase: String { case connecting, streaming, completed, stopped, failed, disconnected, unavailable }
    let id: String
    let owner: String
    private(set) var text = ""
    private(set) var nextOffset = 0
    private(set) var gap = false
    private(set) var phase: Phase = .connecting
    private(set) var revision = 0
    private var anchored = false
    static let retainedBytes = 64 * 1024

    init(id: String, owner: String) { self.id = id; self.owner = owner }

    var active: Bool { [.connecting, .streaming, .disconnected].contains(phase) }
    var status: String {
        switch phase {
        case .connecting: "正在同步输出"
        case .streaming: "实时输出"
        case .completed: "输出已结束"
        case .stopped: "已停止 · 保留部分输出"
        case .failed: "执行失败 · 保留输出"
        case .disconnected: "连接中断 · 保留部分输出"
        case .unavailable: "实时输出暂不可用"
        }
    }

    mutating func begin() { anchored = false; phase = .connecting }
    mutating func disconnect() { if active { phase = .disconnected; anchored = false } }
    mutating func unavailable() { phase = .unavailable; anchored = false }

    mutating func receive(_ frame: [String: Any]) {
        switch frame["type"] as? String {
        case "opened":
            guard let job = frame["job"] as? [String: Any], job["id"] as? String == id,
                  job["owner"] as? String == owner, let start = frame["from"] as? Int, start >= 0 else {
                unavailable(); return
            }
            if start > nextOffset { gap = true; nextOffset = start }
            anchored = true
            phase = .streaming
        case "output":
            guard anchored, let chunks = frame["chunks"] as? [[String: Any]],
                  let next = frame["next"] as? Int, next >= nextOffset else { return }
            guard chunks.allSatisfy({ chunk in
                guard let at = chunk["at"] as? Int, at >= 0, let value = chunk["text"] as? String else { return false }
                let count = value.utf8.count
                return at <= Int.max - count && at + count <= next
            }) else { unavailable(); return }
            if frame["lossy"] as? Bool == true { gap = true }
            for chunk in chunks {
                guard let start = chunk["at"] as? Int, start >= 0, let value = chunk["text"] as? String else { continue }
                let bytes = Array(value.utf8)
                guard start <= Int.max - bytes.count else { continue }
                let end = start + bytes.count
                if end <= nextOffset { continue }
                if start > nextOffset || chunk["gapBefore"] as? Bool == true { gap = true }
                let skip = max(0, nextOffset - start)
                if let addition = String(bytes: bytes.dropFirst(skip), encoding: .utf8) { text += addition }
                else { gap = true }
                nextOffset = end
            }
            if next > nextOffset { gap = true }
            nextOffset = max(nextOffset, next)
            trim()
            revision += 1
        case "status":
            guard anchored, let job = frame["job"] as? [String: Any], job["id"] as? String == id else { return }
            if let total = (job["output"] as? [String: Any])?["total"] as? Int, total > nextOffset { gap = true }
            switch job["status"] as? String {
            case "completed": phase = .completed
            case "killed": phase = .stopped
            case "failed": phase = .failed
            default: unavailable()
            }
            revision += 1
        default: break
        }
    }

    private mutating func trim() {
        let bytes = Array(text.utf8)
        guard bytes.count > Self.retainedBytes else { return }
        var start = bytes.count - Self.retainedBytes
        while start < bytes.count && bytes[start] & 0xC0 == 0x80 { start += 1 }
        text = String(decoding: bytes[start...], as: UTF8.self)
        gap = true
    }
}
