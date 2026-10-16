import OpenMusicEventDatabase
import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ProgramItemStorageTests {
    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let programURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal")!
    let scheduleURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam")!
    let itemURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.programItem/3mrdbziccpcai")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcaj")!
    let createdAt: ATProto.DateTime = "2026-09-22T12:00:00Z"

    @Test
    func `program items keep ordered media unknown variants and storage`() throws {
        let streamplaceURI = try #require(ATProto.URI(
            "at://did:plc:streamplace/place.stream.video/3mrdbziccpcak"
        ))
        let youtube = try OME.Media.External(
            uri: #require(URL(string: "https://youtube.com/watch?v=wicked-woods")),
            title: "Wicked Woods Live",
            mediaKind: .known(.video)
        )
        var item = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Wicked Woods Live",
            createdAt: createdAt,
            media: [
                .known(.record(.init(uri: streamplaceURI))),
                .known(.external(youtube)),
                .unknown(.object(["$type": "media.example.release", "uri": "https://plyr.fm/wicked-woods"])),
            ]
        )
        try item.validateReferences()
        let original = try item.encodeLexicon()
        item = try ProgramItem.decodeLexicon(original, metadata: .init(uri: itemURI))
        item.title = "Wicked Woods Live — remastered"

        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try ProgramItem.insert { item }.execute(db)
        }
        let stored = try database.read { db in try #require(try ProgramItem.find(itemURI).fetchOne(db)) }
        expectNoDifference(stored, item)
        let storedJSON = try stored.encodeLexicon()
        guard case .array(let storedMedia) = storedJSON.object?["media"] else {
            Issue.record("Expected ordered program media")
            return
        }
        expectNoDifference(storedMedia.map { $0.object?["$type"] }, [
            "events.openmusic.defs#mediaRecord", "events.openmusic.defs#externalMedia", "media.example.release",
        ])
    }
}
