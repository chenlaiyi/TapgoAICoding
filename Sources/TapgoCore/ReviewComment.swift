import Foundation

// MARK: - ReviewComment
//
// A pin attached to a single diff line. Stored by `ReviewCommentStore`,
// keyed by the `FileChange.id` it belongs to + the `DiffLine.stableKey`
// so that re-parsing a diff yields the same anchor as long as the
// content didn't change.

/// What side of the diff the comment is anchored to. "BOTH" is used for
/// hunk-level comments (no specific line chosen) and "CONTEXT" for
/// lines that exist on both sides of the diff.
public enum ReviewAnchorSide: String, Hashable, Codable, Sendable {
    case old       // anchored to a removed line (or the old number)
    case new       // anchored to an added/context line (new number)
    case both      // anchored to the hunk as a whole (no line number)
}

public struct ReviewComment: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let fileChangeId: String
    /// DiffLine.stableKey. Empty string = hunk-level (whole-file) comment.
    public let lineKey: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let side: ReviewAnchorSide
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        fileChangeId: String,
        lineKey: String,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil,
        side: ReviewAnchorSide,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.fileChangeId = fileChangeId
        self.lineKey = lineKey
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.side = side
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

// MARK: - ReviewCommentStore
//
// In-memory store keyed by `FileChange.id`. Thread-safe (NSLock).
// Persistence (to disk / session JSON) is left to the app layer so the
// Core type stays free of filesystem concerns; the app can serialise
// `allComments()` and reload it on session restore.

/// Thread-safe (NSLock) review-comment store.
///
/// Conforms to `ObservableObject` so SwiftUI views can hold it as a
/// `@StateObject` / `@ObservedObject` and re-render when comments are
/// added / updated / removed. The `@Published` projection of the
/// internal dictionary is what drives the view updates; thread safety
/// is still guaranteed by the lock around the underlying mutation.
public final class ReviewCommentStore: ObservableObject, @unchecked Sendable {
    @Published private var storage: [String: [ReviewComment]] = [:]   // fileChangeId -> comments
    private let lock = NSLock()

    public init() {}

    /// All comments for a given file change, in insertion order.
    public func comments(for fileChangeId: String) -> [ReviewComment] {
        lock.lock(); defer { lock.unlock() }
        return storage[fileChangeId] ?? []
    }

    /// Comments attached to a single line.
    public func comments(for fileChangeId: String, lineKey: String) -> [ReviewComment] {
        lock.lock(); defer { lock.unlock() }
        return (storage[fileChangeId] ?? []).filter { $0.lineKey == lineKey }
    }

    /// Snapshot of every comment across every file.
    public func allComments() -> [ReviewComment] {
        lock.lock(); defer { lock.unlock() }
        return storage.values.flatMap { $0 }
    }

    @discardableResult
    public func add(_ comment: ReviewComment) -> ReviewComment {
        lock.lock(); defer { lock.unlock() }
        storage[comment.fileChangeId, default: []].append(comment)
        return comment
    }

    /// Update an existing comment's text. Returns true on hit.
    @discardableResult
    public func update(id: UUID, text: String, at now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        for (fileId, list) in storage {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                var c = list[idx]
                c.text = text
                c.updatedAt = now
                storage[fileId, default: []][idx] = c
                return true
            }
        }
        return false
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        for (fileId, list) in storage {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                storage[fileId]?.remove(at: idx)
                return true
            }
        }
        return false
    }

    /// Remove every comment for a given file change.
    public func removeAll(for fileChangeId: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: fileChangeId)
    }

    /// Drop everything. Used on session reset.
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}
