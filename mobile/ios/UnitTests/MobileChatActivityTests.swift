import XCTest
import Foundation

final class MobileChatActivityTests: XCTestCase {
    func testCallKeepsCompleteCommandAndReturnedText() {
        let command = "python3 -c 'print(\"progress\")'\n" + String(repeating: "# details\n", count: 40)
        let data = try! JSONSerialization.data(withJSONObject: ["command": command, "description": "检查进度"])
        var activity = MobileChatActivity(id: "shell", name: "bash", detail: "检查进度", category: "运行命令",
            arguments: String(decoding: data, as: UTF8.self))
        XCTAssertEqual(activity.invocation, command)
        XCTAssertTrue(activity.parameters.contains("检查进度"))
        XCTAssertEqual(activity.status, "运行中")
        let output = String(repeating: "progress\n", count: 3000) + "DONE"
        activity.receive(["message": ["content": [["type": "text", "text": output]]]])
        XCTAssertEqual(activity.output, output)
        XCTAssertEqual(activity.status, "已完成")
    }

    func testCancellationIsDistinctFromToolFailureAndAbsentOutput() {
        var activity = MobileChatActivity(id: "shell", name: "bash", detail: "运行测试", category: "运行命令")
        activity.receive(["message": ["isError": true, "content": [["type": "text", "text": "Error: tool call aborted"]]],
            "error": ["code": "ABORTED"]])
        XCTAssertEqual(activity.status, "已停止")
        XCTAssertFalse(activity.failed)
        activity.receive(["message": ["isError": true, "content": [["type": "text", "text": "Permission denied"]]]])
        XCTAssertEqual(activity.status, "执行失败")
        XCTAssertEqual(activity.output, "Permission denied")
        activity.receive(["message": ["content": []]])
        XCTAssertEqual(activity.status, "已完成")
        XCTAssertNil(activity.output)
        XCTAssertEqual(mobileTurnStatus("aborted"), "已停止")
        XCTAssertEqual(mobileTurnStatus("error"), "任务失败")
        XCTAssertEqual(mobileTurnStatus("extension/result"), "任务已结束")
        XCTAssertNil(mobileTurnStatus("completed"))
    }
    func testLiveLineNamesTheRunningCommand() {
        let running = MobileChatActivity(id: "shell", name: "bash", detail: "git status", category: "运行命令")
        XCTAssertEqual(running.liveLine, "正在运行命令 · git status")
        let blank = MobileChatActivity(id: "read", name: "read", detail: "  ", category: "读取文件")
        XCTAssertEqual(blank.liveLine, "正在读取文件")
    }

    func testShellNonzeroExitIsNotPresentedAsSuccess() {
        var shell = MobileChatActivity(id: "shell", name: "bash", detail: "测试", category: "运行命令")
        shell.receive(["message": ["isError": false, "content": [["type": "text", "text": "SyntaxError\n[exit code: 1]"]]]])
        XCTAssertTrue(shell.failed)
        XCTAssertEqual(shell.exitCode, 1)
        XCTAssertEqual(shell.status, "退出码 1")
        shell.receive(["message": ["content": [["type": "text", "text": "output\n[killed by signal: SIGTERM]"]]]])
        XCTAssertTrue(shell.failed)
        XCTAssertEqual(shell.signal, "SIGTERM")
        shell.receive(["message": ["content": [["type": "text", "text": "[exit code: 1]"]]]])
        XCTAssertFalse(shell.failed)
        XCTAssertNil(shell.exitCode)
        var read = MobileChatActivity(id: "read", name: "read", detail: "文件", category: "读取文件")
        read.receive(["message": ["content": [["type": "text", "text": "file content\n[exit code: 1]"]]]])
        XCTAssertFalse(read.failed)
    }

}
