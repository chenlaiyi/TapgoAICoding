import XCTest
import Foundation

final class MobileMultipartTests: XCTestCase {
    private func body(boundary: String, metadata: String, bytes: [UInt8]) -> Data {
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n".utf8))
        data.append(Data(metadata.utf8))
        data.append(Data("\r\n--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"bytes-0\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        data.append(Data(bytes))
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return data
    }

    func testParsesMetadataAndBinaryParts() throws {
        let metadata = #"{"result":{"ok":true},"attachments":[{"path":["data"],"part":"bytes-0"}]}"#
        let parsed = try MobileMultipart.parse(data: body(boundary: "dsh-boundary", metadata: metadata,
                                                          bytes: [0, 128, 255, 1, 13, 10]),
                                               contentType: "multipart/form-data; boundary=dsh-boundary")
        XCTAssertEqual(parsed["metadata"], Data(metadata.utf8))
        XCTAssertEqual(parsed["bytes-0"], Data([0, 128, 255, 1, 13, 10]))
    }

    func testParsesQuotedBoundary() throws {
        let parsed = try MobileMultipart.parse(data: body(boundary: "quoted", metadata: "{}", bytes: [7, 8]),
                                               contentType: "multipart/form-data; boundary=\"quoted\"; charset=utf-8")
        XCTAssertEqual(parsed["bytes-0"], Data([7, 8]))
    }

    func testRejectsMissingBoundaryOrFraming() {
        XCTAssertThrowsError(try MobileMultipart.parse(data: Data(), contentType: "application/json"))
        XCTAssertThrowsError(try MobileMultipart.parse(data: Data("garbage".utf8),
                                                       contentType: "multipart/form-data; boundary=none"))
    }

    func testFormatsSizes() {
        XCTAssertFalse(MobileFileSize.format(4_096).isEmpty)
        XCTAssertNotNil(MobileFilePreviewError.tooLarge(10_000_000).errorDescription)
        XCTAssertEqual(MobileFilePreviewError.refused("拒绝").errorDescription, "拒绝")
    }
}
