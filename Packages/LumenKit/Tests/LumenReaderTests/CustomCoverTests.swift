import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LumenReader

struct CustomCoverTests {
    /// PNG заданного размера, залитый одним цветом.
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func size(of data: Data) throws -> (width: Int, height: Int, type: String) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            CGImageSourceGetType(source) as String? ?? ""
        )
    }

    @Test func bigPhotoIsShrunkToJPEG() throws {
        let cover = try #require(SourceMetadata.customCover(from: try png(width: 1600, height: 2400)))
        let result = try size(of: cover)
        #expect(result.height == 1200)
        #expect(result.width == 800)
        #expect(result.type == UTType.jpeg.identifier)
    }

    @Test func notAnImageIsRefused() {
        #expect(SourceMetadata.customCover(from: Data("это текст".utf8)) == nil)
    }
}
