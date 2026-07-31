#if canImport(ImageIO) && !os(Android)
import CoreGraphics
import CustomDump
import Foundation
import ImageIO
import Testing

@testable import OpenMusicEventComponents

struct CachedRemoteImageTests {
    @Test
    func `large artwork decodes directly at thumbnail size`() throws {
        let encodedImage = try encodedJPEG(width: 2_400, height: 1_200)

        // A three-times-scale 60-point contributor row requests a 180-pixel thumbnail.
        let image = try decodeCachedRemoteCGImage(
            encodedImage,
            targetPixelSize: CGSize(width: 180, height: 180)
        )

        expectNoDifference(image.width, 180)
        expectNoDifference(image.height, 90)
    }

    func encodedJPEG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let sourceImage = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                "public.jpeg" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, sourceImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
#endif
