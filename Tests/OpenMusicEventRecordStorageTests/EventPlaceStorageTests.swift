import OpenMusicEventDatabase
import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct EventPlaceStorageTests {
    typealias Stage = OpenMusicEventLexicon.Stage
    typealias Event = OpenMusicEventLexicon.Event

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcai")!
    let stageURI = ATProto.URI("at://did:plc:stageowner/events.openmusic.stage/3mrdbziccpcaj")!
    let createdAt: ATProto.DateTime = "2026-09-21T12:00:00Z"

    @Test
    func `future kinds locators and media survive an unrelated edit and storage`() throws {
        var place = try EventPlace(
            id: placeURI, event: eventURI, name: "Future destination", createdAt: createdAt,
            locators: [.unknown(.object(["$type": "events.example.defs#indoor", "room": "A"]))],
            media: [.unknown(.object(["$type": "events.example.defs#video", "url": "https://example.com/place.mp4"]))],
            kind: .unknown(.object(["$type": "events.example.defs#charging", "ports": .integer(4)]))
        )
        let original = try place.encodeLexicon()
        place = try EventPlace.decodeLexicon(original, metadata: .init(uri: placeURI))
        place.name = "Renamed destination"
        try place.validateReferences()
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try EventPlace.insert { place }.execute(db)
        }
        let stored = try database.read { db in try #require(try EventPlace.find(placeURI).fetchOne(db)) }
        expectNoDifference(stored, place)
        for field in ["kind", "locators", "media"] {
            expectNoDifference(try stored.encodeLexicon().object?[field], original.object?[field])
        }
    }


    @Test(arguments: ["stage", "generic", "future"])
    func `schedule rows read event place presentation without a cached persistent stage`(_ use: String) throws {
        let icon = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/hollow-icon.png")))),
            role: .known(.icon(.init(canRepresentSubjectWithoutLabel: true)))
        )
        let kind: Open<EventPlace.Kind>? = switch use {
        case "stage": .known(.stage(.init(stage: stageURI, color: OME.Color(rawValue: 0x336699))))
        case "generic": nil
        default: .unknown(.object(["$type": "events.example.defs#futurePlace"]))
        }
        let place = try EventPlace(
            id: placeURI, event: eventURI, name: "The Hollow — 2026", createdAt: createdAt,
            locators: [.known(.geo(.init(latitude: "50.5", longitude: "-116.0")))],
            media: [.known(.image(icon))],
            kind: kind
        )
        let performance = try ProgramItem(
            id: #require(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.programItem/3mrdbziccpcak")),
            event: eventURI,
            program: #require(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcam")),
            title: "Opening set", createdAt: createdAt,
            eventPlace: placeURI, startsAt: "2026-09-04T20:00:00Z"
        )
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            // The schedule row remains useful before the linked Stage record is cached.
            #expect(try Stage.find(stageURI).fetchOne(db) == nil)
            try place.validateReferences()
            try EventPlace.insert { place }.execute(db)
            try ProgramItem.insert { performance }.execute(db)
        }
        let rows = try database.read { db in
            try ProgramItem.all
                .join(EventPlace.all) { $0.eventPlace.eq($1.id) && $0.event.eq($1.event) }
                .fetchAll(db)
        }
        let (scheduled, destination) = try #require(rows.first)
        expectNoDifference(scheduled, performance)
        expectNoDifference(destination, place)
        expectNoDifference(destination.media, [.known(.image(icon))])

        // Linking to a place in a different edition must not produce a schedule row.
        try database.write { db in
            try ProgramItem.find(performance.id).update {
                $0.event = #bind(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcam")!)
            }.execute(db)
        }
        let mismatchedCount = try database.read { db in
            try ProgramItem.all
                .join(EventPlace.all) { $0.eventPlace.eq($1.id) && $0.event.eq($1.event) }
                .fetchAll(db).count
        }
        expectNoDifference(mismatchedCount, 0)
    }


    @Test
    func `persistent stage edits and deletion do not rewrite places in either edition`() throws {
        var stage = try Stage(id: stageURI, name: "Persistent profile", createdAt: createdAt)
        let first = try EventPlace(
            id: placeURI, event: eventURI, name: "2026 stage name", createdAt: createdAt,
            kind: .known(.stage(.init(stage: stageURI)))
        )
        let second = try EventPlace(
            id: #require(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcan")),
            event: #require(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcam")),
            name: "2027 stage name", createdAt: createdAt, kind: .known(.stage(.init(stage: stageURI)))
        )
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try Stage.insert { stage }.execute(db)
            try EventPlace.insert { first; second }.execute(db)
            stage.name = "Renamed persistent profile"
            try Stage.upsert { stage }.execute(db)
            expectNoDifference(try Stage.find(stageURI).fetchOne(db), stage)
            expectNoDifference(try EventPlace.find(first.id).fetchOne(db), first)
            try Stage.find(stageURI).delete().execute(db)
            expectNoDifference(try EventPlace.find(first.id).fetchOne(db), first)
            expectNoDifference(try EventPlace.find(second.id).fetchOne(db), second)
        }
    }
}
