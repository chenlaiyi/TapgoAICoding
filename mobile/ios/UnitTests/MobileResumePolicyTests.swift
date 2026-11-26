import XCTest
import Foundation

final class MobileResumePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testForegroundWithoutBackgroundKeepsTheSocket() {
        XCTAssertFalse(MobileResumePolicy.mustReconnect(backgroundedAt: nil, now: now))
    }

    func testBriefInterruptionKeepsTheSocket() {
        XCTAssertFalse(MobileResumePolicy.mustReconnect(backgroundedAt: now.addingTimeInterval(-1), now: now))
    }

    func testLongerBackgroundReplacesTheSocket() {
        XCTAssertTrue(MobileResumePolicy.mustReconnect(backgroundedAt: now.addingTimeInterval(-3), now: now))
        XCTAssertTrue(MobileResumePolicy.mustReconnect(backgroundedAt: now.addingTimeInterval(-600), now: now))
    }

    func testVisibleRefreshAlwaysReadsComposerSettings() {
        XCTAssertTrue(MobileResumePolicy.shouldRefreshComposer(
            lastRefreshedAt: now, quietly: false, hasModels: true, now: now))
    }

    func testQuietPollReadsMissingCatalogImmediately() {
        XCTAssertTrue(MobileResumePolicy.shouldRefreshComposer(
            lastRefreshedAt: now, quietly: true, hasModels: false, now: now))
        XCTAssertTrue(MobileResumePolicy.shouldRefreshComposer(
            lastRefreshedAt: nil, quietly: true, hasModels: true, now: now))
    }

    func testQuietPollThrottlesComposerSettings() {
        XCTAssertFalse(MobileResumePolicy.shouldRefreshComposer(
            lastRefreshedAt: now.addingTimeInterval(-15), quietly: true, hasModels: true, now: now))
        XCTAssertTrue(MobileResumePolicy.shouldRefreshComposer(
            lastRefreshedAt: now.addingTimeInterval(-60), quietly: true, hasModels: true, now: now))
    }
}
