import XCTest

final class MobileConnectionUITests: XCTestCase {
    func testProjectMenuAndAddFolderEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--dsh-mobile-test-url", "https://studio.example/?token=fixture&name=Studio%20Mac",
                               "--dsh-mobile-test-sessions",
                               """
                               [{"sessionId":"one","cwd":"/work/TapgoAICoding","running":false,"updatedAt":2,"projections":{"values":{"title":"First"}}},{"sessionId":"two","cwd":"/work/Third","running":false,"updatedAt":1,"projections":{"values":{"title":"Second"}}}]
                               """]
        app.launch()
        app.buttons["新对话输入框"].tap()
        app.buttons["选择项目目录"].tap()
        XCTAssertTrue(app.buttons["不在项目中工作"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Third"].exists)
        XCTAssertTrue(app.buttons["添加新文件夹"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Third"].tap()
        XCTAssertTrue(app.staticTexts["Third"].exists)
        app.buttons["选择项目目录"].tap()
        app.buttons["添加新文件夹"].tap()
        XCTAssertTrue(app.navigationBars["添加项目"].waitForExistence(timeout: 3))
    }

    func testTopMenuSortAndManagement() {
        let app = XCUIApplication()
        app.launchArguments = ["--dsh-mobile-test-url", "https://studio.example/?token=fixture&name=Studio%20Mac",
                               "--dsh-mobile-test-sessions", "[]",
                               "--dsh-mobile-test-balance", "23.51"]
        app.launch()
        app.buttons["打开顶部菜单"].tap()
        XCTAssertTrue(app.buttons["按项目"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["按时间倒序排列"].exists)
        XCTAssertTrue(app.buttons["添加连接"].exists)
        XCTAssertTrue(app.buttons["设置"].exists)
        XCTAssertTrue(app.staticTexts["¥23.51"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["按时间倒序排列"].tap()
        XCTAssertFalse(app.buttons["添加连接"].exists)
        app.buttons["打开顶部菜单"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["远程控制"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)
        XCTAssertTrue(app.buttons["添加连接"].exists)
        XCTAssertTrue(app.switches["Studio Mac"].exists)
        let settingsScreenshot = XCTAttachment(screenshot: app.screenshot())
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)
    }

    func testNewConversationComposerLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--dsh-mobile-test-url", "https://studio.example/?token=fixture&name=Studio%20Mac",
                               "--dsh-mobile-test-sessions", "[]",
                               "--dsh-mobile-test-balance", "23.5067",
                               "--dsh-mobile-test-bonus", "5.00"]
        app.launch()
        app.buttons["新对话输入框"].tap()
        XCTAssertTrue(app.buttons["返回远程首页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)
        XCTAssertTrue(app.staticTexts["默认工作区"].exists)
        XCTAssertTrue(app.staticTexts["在这台 Mac 工作"].exists)
        XCTAssertTrue(app.staticTexts["当前分支"].exists)
        XCTAssertTrue(app.textFields["newConversationInput"].exists)
        XCTAssertTrue(app.staticTexts["V41 Flash"].exists)
        XCTAssertTrue(app.staticTexts["余额 ¥28.51"].exists)
        let permission = app.buttons["访问权限"]
        let model = app.staticTexts["V41 Flash"]
        let balance = app.staticTexts["余额 ¥28.51"]
        XCTAssertLessThan(abs(permission.frame.midY - model.frame.midY), 12)
        XCTAssertLessThan(abs(model.frame.midY - balance.frame.midY), 12)
        XCTAssertLessThan(permission.frame.maxX, model.frame.minX)
        XCTAssertLessThan(model.frame.maxX, balance.frame.minX)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["访问权限"].tap()
        XCTAssertTrue(app.buttons["完全权限"].waitForExistence(timeout: 3))
        app.buttons["完全权限"].tap()
        XCTAssertFalse(app.buttons["选择模型"].exists)
        app.buttons["收起键盘"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testChatKeyboardCanDismiss() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://keyboard.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"keyboard\",\"cwd\":\"/work/TapgoAICoding\",\"running\":false,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"键盘测试\"}}}]",
            "--dsh-mobile-test-events", "[]"
        ]
        app.launch()
        app.buttons["键盘测试"].tap()
        let composer = app.descendants(matching: .any)["chatComposerInput"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["收起键盘"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testFixturePairingDoesNotRemainActive() {
        let app = XCUIApplication()
        app.launchArguments = ["--dsh-mobile-test-url",
                               "https://isolated-only.example/?token=fixture&name=Temporary%20Test%20Mac"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Temporary Test Mac"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertFalse(app.staticTexts["Temporary Test Mac"].exists)
    }

    func testAssistantMarkdownPresentation() throws {
        let app = XCUIApplication()
        let messages: [[String: Any]] = [
            ["id": 1, "role": "assistant", "reasoning": "先检查连接状态。", "text": ""],
            ["id": 2, "role": "assistant", "text": """
            ## 检查结果

            **服务正常**，详见 [文档](https://example.com)。

            第一行会继续
            第二行而不是硬换行。

            - 第一项
              - 子项目
            - [x] 已完成
            - [ ] 待完成

            ```bash
            printf ok
            ```

            | 项目 | 状态 |
            | --- | --- |
            | 连接 | 正常 |
            """]
        ]
        let payload = try JSONSerialization.data(withJSONObject: messages)
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://markdown.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"markdown\",\"cwd\":\"/work/TapgoAICoding\",\"running\":false,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"Markdown 示例\"}}}]",
            "--dsh-mobile-test-messages", String(decoding: payload, as: UTF8.self)
        ]
        app.launch()
        app.buttons["Markdown 示例"].tap()
        XCTAssertTrue(app.staticTexts["检查结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "服务正常")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["printf ok"].exists)
        XCTAssertTrue(app.staticTexts["连接"].exists)
        XCTAssertTrue(app.staticTexts["第一行会继续 第二行而不是硬换行。"].exists)
        XCTAssertTrue(app.staticTexts["子项目"].exists)
        XCTAssertTrue(app.staticTexts["已完成"].exists)
        XCTAssertTrue(app.staticTexts["待完成"].exists)
        XCTAssertTrue(app.buttons["复制"].exists)
        XCTAssertTrue(app.buttons["思考过程"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeTranscriptActivityGrouping() throws {
        let app = XCUIApplication()
        let events: [[String: Any]] = [
            ["seq": 1, "type": "turn/start", "data": ["turn": 1]],
            ["seq": 2, "type": "user/message", "data": ["source": ["kind": "user"],
                "content": [["type": "text", "text": "检查项目"]]]],
            ["seq": 3, "type": "assistant/message", "data": ["message": ["content": []],
                "stream": [["type": "reasoning-chunks", "texts": ["先检查项目文件。"]]]]],
            ["seq": 31, "type": "assistant/message", "data": ["message": ["content": [
                ["type": "text", "text": "先确认本地文件状态。"]]]]],
            ["seq": 4, "type": "tool/call", "data": ["callId": "read-1", "name": "read",
                "arguments": "{\"file_path\":\"README.md\"}"]],
            ["seq": 5, "type": "tool/result", "data": ["message": ["source": ["callId": "read-1"],
                "isError": false]]],
            ["seq": 6, "type": "assistant/attempt", "data": [
                "stream": [["type": "chunk", "chunk": ["type": "reasoning-delta",
                    "text": "继续检查命令输出。"]]]]],
            ["seq": 7, "type": "tool/call", "data": ["callId": "bash-1", "name": "bash",
                "arguments": "{\"command\":\"pwd\"}"]],
            ["seq": 8, "type": "tool/result", "data": ["message": ["source": ["callId": "bash-1"],
                "isError": false]]],
            ["seq": 9, "type": "assistant/message", "data": ["message": ["content": [
                ["type": "text", "text": """
                **检查完成**，项目可以正常访问。

                ```text
                admin/tests/water-purifier/LongServiceGradeMemberInfoTest.php
                ```

                | 项目 | 同步前 | 同步后 |
                | --- | --- | --- |
                | 工作区 | 14 改 | 干净 |
                """]]]]],
            ["seq": 10, "type": "turn/end", "data": ["turn": 1]]
        ]
        let payload = try JSONSerialization.data(withJSONObject: events)
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://transcript.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"native-transcript\",\"cwd\":\"/work/TapgoAICoding\",\"running\":false,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"检查项目\"}}}]",
            "--dsh-mobile-test-events", String(decoding: payload, as: UTF8.self)
        ]
        app.launch()
        app.buttons["检查项目"].tap()
        XCTAssertTrue(app.staticTexts["过程 · 2 项操作"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "过程 · 2 项操作").count, 1)
        XCTAssertFalse(app.staticTexts["README.md"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "检查完成")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["先确认本地文件状态。"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "复制回复")).count, 1)
        XCTAssertTrue(app.staticTexts["干净"].exists)
        XCTAssertFalse(app.staticTexts["工具运行完成"].exists)
        XCTAssertFalse(app.buttons["思考过程"].exists)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.lifetime = .keepAlways
        add(collapsed)
        app.staticTexts["过程 · 2 项操作"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "先检查项目文件")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "继续检查命令输出")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["README.md"].exists)
        XCTAssertTrue(app.staticTexts["pwd"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeTranscriptShowsLiveReply() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://stream.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"stream\",\"cwd\":\"/work/TapgoAICoding\",\"running\":true,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"实时回复\"}}}]",
            "--dsh-mobile-test-events", "[]",
            "--dsh-mobile-test-stream", "[{\"type\":\"start\"},{\"type\":\"chunk\",\"chunk\":{\"type\":\"text-delta\",\"text\":\"正在核对输出格式\"}}]"
        ]
        app.launch()
        app.buttons["实时回复"].tap()
        XCTAssertTrue(app.staticTexts["正在核对输出格式"].waitForExistence(timeout: 5))
    }

    func testRunningTurnShowsProcessAndStopButton() {
        let app = XCUIApplication()
        let events: [[String: Any]] = [
            ["seq": 1, "type": "turn/start", "data": ["turn": 1]],
            ["seq": 2, "type": "tool/call", "data": ["callId": "read-1", "name": "read",
                "arguments": "{\"file_path\":\"README.md\"}"]]
        ]
        let payload = try! JSONSerialization.data(withJSONObject: events)
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://running.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"running\",\"cwd\":\"/work/TapgoAICoding\",\"running\":true,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"运行中\"}}}]",
            "--dsh-mobile-test-events", String(decoding: payload, as: UTF8.self)
        ]
        app.launch()
        app.buttons["运行中"].tap()
        XCTAssertTrue(app.buttons["停止运行"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["README.md"].exists)
        app.staticTexts["过程 · 1 项操作"].tap()
        XCTAssertTrue(app.staticTexts["README.md"].exists)
        XCTAssertFalse(app.buttons["发送"].exists)
    }

    func testRemoteProjectsAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url",
            "https://studio.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            """
            [{"sessionId":"pin-one","cwd":"/work/TapgoAICoding","running":false,"updatedAt":4,"projections":{"values":{"title":"本项目最新代码应该是在 jkmacmini"}}},{"sessionId":"pin-two","cwd":"/work/Third","running":false,"updatedAt":3,"projections":{"values":{"title":"检查服务模块开发情况"}}},{"sessionId":"one","cwd":"/work/TapgoAICoding","running":false,"updatedAt":2,"projections":{"values":{"title":"修复手机布局"}}},{"sessionId":"two","cwd":"/work/Third","running":true,"updatedAt":1,"projections":{"values":{"title":"检查服务器"}}}]
            """,
            "--dsh-mobile-test-pins", "pin-one,pin-two",
            "--dsh-mobile-test-balance", "23.5067",
            "--dsh-mobile-test-bonus", "5.00",
            "--dsh-mobile-test-messages",
            "[{\"id\":1,\"role\":\"user\",\"text\":\"检查服务器状态\"},{\"id\":2,\"role\":\"assistant\",\"text\":\"服务运行正常。接下来检查三个 Mac 的连接入口与会话同步。\"},{\"id\":3,\"role\":\"tool\",\"text\":\"已运行 8 条命令\"},{\"id\":4,\"role\":\"assistant\",\"text\":\"三台 Mac 的 HTTPS 入口均已返回预期结果。现在核对手机端会话列表和电脑名称。\"},{\"id\":5,\"role\":\"tool\",\"text\":\"正在读取会话列表\"},{\"id\":6,\"role\":\"assistant\",\"text\":\"电脑名称可以在 Mac 设置里自定义，手机连接后自动显示，也允许在手机上单独改名。\"},{\"id\":7,\"role\":\"user\",\"text\":\"继续检查 iOS 界面与远程连接\"}]"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["远程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)
        XCTAssertTrue(app.staticTexts["置顶"].exists)
        XCTAssertTrue(app.staticTexts["TapgoAICoding"].exists)
        XCTAssertTrue(app.buttons["修复手机布局"].exists)
        XCTAssertTrue(app.staticTexts["Third"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["搜索"].tap()
        let search = app.textFields["搜索项目或对话"]
        search.tap()
        search.typeText("服务器")
        XCTAssertTrue(app.buttons["检查服务器"].exists)
        XCTAssertFalse(app.buttons["修复手机布局"].exists)
        app.buttons["检查服务器"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "服务运行正常")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["发送"].exists)
        XCTAssertTrue(app.staticTexts["余额 ¥28.51"].waitForExistence(timeout: 3))
        app.buttons["添加与会话设置"].tap()
        XCTAssertTrue(app.buttons["选择模型与权限"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["添加图片"].exists)
        app.buttons["选择模型与权限"].tap()
        XCTAssertTrue(app.staticTexts["访问权限"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["模型额度"].exists)
        XCTAssertTrue(app.staticTexts["充值余额 ¥23.51"].exists)
        XCTAssertTrue(app.staticTexts["赠金余额 ¥5.00"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["V41 Flash"].exists)
        app.buttons["选择模型"].tap()
        XCTAssertTrue(app.staticTexts["选择模型"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["V41 Flash"].exists)
        app.buttons["完成"].tap()
        let chatScreenshot = XCTAttachment(screenshot: app.screenshot())
        chatScreenshot.lifetime = .keepAlways
        add(chatScreenshot)
        let composer = app.descendants(matching: .any)["chatComposerInput"]
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["访问权限"].exists)
        XCTAssertTrue(app.staticTexts["余额 ¥28.51"].exists)
        app.buttons["选择模型"].tap()
        XCTAssertTrue(app.staticTexts["选择模型"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        composer.tap()
        app.buttons["访问权限"].tap()
        XCTAssertTrue(app.buttons["仅可查看"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["工作区内修改"].exists)
        XCTAssertTrue(app.buttons["完全权限"].exists)
        let permissionScreenshot = XCTAttachment(screenshot: app.screenshot())
        permissionScreenshot.lifetime = .keepAlways
        add(permissionScreenshot)
        app.buttons["完全权限"].tap()
        let keyboardScreenshot = XCTAttachment(screenshot: app.screenshot())
        keyboardScreenshot.lifetime = .keepAlways
        add(keyboardScreenshot)
        app.buttons["收起键盘"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testApprovalPromptAnswersOnPhone() throws {
        let app = XCUIApplication()
        let approval: [String: Any] = ["eventId": "approval-1", "agentId": "background-task", "toolName": "bash",
                                       "reason": "该命令会修改工作区之外的文件"]
        let payload = try JSONSerialization.data(withJSONObject: approval)
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://approval.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"approval\",\"cwd\":\"/work/TapgoAICoding\",\"running\":true,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"需要确认的任务\"}}}]",
            "--dsh-mobile-test-events", "[]",
            "--dsh-mobile-test-global-approval", String(decoding: payload, as: UTF8.self)
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["需要你的确认"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["bash"].exists)
        XCTAssertTrue(app.staticTexts["该命令会修改工作区之外的文件"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["允许一次"].tap()
        XCTAssertTrue(app.staticTexts["需要你的确认"].waitForNonExistence(timeout: 3))
    }

    func testQuestionPromptAnswersOnPhone() throws {
        let app = XCUIApplication()
        let question: [String: Any] = [
            "eventId": "question-1", "agentId": "question",
            "questions": [[
                "id": "q1", "header": "确认范围",
                "question": "本次改动要覆盖哪些平台？",
                "multiSelect": true,
                "options": [["label": "iOS"], ["label": "macOS"], ["label": "Windows"]]
            ]]
        ]
        let payload = try JSONSerialization.data(withJSONObject: question)
        app.launchArguments = [
            "--dsh-mobile-test-url", "https://question.example/?token=fixture&name=Studio%20Mac",
            "--dsh-mobile-test-sessions",
            "[{\"sessionId\":\"question\",\"cwd\":\"/work/TapgoAICoding\",\"running\":true,\"updatedAt\":1,\"projections\":{\"values\":{\"title\":\"需要选择的改动\"}}}]",
            "--dsh-mobile-test-events", "[]",
            "--dsh-mobile-test-global-question", String(decoding: payload, as: UTF8.self)
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["需要你的回答"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["本次改动要覆盖哪些平台？"].exists)
        XCTAssertFalse(app.buttons["questionSubmit"].isEnabled)
        app.buttons["iOS"].tap()
        app.buttons["macOS"].tap()
        XCTAssertTrue(app.buttons["questionSubmit"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["questionSubmit"].tap()
        XCTAssertTrue(app.staticTexts["需要你的回答"].waitForNonExistence(timeout: 3))
    }

    func testCurrentMacAndSavedList() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--dsh-mobile-test-url",
            "https://mac-mini.tail.example:8443/?token=fixture&name=Studio%20Mac"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["远程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)

        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["设置"].exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "mac-mini.tail.example:8443"))
            .firstMatch.exists)
        app.buttons["重命名当前电脑"].tap()
        let rename = app.alerts["电脑名称"].textFields.firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        rename.typeText(" 工作")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].exists)

        app.buttons["远程, Studio Mac 工作"].tap()
        XCTAssertTrue(app.staticTexts["已配对的 Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].exists)
        XCTAssertFalse(app.buttons["重命名当前电脑"].exists)
        XCTAssertFalse(app.buttons["连接其他 Mac"].exists)
        app.buttons["完成"].tap()
        app.buttons["设置"].tap()
        app.buttons["连接其他 Mac"].tap()
        app.buttons["连接 Mac"].tap()
        XCTAssertTrue(app.buttons["从剪贴板粘贴"].exists)

        let link = app.textFields["https://…?token=…"]
        link.tap()
        link.typeText("https://macbook-pro.tail.example:8443/?token=fixture2&name=MacBook%20Pro")
        app.buttons["连接"].tap()
        XCTAssertTrue(app.staticTexts["MacBook Pro"].waitForExistence(timeout: 5))

        app.buttons["远程, MacBook Pro"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac 工作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Pro"].exists)
        XCTAssertFalse(app.buttons["重命名当前电脑"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Studio Mac 工作")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["远程"].waitForExistence(timeout: 5))
    }
}
