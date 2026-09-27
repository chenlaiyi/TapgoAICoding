import XCTest

final class MobileConnectionUITests: XCTestCase {
    func testCurrentMacAndSavedList() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url",
            "https://mac-mini.tail.example:8443/?token=fixture"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["当前电脑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mac-mini.tail.example"].exists)
        XCTAssertTrue(app.staticTexts["https://mac-mini.tail.example:8443"].exists)

        app.buttons["切换"].tap()
        XCTAssertTrue(app.staticTexts["已配对的 Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mac-mini.tail.example"].exists)

        let name = app.textFields["电脑名称（可选）"]
        name.tap()
        name.typeText("工作 Mac")
        let link = app.textFields["https://…?token=…"]
        link.tap()
        link.typeText("https://macbook-pro.tail.example:8443/?token=fixture2")
        app.buttons["连接"].tap()
        XCTAssertTrue(app.staticTexts["工作 Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["https://macbook-pro.tail.example:8443"].exists)

        app.buttons["切换"].tap()
        XCTAssertTrue(app.staticTexts["mac-mini.tail.example"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["工作 Mac"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "mac-mini.tail.example")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["https://mac-mini.tail.example:8443"].waitForExistence(timeout: 5))
    }
}
