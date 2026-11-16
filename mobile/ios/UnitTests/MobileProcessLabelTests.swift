import Foundation
import XCTest

final class MobileProcessLabelTests: XCTestCase {
    private func activity(_ name: String, finished: Bool = true, detail: String = "") -> MobileChatActivity {
        var value = MobileChatActivity(id: UUID().uuidString, name: name, detail: detail,
                                       category: "", arguments: "")
        value.finished = finished
        return value
    }

    func testMapsToolNamesToCategories() {
        XCTAssertEqual(MobileProcessLabel.category(for: "bash"), "commands")
        XCTAssertEqual(MobileProcessLabel.category(for: "exec_command"), "commands")
        XCTAssertEqual(MobileProcessLabel.category(for: "grep"), "search")
        XCTAssertEqual(MobileProcessLabel.category(for: "apply_patch"), "edit")
        XCTAssertEqual(MobileProcessLabel.category(for: "mystery"), "tools")
    }

    func testBuildsClosedTitlesLikeDSH() {
        XCTAssertEqual(MobileProcessLabel.title(activities: [], hasReasoning: true), "已完成分析")
        XCTAssertEqual(MobileProcessLabel.title(activities: [], hasReasoning: false), "已完成分析")
        XCTAssertEqual(MobileProcessLabel.title(activities: [activity("bash")], hasReasoning: true), "执行了命令")
        XCTAssertEqual(MobileProcessLabel.title(activities: [activity("read"), activity("grep")], hasReasoning: false),
                       "已读取文件并搜索代码")
        XCTAssertEqual(MobileProcessLabel.title(activities: [activity("bash"), activity("read"), activity("grep"),
                                                             activity("write")], hasReasoning: false),
                       "已读取文件，已搜索代码，已写入文件等")
    }

    func testRunningReasoningUsesTheDSHRunningLabel() {
        XCTAssertEqual(MobileProcessLabel.title(activities: [], hasReasoning: true, running: true), "正在分析请求")
    }

    func testRunningTitleCarriesTheCommandDetail() {
        XCTAssertEqual(MobileProcessLabel.title(activities: [activity("bash", finished: false, detail: "git status")],
                                                hasReasoning: true),
                       "正在运行命令 · git status")
    }
}
