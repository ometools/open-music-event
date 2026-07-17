import Foundation
import Hummingbird

public struct StaticSiteFiles: Sendable {
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var rootDirectory: URL

    public func file(requestPath: String) throws -> StaticSiteFile? {
        guard let relativePath = Self.relativePath(for: requestPath) else { return nil }
        let url = rootDirectory.appendingPathComponent(relativePath, isDirectory: false)

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return StaticSiteFile(path: relativePath, data: data)
    }

    public static func relativePath(for requestPath: String) -> String? {
        switch requestPath {
        case "/", "/index.html":
            return "index.html"
        case "/.well-known/oauth-client-metadata.json":
            return ".well-known/oauth-client-metadata.json"
        case "/favicon.png":
            return "favicon.png"
        case "/apple-touch-icon.png":
            return "apple-touch-icon.png"
        case "/styles.css":
            return "styles.css"
        default:
            guard requestPath.hasPrefix("/assets/") else { return nil }
            let file = String(requestPath.dropFirst("/assets/".count))
            guard isSafeAssetFileName(file) else { return nil }
            return "assets/\(file)"
        }
    }

    private static func isSafeAssetFileName(_ value: String) -> Bool {
        !value.isEmpty
            && value.allSatisfy { character in
                character.isASCII
                    && (
                        character.isLetter
                            || character.isNumber
                            || character == "."
                            || character == "-"
                            || character == "_"
                    )
            }
    }
}

public struct StaticSiteFile: Sendable, Equatable {
    public var path: String
    public var data: Data

    public var contentType: String {
        switch path.split(separator: ".").last {
        case "css":
            "text/css; charset=utf-8"
        case "html":
            "text/html; charset=utf-8"
        case "json":
            "application/json"
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "svg":
            "image/svg+xml"
        default:
            "application/octet-stream"
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
