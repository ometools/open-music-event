import AWSLambdaEvents
import ATProto
import CustomDump
import Foundation
import HummingbirdLambda
import HummingbirdLambdaTesting
import HummingbirdTesting
import OpenMusicEventLexicon
import OpenMusicEventOAuthClient
import OpenMusicEventRouting
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

private let wickedWoodsCanonicalEventID = Event.ID(
    "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
)!

@Suite(AppViewTestTime())
struct AppViewRouteTests {
    @Test
    func canonicalEventRoutesServeIndexedRecordsWithPaging() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(database: SQLiteData.defaultDatabase())
        let firstID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let secondID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaq"
        ))
        var firstDraft = try Event(
            id: firstID,
            name: "First Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        firstDraft.cid = ATProto.CID(rawValue: "bafy-first-event")
        let first = firstDraft
        let second = try Event(
            id: secondID,
            name: "Second Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try await store.database.write { db in
            try Event.insert { first }.execute(db)
            try Event.insert { second }.execute(db)
        }
        let app = try OpenMusicEventAppViewServer.application(
            configuration: roots.configuration,
            store: store
        )

        try await app.test(.live) { client in
            try await client.execute(
                uri: "/xrpc/events.openmusic.getEvents?limit=1",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try JSONDecoder().decode(Event.Page.self, from: Data(response.body.readableBytesView))
                expectNoDifference(page.events.map(\.uri), [firstID])
                expectNoDifference(page.events.first?.cid, first.cid)
                expectNoDifference(try page.events.first?.event().name, "First Event")
                expectNoDifference(page.cursor, "1")
            }
            try await client.execute(
                uri: "/xrpc/events.openmusic.getEvents?limit=1&cursor=1",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try JSONDecoder().decode(Event.Page.self, from: Data(response.body.readableBytesView))
                expectNoDifference(page.events.map(\.uri), [secondID])
                expectNoDifference(page.cursor, nil)
            }
            var eventURL = URLComponents()
            eventURL.path = "/xrpc/events.openmusic.getEvent"
            eventURL.queryItems = [URLQueryItem(name: "uri", value: firstID.description)]
            try await client.execute(
                uri: try #require(eventURL.string),
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let indexed = try JSONDecoder().decode(
                    Event.IndexedRecord.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(indexed.uri, firstID)
                expectNoDifference(indexed.cid, first.cid)
                expectNoDifference(try indexed.event(), first)
            }
        }
    }

    @Test
    func unknownCalendarCatalogIsNotServed() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(database: SQLiteData.defaultDatabase())
        let app = try OpenMusicEventAppViewServer.application(
            configuration: roots.configuration,
            store: store
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=example.invalid.event",
                method: .get
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test
    func `readiness waits for the Hydrant replay boundary`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(
            database: SQLiteData.defaultDatabase(),
            initiallyReady: false
        )
        let app = try OpenMusicEventAppViewServer.application(
            configuration: roots.configuration,
            store: store
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/readyz", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                #expect(String(buffer: response.body) == "catching up")
            }

            await store.readiness.markReady(cursor: 42)

            try await client.execute(uri: "/readyz", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "ready")
            }
        }
    }

    @Test
    func `indexed canonical Event changes reach XRPC and the event page`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(database: SQLiteData.defaultDatabase())
        var configuration = roots.configuration
        let app = try OpenMusicEventAppViewServer.application(
            configuration: configuration,
            store: store
        )
        var eventURL = URLComponents()
        eventURL.path = "/xrpc/events.openmusic.getEvent"
        eventURL.queryItems = [
            URLQueryItem(name: "uri", value: wickedWoodsCanonicalEventID.description)
        ]
        let eventRequest = try #require(eventURL.string)

        try await app.test(.router) { client in
            try await client.execute(uri: eventRequest, method: .get) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah", method: .get) { response in
                #expect(response.status == .notFound)
            }

            var first = try Event(
                id: wickedWoodsCanonicalEventID,
                name: "Wicked Woods 2026",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt
            )
            first.description = "A festival in the woods."
            let published = first
            try await store.database.write { db in
                try Event.insert { published }.execute(db)
            }
            try await client.execute(uri: eventRequest, method: .get) { response in
                #expect(response.status == .ok)
                let indexed = try JSONDecoder().decode(
                    Event.IndexedRecord.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(try indexed.event(), published)
            }
            try await client.execute(uri: "/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("<h1>Wicked Woods 2026</h1>"))
            }

            var updated = published
            updated.name = "Wicked Woods 2026 — Updated"
            let revised = updated
            try await store.database.write { db in
                try Event.upsert { revised }.execute(db)
            }
            try await client.execute(uri: eventRequest, method: .get) { response in
                let indexed = try JSONDecoder().decode(
                    Event.IndexedRecord.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(try indexed.event().name, revised.name)
            }
            try await client.execute(uri: "/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah", method: .get) { response in
                #expect(String(buffer: response.body).contains(
                    "<h1>Wicked Woods 2026 — Updated</h1>"
                ))
            }

            try await store.database.write { db in
                try Event.find(wickedWoodsCanonicalEventID).delete().execute(db)
            }
            try await client.execute(uri: eventRequest, method: .get) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }
    @Test
    func `loads the public AppView host from deployment configuration`() throws {
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: ["OME_APPVIEW_PUBLIC_HOST": "stg.openmusicevent.app"]
        )

        expectNoDifference(
            configuration.publicAppViewHost,
            ATProto.PDSHost("stg.openmusicevent.app")
        )
    }

    @Test
    func `treats an empty Geoapify environment value as disabled`() throws {
        #expect(
            try AppViewConfiguration.fromEnvironment(
                environment: ["GEOAPIFY_API_KEY": "   "]
            ).geoapifyAPIKey == nil
        )
        #expect(
            try AppViewConfiguration.fromEnvironment(
                environment: ["GEOAPIFY_API_KEY": "key"]
            ).geoapifyAPIKey == "key"
        )
    }

    @Test
    func `loads local geocoding overrides from deployment configuration`() throws {
        let configuration = try AppViewConfiguration.fromEnvironment(environment: [
            "OME_APPVIEW_GEOCODING_OVERRIDES": #"{"422 East Mendenhall Street":{"latitude":45.6802,"longitude":-111.03126}}"#
        ])

        expectNoDifference(
            configuration.geocodingOverrides["422 East Mendenhall Street"],
            .init(latitude: 45.6802, longitude: -111.03126)
        )
        #expect(throws: AppViewConfigurationError.self) {
            try AppViewConfiguration.fromEnvironment(environment: [
                "OME_APPVIEW_GEOCODING_OVERRIDES": "not-json"
            ])
        }
    }

    @Test
    func `serves a canonical attendee URL from its durable event`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(database: SQLiteData.defaultDatabase())
        var event = try Event(
            id: wickedWoodsCanonicalEventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        event.media = [.known(.image(OME.Image(
            source: .known(.url(URL(string: "https://resources.openmusicevent.app/wickedwoods/2026_ww_hero.png")!)),
            role: .known(.hero)
        )))]
        let publishedEvent = event
        try await store.database.write { db in
            try Event.insert { publishedEvent }.execute(db)
        }
        var configuration = roots.configuration
        let app = try OpenMusicEventAppViewServer.application(
            configuration: configuration,
            store: store
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/html; charset=utf-8")
                let html = String(buffer: response.body)
                #expect(html.contains("<h1>Wicked Woods 2026</h1>"))
                #expect(html.contains(
                    "https://localhost/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3mrdbziccpcah"
                ))
                #expect(html.contains(
                    "https://resources.openmusicevent.app/wickedwoods/2026_ww_hero.png"
                ))
            }
        }
    }

    @Test
    func `rejects unsupported slug routes`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        var configuration = roots.configuration
        let app = try OpenMusicEventAppViewServer.application(configuration: configuration)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/events/2025",
                method: .get
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test
    func `serves the Wicked Woods association file from its exact host`() throws {
        let files = WellKnownFiles(
            rootDirectory: AppViewConfiguration().wellKnownRoot
        )

        for path in [
            "/.well-known/apple-app-site-association",
            "/apple-app-site-association",
        ] {
            let file = try #require(try files.file(
                host: "wickedwoods.openmusicevent.app",
                requestPath: path
            ))
            #expect(file.contentType == "application/json")
            let association = String(decoding: file.data, as: UTF8.self)
            #expect(association.contains("FYZE6539TN.com.Festivl.WickedWoods"))
            #expect(association.contains("FYZE6539TN.com.Festivl.WickedWoods.Clip"))
            #expect(association.contains("\"/\": \"/events/2026\""))
        }
    }

    @Test
    func `returns standard XRPC errors for invalid catalog parameters`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(database: SQLiteData.defaultDatabase())

        let app = try OpenMusicEventAppViewServer.application(
            configuration: roots.configuration,
            store: store
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/events.openmusic.getEvents?limit=0",
                method: .get
            ) { response in
                #expect(response.status == .badRequest)
                expectNoDifference(
                    try decodeXRPCError(response.body),
                    XRPC.ErrorResponse(
                        error: "InvalidCursor",
                        message: "The XRPC cursor or limit is invalid."
                    )
                )
            }

            try await client.execute(
                uri: "/xrpc/events.openmusic.getEvents?cursor=not-a-cursor",
                method: .get
            ) { response in
                #expect(response.status == .badRequest)
                expectNoDifference(
                    try decodeXRPCError(response.body),
                    XRPC.ErrorResponse(
                        error: "InvalidRequest",
                        message: "Invalid XRPC query parameters."
                    )
                )
            }
        }
    }

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

            try await client.execute(uri: "/favicon.png", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "image/png")
                #expect(response.body.readableBytes == 4)
            }

            try await client.execute(uri: "/apple-touch-icon.png", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "image/png")
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
                #expect(String(buffer: response.body).contains(#""client_id":"https://openmusicevent.app/.well-known/oauth-client-metadata.json""#))
            }
        }
    }

    @Test
    func privateAppViewServesTheSharedNativeClient() async throws {
        #expect(try AppViewConfiguration.fromEnvironment(environment: [
            "OME_OAUTH_CLIENT": "private-authentication"
        ]).oauthClient == .privateAuthentication)
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        var configuration = roots.configuration
        configuration.oauthClient = .privateAuthentication
        let application = try OpenMusicEventAppViewServer.application(configuration: configuration)
        try await application.test(.ahc()) { client in
            try await client.execute(uri: "/oauth-client-metadata.json", method: .get,
                                     headers: [.init("Host")!: "metadata.ome-auth.test"]) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json")
                let metadata = try #require(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                #expect(metadata["client_id"] as? String == "https://metadata.ome-auth.test/oauth-client-metadata.json")
                #expect(metadata["client_uri"] as? String == "https://metadata.ome-auth.test/")
                #expect(metadata["redirect_uris"] as? [String] == ["test.ome-auth.metadata:/oauth/callback"])
                #expect(metadata["scope"] as? String == OpenMusicEventOAuthClient.privateScope)
                #expect(metadata["application_type"] as? String == "native")
                #expect(metadata["dpop_bound_access_tokens"] as? Bool == true)
                #expect(!String(buffer: response.body).contains("openmusicevent.app"))
            }
            try await client.execute(uri: "/", method: .get,
                                     headers: [.init("Host")!: "metadata.ome-auth.test"]) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/oauth-client-metadata.json", method: .get,
                                     headers: [.init("Host")!: "openmusicevent.app"]) { response in
                #expect(response.status == .notFound)
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
                #expect(response.body?.contains(#""client_id":"https://openmusicevent.app/.well-known/oauth-client-metadata.json""#) == true)
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

private func decodeXRPCError(_ body: ByteBuffer) throws -> XRPC.ErrorResponse {
    try JSONDecoder().decode(XRPC.ErrorResponse.self, from: Data(body.readableBytesView))
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
        try Data([0x89, 0x50, 0x4e, 0x47])
            .write(to: siteRoot.appendingPathComponent("favicon.png", isDirectory: false))
        try Data([0x89, 0x50, 0x4e, 0x47])
            .write(to: siteRoot.appendingPathComponent("apple-touch-icon.png", isDirectory: false))
        try Data(#"{"client_id":"old.example","scope":"atproto"}"#.utf8)
            .write(to: siteRoot.appendingPathComponent(".well-known/oauth-client-metadata.json", isDirectory: false))
        try Data("did:plc:localtest".utf8)
            .write(to: wellKnownRoot.appendingPathComponent("localhost/atproto-did", isDirectory: false))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
