import XCTest
import Foundation

final class MobileImageExportTests: XCTestCase {
    func testNameKeepsTheLeafAndAddsTheMediaExtension() {
        XCTAssertEqual(MobileImageExport.fileName(name: "照片.jpg", mediaType: "image/jpeg"), "照片.jpg")
        XCTAssertEqual(MobileImageExport.fileName(name: "../秘密 1", mediaType: "image/jpeg"), "秘密 1.jpg")
        XCTAssertEqual(MobileImageExport.fileName(name: nil, mediaType: "image/png"), "图片.png")
    }

    func testWritePlacesTheBytesUnderThatName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-image-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try MobileImageExport.write(data: Data([1, 2, 3]), name: "photo", mediaType: "image/jpeg",
                                              in: directory)
        XCTAssertEqual(url.lastPathComponent, "photo.jpg")
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }
}
