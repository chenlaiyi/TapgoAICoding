import Foundation
import XCTest

final class MobileDeliverablesTests: XCTestCase {
    func testDeduplicatesAndNamesDeliverables() {
        let files = MobileDeliverables.list([" /tmp/out/experience-8.jpg ", "/tmp/out/experience-8.jpg", ""])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "experience-8.jpg")
        XCTAssertTrue(files[0].isImage)
        XCTAssertEqual(files[0].subtitle, "out")
    }

    func testDeduplicatesAbsoluteDeliverableAgainstRelativeLink() {
        let files = MobileDeliverables.merged(deliverables: ["/tmp/out/wechat-317/experience-8.jpg",
                                                            "/tmp/out/wechat/run.md"],
                                              text: "[png](experience-8.jpg) [md](run.md)")
        XCTAssertEqual(files.map(\.name), ["experience-8.jpg", "run.md"])
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(MobileDeliverables.sameFile("/a/wechat/run.md", "run.md"))
        XCTAssertFalse(MobileDeliverables.sameFile("/a/wechat/run.md", "/b/other/run.md"))
    }

    func testExtractsLocalMarkdownFileLinks() {
        let text = "见 [二维码](file:///tmp/out/experience-8.jpg) 和 [记录](./docs/run.md)，以及 [网页](https://x.test/a.md)。"
        XCTAssertEqual(MobileDeliverables.linkedFiles(in: text),
                       ["/tmp/out/experience-8.jpg", "docs/run.md"])
    }

    func testMergesDeliverablesWithLinksAndSkipsNonFiles() {
        let files = MobileDeliverables.merged(deliverables: ["/tmp/a.md"],
                                              text: "[b](b.png) [link](https://example.com) [again](/tmp/a.md)")
        XCTAssertEqual(files.map(\.path), ["/tmp/a.md", "b.png"])
        XCTAssertFalse(MobileDeliverables.merged(deliverables: [], text: "[link](https://example.com)").isEmpty == false)
    }
}
