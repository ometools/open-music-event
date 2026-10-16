import Foundation
import Hummingbird

public struct WellKnownFiles: Sendable {
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var rootDirectory: URL

    public func file(host: String, requestPath: String) throws -> WellKnownFile? {
        guard let name = Self.fileName(for: requestPath) else { return nil }
        let normalizedHost = host.lowercased()
        guard Self.isAllowedHost(normalizedHost) else { return nil }

        let url = rootDirectory
            .appendingPathComponent(normalizedHost, isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return WellKnownFile(name: name, data: data)
    }

    public static func fileName(for requestPath: String) -> String? {
        switch requestPath {
        case "/.well-known/atproto-did":
            "atproto-did"
        case "/.well-known/apple-app-site-association", "/apple-app-site-association":
            "apple-app-site-association"
        case "/.well-known/assetlinks.json":
            "assetlinks.json"
        case "/.well-known/did.json":
            "did.json"
        default:
            nil
        }
    }

    public static func isAllowedHost(_ host: String) -> Bool {
        host.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || character == "." || character == "-")
        }
    }
}

public struct WellKnownFile: Sendable, Equatable {
    public var name: String
    public var data: Data

    public var contentType: String {
        switch name {
        case "atproto-did":
            "text/plain; charset=utf-8"
        default:
            "application/json"
        }
    }

    public var response: Response {
        Response(
            status: .ok,
            headers: [.contentType: contentType],
            body: .init(byteBuffer: .init(data: data))
        )
    }
}
