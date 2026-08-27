import Foundation
@testable import TapgoCore

@MainActor
func runReviewCommentAddAndFetch(_ t: TestRunner) {
    t.section("ReviewCommentStore: add then fetch by fileChangeId")
    let store = ReviewCommentStore()
    let c = ReviewComment(
        fileChangeId: "fc-1", lineKey: "add:0:1:hello",
        oldLineNumber: nil, newLineNumber: 1,
        side: .new, text: "looks good")
    store.add(c)
    let fetched = store.comments(for: "fc-1")
    t.expectEqual(fetched.count, 1, "one comment for fc-1")
    t.expectEqual(fetched.first?.text, "looks good", "text round-trips")
    t.expectEqual(store.comments(for: "fc-2").count, 0, "no comments for fc-2")
}

@MainActor
func runReviewCommentFetchByLineKey(_ t: TestRunner) {
    t.section("ReviewCommentStore: filter by lineKey")
    let store = ReviewCommentStore()
    store.add(ReviewComment(fileChangeId: "f", lineKey: "a", side: .new, text: "x"))
    store.add(ReviewComment(fileChangeId: "f", lineKey: "b", side: .new, text: "y"))
    store.add(ReviewComment(fileChangeId: "f", lineKey: "a", side: .old, text: "z"))
    let onA = store.comments(for: "f", lineKey: "a")
    t.expectEqual(onA.count, 2, "two comments on line 'a'")
    let onB = store.comments(for: "f", lineKey: "b")
    t.expectEqual(onB.count, 1, "one on 'b'")
}

@MainActor
func runReviewCommentUpdate(_ t: TestRunner) {
    t.section("ReviewCommentStore: update text by id")
    let store = ReviewCommentStore()
    let c = ReviewComment(fileChangeId: "f", lineKey: "k", side: .new, text: "old")
    store.add(c)
    let now = Date(timeIntervalSince1970: 5000)
    let ok = store.update(id: c.id, text: "new", at: now)
    t.expect(ok, "update returns true")
    let fetched = store.comments(for: "f").first!
    t.expectEqual(fetched.text, "new", "text updated")
    t.expectEqual(fetched.updatedAt, now, "updatedAt set")
}

@MainActor
func runReviewCommentUpdateMiss(_ t: TestRunner) {
    t.section("ReviewCommentStore: update on missing id returns false")
    let store = ReviewCommentStore()
    let ok = store.update(id: UUID(), text: "x")
    t.expect(!ok, "miss returns false")
}

@MainActor
func runReviewCommentRemove(_ t: TestRunner) {
    t.section("ReviewCommentStore: remove by id")
    let store = ReviewCommentStore()
    let a = ReviewComment(fileChangeId: "f", lineKey: "1", side: .new, text: "a")
    let b = ReviewComment(fileChangeId: "f", lineKey: "2", side: .new, text: "b")
    store.add(a); store.add(b)
    let ok = store.remove(id: a.id)
    t.expect(ok, "remove returns true")
    let remaining = store.comments(for: "f")
    t.expectEqual(remaining.count, 1, "one remains")
    t.expectEqual(remaining.first?.id, b.id, "the other one")
}

@MainActor
func runReviewCommentRemoveAll(_ t: TestRunner) {
    t.section("ReviewCommentStore: removeAll(fileChangeId) clears that file only")
    let store = ReviewCommentStore()
    store.add(ReviewComment(fileChangeId: "x", lineKey: "k", side: .new, text: "1"))
    store.add(ReviewComment(fileChangeId: "y", lineKey: "k", side: .new, text: "2"))
    store.removeAll(for: "x")
    t.expectEqual(store.comments(for: "x").count, 0, "x cleared")
    t.expectEqual(store.comments(for: "y").count, 1, "y untouched")
}

@MainActor
func runReviewCommentClear(_ t: TestRunner) {
    t.section("ReviewCommentStore: clear wipes everything")
    let store = ReviewCommentStore()
    store.add(ReviewComment(fileChangeId: "a", lineKey: "k", side: .new, text: "x"))
    store.add(ReviewComment(fileChangeId: "b", lineKey: "k", side: .new, text: "y"))
    store.clear()
    t.expectEqual(store.allComments().count, 0, "all gone")
}

@MainActor
func runReviewCommentAllComments(_ t: TestRunner) {
    t.section("ReviewCommentStore: allComments spans every file")
    let store = ReviewCommentStore()
    store.add(ReviewComment(fileChangeId: "a", lineKey: "k", side: .new, text: "1"))
    store.add(ReviewComment(fileChangeId: "b", lineKey: "k", side: .new, text: "2"))
    store.add(ReviewComment(fileChangeId: "a", lineKey: "k2", side: .new, text: "3"))
    t.expectEqual(store.allComments().count, 3, "3 across all files")
}

@MainActor
func runReviewCommentCodableRoundTrip(_ t: TestRunner) {
    t.section("ReviewComment: Codable round-trips through JSON")
    // Pin the timestamp to a whole-second boundary so iso8601 (which
    // has 1-second precision) round-trips losslessly. Without this
    // the default Date() sub-microsecond precision would be truncated
    // and the equality comparison would (correctly) fail.
    let pinned = Date(timeIntervalSince1970: 1_700_000_000)
    let original = ReviewComment(
        fileChangeId: "f", lineKey: "k",
        oldLineNumber: 1, newLineNumber: 2,
        side: .both, text: "interesting",
        createdAt: pinned, updatedAt: pinned)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(original)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try! decoder.decode(ReviewComment.self, from: data)
    t.expectEqual(decoded, original, "round-trip equal (iso8601, pinned sec)")
}

@MainActor
func runReviewCommentHunkLevelUsesEmptyKey(_ t: TestRunner) {
    t.section("ReviewComment: hunk-level comment uses empty lineKey")
    let c = ReviewComment(fileChangeId: "f", lineKey: "", side: .both, text: "hunk note")
    t.expectEqual(c.lineKey, "", "empty key for hunk-level")
    t.expectEqual(c.side, .both, "side = both for hunk-level")
}

@MainActor
func runReviewCommentStoreConcurrency(_ t: TestRunner) {
    // Smoke test: many concurrent adds + reads don't crash. Swift's
    // NSLock inside the store should keep things coherent.
    t.section("ReviewCommentStore: 100 concurrent adds don't lose data")
    let store = ReviewCommentStore()
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "review-comment-concurrency", attributes: .concurrent)
    for i in 0..<100 {
        group.enter()
        queue.async {
            store.add(ReviewComment(fileChangeId: "f-\(i % 10)", lineKey: "k", side: .new, text: "msg \(i)"))
            group.leave()
        }
    }
    group.wait()
    t.expectEqual(store.allComments().count, 100, "all 100 retained")
}
