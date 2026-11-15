import Foundation

/// The Host's committed feedback revision, used for compare-and-set updates.
struct MobileMessageFeedback: Decodable, Equatable {
    enum Rating: String, Decodable, Equatable { case positive, negative }
    let messageId: String
    let rating: Rating
    let version: String
    let note: String?
    let category: String?
}

/// A turn-scoped summary served by the Host for a workspace/changes event.
struct MobileChangesSummary: Decodable, Equatable {
    struct File: Decodable, Equatable {
        let path: String
        let display: String
        let added: Int
        let deleted: Int
        let binary: Bool?
        let oversized: Bool?
    }
    let turn: Int
    let files: [File]
    let total: Int
    let added: Int
    let deleted: Int

    var valid: Bool {
        turn >= 1 && total >= files.count && added >= 0 && deleted >= 0
            && files.allSatisfy { !$0.path.isEmpty && !$0.display.isEmpty && $0.added >= 0 && $0.deleted >= 0 }
    }
}

/// The Host's retained comparison; binary and oversized files have no text hunks.
struct MobileFileDiff: Decodable {
    enum Kind: String, Decodable, Equatable { case text, binary, oversized }
    struct Hunk: Decodable {
        let oldStart: Int
        let oldLines: Int
        let newStart: Int
        let newLines: Int
        let lines: [String]
    }
    let kind: Kind
    let path: String
    let display: String
    let hunks: [Hunk]?
    let before: Bool?
    let after: Bool?
    let coarse: Bool?
}

enum MobileReplyFailure: LocalizedError, Equatable {
    case unavailable, expired, invalidData
    var errorDescription: String? {
        switch self {
        case .unavailable: return "暂时无法读取，请重试"
        case .expired: return "这次文件变更的预览已不可用"
        case .invalidData: return "返回内容无法读取，请重试"
        }
    }
}
