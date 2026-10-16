import OpenMusicEventDatabase
import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct EventStorageTests {
    private let uri = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!

    typealias Event = OpenMusicEventLexicon.Event

    @Test(arguments: [nil, TimeZone(identifier: "America/Edmonton")])
    func `the public event model round trips through its SQLite table`(timeZone: TimeZone?) throws {
        let programURI = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal"
        ))
        let scheduleURI = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam"
        ))
        var event = try Event(
            id: uri,
            cid: "last-observed-revision",
            name: "Wicked Woods",
            createdAt: "2026-01-01T12:00:00.000Z",
            timeZone: timeZone,
            description: "Music in the woods",
            start: .known(.day(.init(value: try #require(LocalDate("2026-09-04"))))),
            end: .known(.time(.init(value: "2026-09-07T06:00:00.000Z"))),
            status: .unknown("events.example.defs#tentative"),
            mode: .known(.inPerson),
            locations: [
                .init(
                    name: "Festival grounds",
                    locators: [.known(.address(.init(country: "CA", locality: "Invermere")))],
                    links: [.init(url: try #require(URL(string: "https://example.com/map")), title: "Map")]
                ),
            ],
            links: [.init(url: try #require(URL(string: "https://example.com/tickets")), role: .known(.tickets(.init())))],
            programs: [programURI],
            schedules: [scheduleURI],
            rsvpExpected: true,
            categories: [#require(ATProto.URI("at://did:plc:wickedwoods/social.ome.category/3mrdbziccpcam"))],
            siteMap: .init(title: "Festival map", styles: [
                .init(id: "public", title: "Public", image: .init(
                    source: .known(.url(#require(URL(string: "https://example.com/map.png")))),
                    role: .known(.siteMap)
                )),
            ], defaultStyleID: "public")
        )
        event.media = [
            .known(.image(.init(source: .known(.url(try #require(URL(string: "https://example.com/poster.png"))))))),
            .unknown(.object([
                "$type": "events.example.defs#video",
                "url": "https://example.com/recap.mp4",
            ])),
        ]

        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try Event.insert { event }.execute(db)
            #expect(throws: (any Error).self) { try Event.insert { event }.execute(db) }
        }

        let stored = try database.read { db in
            try #require(try Event.all.fetchOne(db))
        }
        #expect(Event.tableName == "events.openmusic.event")
        expectNoDifference(stored, event)
        expectNoDifference(try stored.encodeLexicon(), try event.encodeLexicon())

        event.name = "Wicked Woods — updated locally"
        #expect(event.cid == "last-observed-revision")
        try database.write { db in
            try Event.find(uri).update { $0.name = event.name }.execute(db)
            let edited = try #require(try Event.find(uri).fetchOne(db))
            expectNoDifference(edited, event)
            try Event.find(uri).update { $0.cid = #bind("new-repository-revision" as ATProto.CID?) }.execute(db)
            #expect(try Event.find(uri).fetchOne(db)?.cid == "new-repository-revision")
            try Event.find(uri).delete().execute(db)
            #expect(try Event.find(uri).fetchOne(db) == nil)
        }
    }
}
