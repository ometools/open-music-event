import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ContributorTests {
    typealias Contributor = OpenMusicEventLexicon.Contributor

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let contributorURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.contributor/3mrdbziccpcai")!
    let subject = DID("did:plc:artist")!
    let sourceURI = ATProto.URI("at://did:plc:artist/app.bsky.actor.profile/self")!
    let sourceCID: ATProto.CID = "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
    let createdAt: ATProto.DateTime = "2026-09-22T18:00:00Z"

    @Test
    func `an organizer snapshot renders independently while preserving pinned profile provenance`() throws {
        let contributor = try Contributor(
            id: contributorURI,
            cid: "observed-contributor-revision",
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(uri: sourceURI, cid: sourceCID),
            description: "Live at Wicked Woods",
            roles: [.known(.performer), .unknown("visualArtist")],
            links: [.init(url: #require(URL(string: "https://artist.example")), title: "Website")],
            media: [.known(.image(.init(source: .known(.url(#require(URL(string: "https://artist.example/portrait.jpg")))))))]
        )

        try contributor.validateReferences()
        let payload = try contributor.encodeLexicon()
        expectNoDifference(payload, .object([
            "$type": "events.openmusic.contributor",
            "event": .string(eventURI.description),
            "name": "The Artist",
            "createdAt": .string(createdAt.rawValue),
            "subject": .string(subject.description),
            "source": .object([
                "uri": .string(sourceURI.description),
                "cid": .string(sourceCID.description),
            ]),
            "description": "Live at Wicked Woods",
            "roles": .array(["performer", "visualArtist"]),
            "links": .array([.object([
                "url": "https://artist.example",
                "title": "Website",
            ])]),
            "media": .array([.object([
                "$type": "events.openmusic.defs#image",
                "source": .object([
                    "$type": "events.openmusic.defs#imageURL",
                    "url": "https://artist.example/portrait.jpg",
                ]),
                "renderingMode": "original",
            ])]),
        ]))
        expectNoDifference(
            try Contributor.decodeLexicon(payload, metadata: .init(uri: contributorURI, cid: "observed-contributor-revision")),
            contributor
        )
    }

    @Test(arguments: ["subject", "source", "description", "roles", "links", "media"])
    func `profile additions remain optional and explicit null encodes as absence`(_ field: String) throws {
        let contributor = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "Independent name",
            createdAt: createdAt
        )
        var payload = try #require(contributor.encodeLexicon().object)
        payload[field] = .null
        let decoded = try Contributor.decodeLexicon(.object(payload), metadata: .init(uri: contributorURI))
        expectNoDifference(decoded, contributor)
        expectNoDifference(try decoded.encodeLexicon(), try contributor.encodeLexicon())
    }

    @Test(arguments: ["event", "name", "createdAt"])
    func `the independently renderable profile fields are required`(_ field: String) throws {
        var payload = try #require(Contributor(
            id: contributorURI,
            event: eventURI,
            name: "Contributor",
            createdAt: createdAt
        ).encodeLexicon().object)
        payload.removeValue(forKey: field)
        #expect(throws: (any Error).self) {
            try Contributor.decodeLexicon(.object(payload), metadata: .init(uri: contributorURI))
        }
    }

    @Test
    func `a subject assertion needs no source and provenance may use any DID authored record`() throws {
        let subjectOnly = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject
        )
        try subjectOnly.validateReferences()

        let customSource = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(
                uri: #require(ATProto.URI("at://did:plc:artist/social.example.profile/2026")),
                cid: sourceCID
            )
        )
        try customSource.validateReferences()
    }

    @Test
    func `decoding preserves an organizer assertion while verified ingestion enforces provenance`() throws {
        var payload = try #require(Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(uri: sourceURI, cid: sourceCID)
        ).encodeLexicon().object)
        payload.removeValue(forKey: "subject")

        let decoded = try Contributor.decodeLexicon(.object(payload), metadata: .init(uri: contributorURI))
        #expect(decoded.subject == nil)
        #expect(decoded.source?.uri == sourceURI)
        #expect(throws: ValidationError.self) { try decoded.validateReferences() }

        let mismatched = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(
                uri: #require(ATProto.URI("at://did:plc:someoneelse/app.bsky.actor.profile/self")),
                cid: sourceCID
            )
        )
        #expect(throws: ValidationError.self) { try mismatched.validateReferences() }

        let handleAuthored = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(
                uri: #require(ATProto.URI("at://artist.example/app.bsky.actor.profile/self")),
                cid: sourceCID
            )
        )
        #expect(throws: ValidationError.self) { try handleAuthored.validateReferences() }

        let incomplete = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "The Artist",
            createdAt: createdAt,
            subject: subject,
            source: .init(
                uri: #require(ATProto.URI("at://did:plc:artist/app.bsky.actor.profile")),
                cid: sourceCID
            )
        )
        #expect(throws: ValidationError.self) { try incomplete.validateReferences() }
    }

    @Test
    func `publication validation enforces event ownership names roles and media`() throws {
        let foreign = try Contributor(
            id: #require(ATProto.URI("at://did:plc:another/events.openmusic.contributor/3mrdbziccpcai")),
            event: eventURI,
            name: "Contributor",
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try foreign.validateReferences() }

        var contributor = try Contributor(
            id: contributorURI,
            event: eventURI,
            name: "   \n",
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try contributor.validateReferences() }

        contributor.name = "Contributor"
        contributor.roles = [.known(.staff), .unknown("staff")]
        #expect(throws: ValidationError.self) { try contributor.validateReferences() }

        contributor.roles = [.unknown(" \n")]
        #expect(throws: ValidationError.self) { try contributor.validateReferences() }

        contributor.roles = nil
        contributor.media = [.known(.image(.init(source: .known(.url(URL(fileURLWithPath: "/tmp/private.jpg"))))))]
        #expect(throws: ValidationError.self) { try contributor.validateReferences() }
    }

    @Test
    func `ordered open roles and the full snapshot round trip through SQLite`() throws {
        let contributor = try Contributor(
            id: contributorURI,
            cid: "cached-revision",
            event: eventURI,
            name: "Community Crew",
            createdAt: createdAt,
            subject: subject,
            source: .init(uri: sourceURI, cid: sourceCID),
            description: "A collective",
            roles: [.known(.organizer), .unknown("lightingDesigner"), .known(.volunteer)],
            links: [.init(url: #require(URL(string: "https://crew.example")))],
            media: [.unknown(.object(["$type": "media.example.video", "url": "https://crew.example/reel"]))]
        )

        let database = try DatabaseQueue()
        try database.write { db in
            try #sql("""
                CREATE TABLE \(quote: Contributor.tableName) (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
                  "name" TEXT NOT NULL, "createdAt" TEXT NOT NULL, "subject" TEXT,
                  "source" TEXT, "description" TEXT, "roles" TEXT, "links" TEXT, "media" TEXT
                ) STRICT
                """).execute(db)
            try Contributor.insert { contributor }.execute(db)
        }
        let stored = try database.read { db in
            try #require(try Contributor.find(contributorURI).fetchOne(db))
        }
        expectNoDifference(stored, contributor)
        expectNoDifference(try stored.encodeLexicon(), try contributor.encodeLexicon())
        expectNoDifference(try stored.encodeLexicon().object?["roles"], .array([
            "organizer", "lightingDesigner", "volunteer",
        ]))
    }

    @Test
    func `long source biographies are preserved within the five thousand character limit`() throws {
        let biography = String(repeating: "é", count: 5_000)
        var contributor = try Contributor(id: contributorURI, event: eventURI, name: "Artist",
            createdAt: createdAt, description: biography)
        let payload = try contributor.encodeLexicon()
        let decoded = try Contributor.decodeLexicon(payload, metadata: .init(uri: contributorURI))
        expectNoDifference(decoded.description, biography)
        contributor.description = biography + "x"
        #expect(throws: (any Error).self) { try contributor.encodeLexicon() }
    }

    @Test
    func `the exporter exposes the complete contributor contract and no confirmation claim`() throws {
        let documents = try LexiconExporter.documents(for: [Contributor.self])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "events.openmusic.contributor", "events.openmusic.defs", "com.atproto.repo.strongRef",
        ])
        let document = try #require(documents.first { $0.id.rawValue == "events.openmusic.contributor" })
        let main = try #require(Lexicon.JSONValue(encoding: document).object?["defs"]?.object?["main"]?.object)
        let record = try #require(main["record"]?.object)
        expectNoDifference(main["key"], "tid")
        expectNoDifference(record["required"], .array(["event", "name", "createdAt"]))
        expectNoDifference(record["nullable"], .array(["subject", "source", "description", "roles", "links", "media"]))
        let properties = try #require(record["properties"]?.object)
        expectNoDifference(properties["description"]?.object?["maxGraphemes"], 5_000)
        expectNoDifference(properties["source"], .object([
            "description": "A pinned DID-authored profile record used as provenance when hydrating this organizer-owned snapshot.",
            "type": "ref",
            "ref": "com.atproto.repo.strongRef",
        ]))
        expectNoDifference(properties["roles"]?.object?["minLength"], 1)
        expectNoDifference(properties["roles"]?.object?["items"]?.object?["knownValues"], .array([
            "performer", "facilitator", "organizer", "sponsor", "vendor", "volunteer", "staff",
        ]))
        #expect(properties["confirmation"] == nil)
        #expect(properties["claim"] == nil)

        let strongRef = try #require(documents.first { $0.id.rawValue == "com.atproto.repo.strongRef" })
        let definition = try #require(Lexicon.JSONValue(encoding: strongRef).object?["defs"]?.object?["main"]?.object)
        expectNoDifference(definition["required"], .array(["uri", "cid"]))
        expectNoDifference(Set(try #require(definition["properties"]?.object).keys), ["uri", "cid"])
        expectNoDifference(definition["properties"]?.object?["uri"]?.object?["format"], "at-uri")
        expectNoDifference(definition["properties"]?.object?["cid"]?.object?["format"], "cid")
    }
}
