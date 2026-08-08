import AWSLambdaEvents
import ATProto
import ComposableCalendarEvents
import CustomDump
import Foundation
import HummingbirdLambda
import HummingbirdLambdaTesting
import HummingbirdTesting
import HydrantClient
import IssueReporting
import OpenMusicEventAppViewServer
import OpenMusicEventLexicon
import ServiceLifecycle
import SQLiteData
import Testing
import XRPCClient

struct AppViewRouteTests {
    @Test
    func `reports and skips poisoned community records without stopping ingestion`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(
            database: SQLiteData.defaultDatabase(),
            initiallyReady: false
        )
        let client = HydrantClient(runMessages: { configuration, receive in
            expectNoDifference(configuration.cursor, 0)
            expectNoDifference(configuration.readiness, true)

            // The first record is missing the required createdAt field from the Lexicon JSON.
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventUndecodable)
            )

            // The next record decodes, but its startsAt timestamp cannot be hydrated.
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventPoisoned)
            )

            // Ingestion reports both records and continues through the next valid record.
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventTwo)
            )
            try await receive(
                HydrantClient.decodeMessage(#"{"type":"caughtUp","cursor":42}"#)
            )
            try await gracefulShutdown()
        })
        var configuration = roots.configuration
        configuration.ingestion = AppViewIngestionConfiguration(
            endpoint: "ws://hydrant.test/stream"
        )
        let app = try OpenMusicEventAppViewServer.application(
            configuration: configuration,
            store: store,
            hydrantClient: client
        )
        let reporter = AppViewIssueRecordingReporter()

        try await withIssueReporters([reporter]) {
            try await app.test(.live) { client in
                for _ in 0..<100 {
                    let isReady = try await client.execute(
                        uri: "/readyz",
                        method: .get
                    ) { response in
                        response.status == .ok
                    }
                    if isReady { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let readiness = await store.readiness.snapshot()
                expectNoDifference(readiness, .ready(cursor: 42))

                try await client.execute(
                    uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=community.lexicon.calendar.event",
                    method: .get
                ) { response in
                    #expect(response.status == .ok)
                    let page = try decodeCalendarEventPage(response.body)
                    expectNoDifference(page.events.map(\.name), ["Second Community Event"])
                    expectNoDifference(page.cursor, nil)
                }
            }
        }

        expectNoDifference(reporter.messages.count, 2)
        #expect(
            reporter.messages.contains {
                $0.contains("2nd-monday-thing-ph-ik5")
                    && $0.contains("createdAt")
            }
        )
        #expect(reporter.messages.contains { $0.contains("invalidTimestamp") })
    }

    @Test
    func `ingests community records before serving their hydrated XRPC catalog`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let store = try OpenMusicEventAppViewStore(
            database: SQLiteData.defaultDatabase(),
            initiallyReady: false
        )
        let client = HydrantClient(runMessages: { configuration, receive in
            expectNoDifference(configuration.cursor, 0)
            expectNoDifference(configuration.readiness, true)
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventOne)
            )
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventTwo)
            )
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventDeleted)
            )
            try await receive(
                HydrantClient.decodeMessage(Self.communityCalendarEventDeletion)
            )
            try await receive(
                HydrantClient.decodeMessage(#"{"type":"caughtUp","cursor":44}"#)
            )
            try await gracefulShutdown()
        })
        var configuration = roots.configuration
        configuration.ingestion = AppViewIngestionConfiguration(
            endpoint: "ws://hydrant.test/stream"
        )
        let app = try OpenMusicEventAppViewServer.application(
            configuration: configuration,
            store: store,
            hydrantClient: client
        )

        try await app.test(.live) { client in
            for _ in 0..<100 {
                let isReady = try await client.execute(
                    uri: "/readyz",
                    method: .get
                ) { response in
                    response.status == .ok
                }
                if isReady { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let readiness = await store.readiness.snapshot()
            expectNoDifference(readiness, .ready(cursor: 44))

            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=community.lexicon.calendar.event&limit=1",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decodeCalendarEventPage(response.body)
                expectNoDifference(page.cursor, "1")
                let event = try #require(page.events.first)
                expectNoDifference(event.name, "First Community Event")
                expectNoDifference(event.cid, ATProto.CID("bafy-first"))
                expectNoDifference(
                    event.uri,
                    try #require(ATProto.URI(
                        "at://did:plc:festival/community.lexicon.calendar.event/first"
                    ))
                )
                expectNoDifference(event.source.collection, Community.CalendarEvent.nsid)
                expectNoDifference(event.source.appViewHost, "openmusicevent.app")
                expectNoDifference(event.organizer.id, DID("did:plc:festival")!)
                expectNoDifference(event.locations.first?.name, "The Hall")
                expectNoDifference(event.locations.first?.street, "1 Main St")
                expectNoDifference(event.locations.first?.locality, "Denver")
                expectNoDifference(event.locations.first?.region, "CO")
                expectNoDifference(event.locations.first?.postalCode, "80202")
                expectNoDifference(event.locations.first?.country, "US")
                expectNoDifference(event.links.map(\.uri.absoluteString), ["https://example.com/first"])
                expectNoDifference(event.timeZoneIdentifier, nil)
                expectNoDifference(event.event, nil)
            }

            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=community.lexicon.calendar.event&cursor=1&limit=1",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try decodeCalendarEventPage(response.body)
                expectNoDifference(page.events.map(\.name), ["Second Community Event"])
                expectNoDifference(page.cursor, nil)
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
    func `serves the bundled OME catalog through its shared XRPC definition`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }

        let app = try OpenMusicEventAppViewServer.application(configuration: roots.configuration)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=app.openmusicevent.event",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")

                let page = try decodeCalendarEventPage(response.body)
                expectNoDifference(page.events.count, 20)
                expectNoDifference(page.cursor, nil)

                let wickedWoods = try #require(page.events.first)
                expectNoDifference(wickedWoods.name, "Wicked Woods 2026")
                expectNoDifference(wickedWoods.source.collection, OME.Event.nsid)
                expectNoDifference(wickedWoods.source.appViewHost, "openmusicevent.app")
                expectNoDifference(
                    wickedWoods.source.sourceRecord,
                    OME.SourceRecord(
                        kind: .tangled,
                        reference: "https://tangled.org/wickedwoods.ca/ome-workspace",
                        ref: "main"
                    )
                )
                #expect(wickedWoods.event != nil)
            }
        }
    }

    @Test
    func `pages through the bundled OME catalog with XRPC cursor and limit`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }

        let app = try OpenMusicEventAppViewServer.application(configuration: roots.configuration)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=app.openmusicevent.event&limit=2",
                method: .get
            ) { response in
                #expect(response.status == .ok)

                let page = try decodeCalendarEventPage(response.body)
                expectNoDifference(page.events.map(\.name), ["Wicked Woods 2026", "Wicked Woods 2025"])
                expectNoDifference(page.cursor, "2")
            }

            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=app.openmusicevent.event&cursor=2&limit=2",
                method: .get
            ) { response in
                #expect(response.status == .ok)

                let page = try decodeCalendarEventPage(response.body)
                expectNoDifference(page.events.map(\.name), ["Wicked Woods 2024", "Wicked Woods 2023"])
                expectNoDifference(page.cursor, "4")
            }
        }
    }

    @Test
    func `returns standard XRPC errors for invalid catalog parameters`() async throws {
        let roots = try TestAppViewRoots()
        defer { roots.remove() }

        let app = try OpenMusicEventAppViewServer.application(configuration: roots.configuration)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=app.openmusicevent.event&limit=0",
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

            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=app.openmusicevent.event&cursor=not-a-cursor",
                method: .get
            ) { response in
                #expect(response.status == .badRequest)
                expectNoDifference(
                    try decodeXRPCError(response.body),
                    XRPC.ErrorResponse(
                        error: "InvalidCursor",
                        message: "The XRPC cursor is invalid."
                    )
                )
            }

            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=community.lexicon.calendar.event",
                method: .get
            ) { response in
                #expect(response.status == .notFound)
                expectNoDifference(
                    try decodeXRPCError(response.body),
                    XRPC.ErrorResponse(
                        error: "UnknownCatalog",
                        message: "The requested calendar event catalog is not available."
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

    private static let communityCalendarEventOne = #"""
    {
      "id": 41,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:festival",
        "rev": "3abc",
        "collection": "community.lexicon.calendar.event",
        "rkey": "first",
        "action": "create",
        "record": {
          "$type": "community.lexicon.calendar.event",
          "createdAt": "2026-08-01T12:00:00Z",
          "name": "First Community Event",
          "description": "Hydrated from the shared community record.",
          "startsAt": "2026-08-08T18:00:00Z",
          "endsAt": "2026-08-08T22:00:00Z",
          "status": "community.lexicon.calendar.event#scheduled",
          "mode": "community.lexicon.calendar.event#inperson",
          "locations": [
            {
              "$type": "community.lexicon.location.address",
              "name": "The Hall",
              "street": "1 Main St",
              "locality": "Denver",
              "region": "CO",
              "postalCode": "80202",
              "country": "US"
            }
          ],
          "uris": [
            { "uri": "https://example.com/first", "name": "Event page" }
          ]
        },
        "cid": "bafy-first"
      }
    }
    """#

    private static let communityCalendarEventPoisoned = #"""
    {
      "id": 41,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:poisoned",
        "rev": "3abc",
        "collection": "community.lexicon.calendar.event",
        "rkey": "poisoned",
        "action": "create",
        "record": {
          "$type": "community.lexicon.calendar.event",
          "createdAt": "2026-08-01T12:00:00Z",
          "name": "Poisoned Community Event",
          "startsAt": "not-a-timestamp"
        },
        "cid": "bafy-poisoned"
      }
    }
    """#

    private static let communityCalendarEventUndecodable = #"""
    {
      "id": 40,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:piobscs63j5o53wzbgqidgj6",
        "rev": "3mrbaouudwj2t",
        "collection": "community.lexicon.calendar.event",
        "rkey": "2nd-monday-thing-ph-ik5",
        "action": "create",
        "record": {
          "$type": "community.lexicon.calendar.event",
          "description": "a thing going on once a nonth",
          "locations": [],
          "mode": "community.lexicon.calendar.event#inperson",
          "name": "2nd monday thing",
          "startsAt": "2025-05-12T21:00:00.000Z",
          "status": "community.lexicon.calendar.event#scheduled",
          "uris": [
            {
              "name": "OpenMeet Event",
              "uri": "https://platform.openmeet.net/events/2nd-monday-thing-ph-ik5"
            }
          ]
        },
        "cid": "bafyreifiymllu4ykepilnm6j24fstwvp72rlbiojjkpmourcjyxykm7mzu"
      }
    }
    """#

    private static let communityCalendarEventTwo = #"""
    {
      "id": 42,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:second",
        "rev": "3abd",
        "collection": "community.lexicon.calendar.event",
        "rkey": "second",
        "action": "create",
        "record": {
          "$type": "community.lexicon.calendar.event",
          "createdAt": "2026-08-02T12:00:00Z",
          "name": "Second Community Event",
          "startsAt": "2026-08-09T18:00:00Z"
        },
        "cid": "bafy-second"
      }
    }
    """#

    private static let communityCalendarEventDeleted = #"""
    {
      "id": 43,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:deleted",
        "rev": "3abe",
        "collection": "community.lexicon.calendar.event",
        "rkey": "deleted",
        "action": "create",
        "record": {
          "$type": "community.lexicon.calendar.event",
          "createdAt": "2026-08-03T12:00:00Z",
          "name": "Deleted Community Event",
          "startsAt": "2026-08-10T18:00:00Z"
        },
        "cid": "bafy-deleted"
      }
    }
    """#

    private static let communityCalendarEventDeletion = #"""
    {
      "id": 44,
      "type": "record",
      "record": {
        "live": false,
        "did": "did:plc:deleted",
        "rev": "3abf",
        "collection": "community.lexicon.calendar.event",
        "rkey": "deleted",
        "action": "delete"
      }
    }
    """#
}

private final class AppViewIssueRecordingReporter: @unchecked Sendable, IssueReporter {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(message() ?? "")
        }
    }

    func reportIssue(
        _ error: any Error,
        _ message: @autoclosure () -> String?,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(
                "Caught error: \(error)"
                    + (message().map { ": \($0)" } ?? "")
            )
        }
    }
}

private func decodeCalendarEventPage(_ body: ByteBuffer) throws -> OME.CalendarEvent.Page {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(OME.CalendarEvent.Page.self, from: Data(body.readableBytesView))
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
        try Data(#"{"client_id":"openmusicevent.app"}"#.utf8)
            .write(to: siteRoot.appendingPathComponent(".well-known/oauth-client-metadata.json", isDirectory: false))
        try Data("did:plc:localtest".utf8)
            .write(to: wellKnownRoot.appendingPathComponent("localhost/atproto-did", isDirectory: false))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
