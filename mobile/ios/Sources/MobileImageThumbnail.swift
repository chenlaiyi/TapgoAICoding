import Foundation
import ImageIO

/// Downsamples durable image bytes into transcript thumbnails.
enum MobileImageThumbnail {
    /// Largest edge kept for one transcript thumbnail.
    static let maxDimension = 360

    /// Reads the first frame and scales it down with its EXIF orientation applied.
    /// - Parameters:
    ///   - data: encoded image bytes returned by the Host.
    ///   - maxDimension: largest edge of the returned image in pixels.
    /// - Returns: the downsampled image, or nil when the bytes are not a readable raster image.
    static func make(from data: Data, maxDimension: Int = MobileImageThumbnail.maxDimension) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxDimension),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
