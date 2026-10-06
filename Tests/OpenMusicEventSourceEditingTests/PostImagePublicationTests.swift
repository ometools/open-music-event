import Foundation
#if canImport(ImageIO)
import ImageIO
import OpenMusicEventSourceEditing
import Testing

@Suite struct PostImagePublicationTests {
    @Test func `a publication image cache freezes reviewed bytes across retries`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://example.test/header.png"))
        let first = try await loadPublicationImage(from: url, cacheDirectory: directory) { _ in Data("first download".utf8) }
        let retry = try await loadPublicationImage(from: url, cacheDirectory: directory) { _ in
            Issue.record("A retry should use the reviewed image bytes")
            return Data("changed download".utf8)
        }
        #expect(first == retry)
    }

    @Test func `a small image in another format normalizes to a supported post image`() throws {
        let gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let prepared = try preparePostImage(gif)
        #expect(prepared.starts(with: [255, 216, 255]))
        let source = try #require(CGImageSourceCreateWithData(prepared as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
    }

    @Test func `oversized post artwork fits the embed limit without changing dimensions`() throws {
        let size = 1_024
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        var seed: UInt32 = 123
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            for component in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                pixels[offset + component] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let original = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(original, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(original.length > 2_000_000)
        let compressed = try preparePostImage(original as Data)
        #expect(compressed.count <= 2_000_000)
        let source = try #require(CGImageSourceCreateWithData(compressed as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == size)
        #expect(decoded.height == size)
        #expect(try preparePostImage(compressed) == compressed)
    }
}
#endif
