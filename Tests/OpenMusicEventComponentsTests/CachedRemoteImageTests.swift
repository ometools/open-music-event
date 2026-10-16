import CustomDump
import Foundation
#if canImport(ImageIO) && !os(Android)
import CoreGraphics
import ImageIO
#endif
import Testing

@testable import OpenMusicEventComponents

struct CachedRemoteImageTests {
    @Test
    func `contributor artwork decodes for Android display density`() throws {
        let targetPixelSize = try #require(
            cachedRemotePixelSize(
                targetSize: imageSize(width: 60, height: 60),
                displayScale: 2.625
            )
        )

        expectNoDifference(targetPixelSize, imageSize(width: 157.5, height: 157.5))
        expectNoDifference(
            cachedRemoteThumbnailSize(
                intrinsicSize: imageSize(width: 1_200, height: 1_200),
                targetPixelSize: targetPixelSize
            ),
            imageSize(width: 158, height: 158)
        )
    }

    @Test
    func `thumbnail size preserves a landscape aspect ratio`() throws {
        let size = try #require(
            cachedRemoteThumbnailSize(
                intrinsicSize: imageSize(width: 2_400, height: 1_200),
                targetPixelSize: imageSize(width: 180, height: 180)
            )
        )

        expectNoDifference(size, imageSize(width: 180, height: 90))
    }

    @Test
    func `thumbnail size preserves a portrait aspect ratio`() throws {
        let size = try #require(
            cachedRemoteThumbnailSize(
                intrinsicSize: imageSize(width: 1_200, height: 2_400),
                targetPixelSize: imageSize(width: 180, height: 180)
            )
        )

        expectNoDifference(size, imageSize(width: 90, height: 180))
    }

    @Test
    func `thumbnail size does not upscale small artwork`() throws {
        let size = try #require(
            cachedRemoteThumbnailSize(
                intrinsicSize: imageSize(width: 60, height: 30),
                targetPixelSize: imageSize(width: 180, height: 180)
            )
        )

        expectNoDifference(size, imageSize(width: 60, height: 30))
    }

    @Test
    func `thumbnail size rejects invalid dimensions`() {
        #expect(
            cachedRemoteThumbnailSize(
                intrinsicSize: imageSize(width: 2_400, height: 1_200),
                targetPixelSize: imageSize(width: 0, height: 180)
            ) == nil
        )
    }

    #if canImport(ImageIO) && !os(Android)
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
    #endif

    func imageSize(width: Double, height: Double) -> CachedRemoteImageSize {
        CachedRemoteImageSize(width: width, height: height)
    }
}
