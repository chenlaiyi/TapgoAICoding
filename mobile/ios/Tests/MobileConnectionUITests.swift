import XCTest

final class MobileConnectionUITests: XCTestCase {
    func testCurrentMacAndSavedList() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url",
            "https://mac-mini.tail.example:8443/?token=fixture&name=Studio%20Mac"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["当前电脑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)
        XCTAssertTrue(app.staticTexts["https://mac-mini.tail.example:8443"].exists)

        app.buttons["改名"].tap()
        let rename = app.alerts["电脑名称"].textFields.firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        rename.typeText(" 工作")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].exists)

        app.buttons["切换"].tap()
        XCTAssertTrue(app.staticTexts["已配对的 Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].exists)

        let link = app.textFields["https://…?token=…"]
        link.tap()
        link.typeText("https://macbook-pro.tail.example:8443/?token=fixture2&name=MacBook%20Pro")
        app.buttons["连接"].tap()
        XCTAssertTrue(app.staticTexts["MacBook Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["https://macbook-pro.tail.example:8443"].exists)

        app.buttons["切换"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Pro"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Studio Mac 工作")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["https://mac-mini.tail.example:8443"].waitForExistence(timeout: 5))
    }
}
