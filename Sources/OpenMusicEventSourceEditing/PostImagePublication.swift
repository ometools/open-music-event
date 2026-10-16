import Foundation
import Crypto
#if canImport(ImageIO)
import ImageIO
#endif

/// app.bsky.embed.images permits at most 2 MB per image.
public func preparePostImage(_ bytes: Data) throws -> Data {
    let supported = bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) || bytes.starts(with: [255, 216, 255])
    if supported && bytes.count <= 2_000_000 { return bytes }
    #if canImport(ImageIO)
    guard bytes.count <= 50_000_000,
          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw PostImagePublicationError.invalidImage
    }
    for quality in [0.95, 0.9, 0.8, 0.7, 0.5] {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw PostImagePublicationError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        if CGImageDestinationFinalize(destination), output.length <= 2_000_000 {
            return output as Data
        }
    }
    #endif
    throw PostImagePublicationError.tooLarge
}

public enum PostImagePublicationError: Error, LocalizedError {
    case invalidImage
    case tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "The source post image cannot be decoded."
        case .tooLarge: "The post image cannot fit the 2 MB embed limit at its original dimensions."
        }
    }
}

/// A reviewed publication may reuse the same downloaded image bytes on retry.
public func loadPublicationImage(
    from url: URL,
    cacheDirectory: URL?,
    download: @Sendable (URL) async throws -> Data
) async throws -> Data {
    guard let cacheDirectory else { return try await download(url) }
    let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let path = cacheDirectory.appendingPathComponent(key + ".json")
    if FileManager.default.fileExists(atPath: path.path) {
        let cached = try JSONDecoder().decode(CachedPublicationImage.self, from: Data(contentsOf: path))
        guard cached.url == url else { throw PostImagePublicationError.invalidImage }
        return cached.bytes
    }
    let bytes = try await download(url)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try JSONEncoder().encode(CachedPublicationImage(url: url, bytes: bytes)).write(to: path, options: .atomic)
    return bytes
}

private struct CachedPublicationImage: Codable {
    var url: URL
    var bytes: Data
}
