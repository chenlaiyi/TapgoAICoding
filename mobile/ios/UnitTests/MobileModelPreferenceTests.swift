import XCTest
import Foundation

final class MobileModelPreferenceTests: XCTestCase {
    private let computerID = "preference-\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "dsh.mobile.last-model.\(computerID)")
        UserDefaults.standard.removeObject(forKey: "dsh.mobile.last-effort.\(computerID)")
    }

    func testEffortRoundTripsWithTheRoute() {
        MobileModelPreference.save("deepseek-account/deepseek-v41-flash", effort: "high", computerID: computerID)
        XCTAssertEqual(MobileModelPreference.read(computerID: computerID), "deepseek-account/deepseek-v41-flash")
        XCTAssertEqual(MobileModelPreference.readEffort(computerID: computerID), "high")
    }

    func testSavingWithoutEffortClearsAStaleLevel() {
        MobileModelPreference.save("deepseek-account/deepseek-v41-flash", effort: "high", computerID: computerID)
        MobileModelPreference.save("deepseek-official/deepseek-chat", computerID: computerID)
        XCTAssertEqual(MobileModelPreference.read(computerID: computerID), "deepseek-official/deepseek-chat")
        XCTAssertNil(MobileModelPreference.readEffort(computerID: computerID))
    }

    func testComputersKeepSeparateSelections() {
        let other = "preference-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: "dsh.mobile.last-model.\(other)")
            UserDefaults.standard.removeObject(forKey: "dsh.mobile.last-effort.\(other)")
        }
        MobileModelPreference.save("provider/a", effort: "low", computerID: computerID)
        MobileModelPreference.save("provider/b", effort: "max", computerID: other)
        XCTAssertEqual(MobileModelPreference.read(computerID: computerID), "provider/a")
        XCTAssertEqual(MobileModelPreference.readEffort(computerID: computerID), "low")
        XCTAssertEqual(MobileModelPreference.read(computerID: other), "provider/b")
        XCTAssertEqual(MobileModelPreference.readEffort(computerID: other), "max")
    }
}
