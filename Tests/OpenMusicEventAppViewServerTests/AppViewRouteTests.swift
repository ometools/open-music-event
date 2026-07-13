import AWSLambdaEvents
import Foundation
import HummingbirdLambda
import HummingbirdLambdaTesting
import HummingbirdTesting
import OpenMusicEventAppViewServer
import Testing

struct AppViewRouteTests {
    @Test
    func servesSharedRoutesThroughLocalHummingbirdApp() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }

        let app = try OpenMusicEventAppViewServer.application(configuration: roots.configuration)

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/html; charset=utf-8")
                #expect(String(buffer: response.body).contains("Open Music Event"))
            }

            try await client.execute(uri: "/", method: .head) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/html; charset=utf-8")
            }

            try await client.execute(uri: "/assets/ome-mark.jpg", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "image/jpeg")
                #expect(response.body.readableBytes == 4)
            }

            try await client.execute(uri: "/healthz", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "ok")
            }

            try await client.execute(uri: "/.well-known/atproto-did", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/plain; charset=utf-8")
                #expect(String(buffer: response.body) == "did:plc:localtest")
            }

            try await client.execute(uri: "/.well-known/oauth-client-metadata.json", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json")
                #expect(String(buffer: response.body).contains(#""client_id":"openmusicevent.app""#))
            }
        }
    }

    @Test
    func servesSharedRoutesThroughAPIGatewayV2Lambda() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }

        let router = OpenMusicEventAppViewServer.router(
            context: BasicLambdaRequestContext<APIGatewayV2Request>.self,
            configuration: roots.configuration
        )
        let lambda = APIGatewayV2LambdaFunction(router: router)

        try await lambda.test { client in
            try await client.execute(uri: "/.well-known/oauth-client-metadata.json", method: .get) { response in
                #expect(response.statusCode == .ok)
                #expect(response.headers?["Content-Type"] == "application/json")
                #expect(response.isBase64Encoded == nil)
                #expect(response.body?.contains(#""client_id":"openmusicevent.app""#) == true)
            }

            try await client.execute(uri: "/assets/ome-mark.jpg", method: .get) { response in
                #expect(response.statusCode == .ok)
                #expect(response.headers?["Content-Type"] == "image/jpeg")
                #expect(response.isBase64Encoded == true)
                #expect(response.body == "/9j/AA==")
            }
        }
    }
}

private struct TestAppViewRoots {
    let root: URL
    let siteRoot: URL
    let wellKnownRoot: URL

    var configuration: AppViewConfiguration {
        AppViewConfiguration(
            host: "127.0.0.1",
            port: 0,
            siteRoot: siteRoot,
            wellKnownRoot: wellKnownRoot
        )
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-music-event-appview-tests-\(UUID().uuidString)", isDirectory: true)
        siteRoot = root.appendingPathComponent("Site", isDirectory: true)
        wellKnownRoot = root.appendingPathComponent("WellKnown", isDirectory: true)

        try FileManager.default.createDirectory(
            at: siteRoot.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: siteRoot.appendingPathComponent(".well-known", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: wellKnownRoot.appendingPathComponent("localhost", isDirectory: true),
            withIntermediateDirectories: true
        )

        try Data("<html><body>Open Music Event</body></html>".utf8)
            .write(to: siteRoot.appendingPathComponent("index.html", isDirectory: false))
        try Data("body {}".utf8)
            .write(to: siteRoot.appendingPathComponent("styles.css", isDirectory: false))
        try Data([0xff, 0xd8, 0xff, 0x00])
            .write(to: siteRoot.appendingPathComponent("assets/ome-mark.jpg", isDirectory: false))
        try Data(#"{"client_id":"openmusicevent.app"}"#.utf8)
            .write(to: siteRoot.appendingPathComponent(".well-known/oauth-client-metadata.json", isDirectory: false))
        try Data("did:plc:localtest".utf8)
            .write(to: wellKnownRoot.appendingPathComponent("localhost/atproto-did", isDirectory: false))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
