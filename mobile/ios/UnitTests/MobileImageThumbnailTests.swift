import XCTest
import Foundation
import ImageIO
import CoreGraphics

final class MobileImageThumbnailTests: XCTestCase {
    func testDownsamplesTheLongestEdgeAndKeepsTheAspectRatio() {
        guard let source = Self.png(width: 1_000, height: 500),
              let thumbnail = MobileImageThumbnail.make(from: source) else {
            return XCTFail("expected a readable PNG")
        }
        XCTAssertEqual(thumbnail.width, 360)
        XCTAssertEqual(thumbnail.height, 180)
    }

    func testSmallImagesKeepTheirSize() {
        guard let source = Self.png(width: 120, height: 80),
              let thumbnail = MobileImageThumbnail.make(from: source) else {
            return XCTFail("expected a readable PNG")
        }
        XCTAssertEqual(thumbnail.width, 120)
        XCTAssertEqual(thumbnail.height, 80)
    }

    func testUnreadableBytesAreRejected() {
        XCTAssertNil(MobileImageThumbnail.make(from: Data("not an image".utf8)))
        XCTAssertNil(MobileImageThumbnail.make(from: Data()))
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
