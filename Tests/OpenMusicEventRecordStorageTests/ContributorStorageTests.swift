import OpenMusicEventDatabase
import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ContributorStorageTests {
    typealias Contributor = OpenMusicEventLexicon.Contributor

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let contributorURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.contributor/3mrdbziccpcai")!
    let subject = DID("did:plc:artist")!
    let sourceURI = ATProto.URI("at://did:plc:artist/app.bsky.actor.profile/self")!
    let sourceCID: ATProto.CID = "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
    let createdAt: ATProto.DateTime = "2026-09-22T18:00:00Z"

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
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
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
}
