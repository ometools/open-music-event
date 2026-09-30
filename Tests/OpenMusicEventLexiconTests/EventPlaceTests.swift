import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct EventPlaceTests {
    typealias Stage = OpenMusicEventLexicon.Stage
    typealias Event = OpenMusicEventLexicon.Event

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcai")!
    let stageURI = ATProto.URI("at://did:plc:stageowner/events.openmusic.stage/3mrdbziccpcaj")!
    let createdAt: ATProto.DateTime = "2026-09-21T12:00:00Z"

    @Test
    func `a persistent stage has no edition or event presentation requirements`() throws {
        let stage = try Stage(id: stageURI, cid: "observed-revision", name: "The Hollow", createdAt: createdAt)
        expectNoDifference(try stage.encodeLexicon(), .object([
            "$type": "events.openmusic.stage", "name": "The Hollow", "createdAt": .string(createdAt.rawValue),
        ]))
        expectNoDifference(
            try Stage.decodeLexicon(stage.encodeLexicon(), metadata: .init(uri: stageURI, cid: "observed-revision")),
            stage
        )
    }

    @Test
    func `an organizer can publish a named place before its use or coordinates are known`() throws {
        let place = try EventPlace(id: placeURI, event: eventURI, name: "Meeting point", createdAt: createdAt)
        try place.validateReferences()
        expectNoDifference(try place.encodeLexicon(), .object([
            "$type": "events.openmusic.eventPlace", "event": .string(eventURI.description),
            "name": "Meeting point", "createdAt": .string(createdAt.rawValue),
        ]))
        #expect(place.kind == nil)
        #expect(place.locators == nil)
    }

    @Test(arguments: ["event", "name", "createdAt"])
    func `required place fields cannot disappear`(_ field: String) throws {
        var payload = try #require(EventPlace(id: placeURI, event: eventURI, name: "Gate", createdAt: createdAt).encodeLexicon().object)
        payload.removeValue(forKey: field)
        #expect(throws: (any Error).self) { try EventPlace.decodeLexicon(.object(payload), metadata: .init(uri: placeURI)) }
    }

    @Test(arguments: ["description", "locators", "links", "media", "kind"])
    func `optional place fields accept null and encode absence`(_ field: String) throws {
        let place = try EventPlace(id: placeURI, event: eventURI, name: "Gate", createdAt: createdAt)
        var payload = try #require(place.encodeLexicon().object)
        payload[field] = .null
        let decoded = try EventPlace.decodeLexicon(.object(payload), metadata: .init(uri: placeURI))
        expectNoDifference(decoded, place)
        expectNoDifference(try decoded.encodeLexicon(), try place.encodeLexicon())
    }

    @Test
    func `linking and unlinking persistent identity preserves the place and its copied presentation`() throws {
        var place = try EventPlace(
            id: placeURI, cid: "place-revision", event: eventURI, name: "The Hollow — 2026",
            createdAt: createdAt, description: "Enter from the north path",
            kind: .known(.stage(.init(color: OME.Color(rawValue: 0x336699))))
        )
        let original = place
        // The stage already renders before a persistent profile has been selected.
        expectNoDifference(try place.encodeLexicon().object?["kind"], .object([
            "$type": "events.openmusic.defs#eventPlaceStage", "color": .integer(0x336699),
        ]))

        // Selecting continuity changes only the nested reference.
        guard case var .known(.stage(use)) = place.kind else {
            Issue.record("Expected stage use")
            return
        }
        use.stage = stageURI
        place.kind = .known(.stage(use))
        try place.validateReferences()
        expectNoDifference(place.id, original.id)
        expectNoDifference(place.name, original.name)
        expectNoDifference(place.cid, original.cid)
        expectNoDifference(try place.encodeLexicon().object?["kind"], .object([
            "$type": "events.openmusic.defs#eventPlaceStage", "stage": .string(stageURI.description),
            "color": .integer(0x336699),
        ]))

        use.stage = nil
        place.kind = .known(.stage(use))
        expectNoDifference(place, original)
    }

    @Test(arguments: ["entrance", "camping", "info"])
    func `nonstage places need no persistent entity`(_ kind: String) throws {
        let placeKind: EventPlace.Kind = switch kind {
        case "entrance": .entrance(.init())
        case "camping": .camping(.init())
        default: .info(.init())
        }
        let place = try EventPlace(id: placeURI, event: eventURI, name: kind, createdAt: createdAt, kind: .known(placeKind))
        try place.validateReferences()
        let json = try place.encodeLexicon()
        let suffix = kind.prefix(1).uppercased() + kind.dropFirst()
        expectNoDifference(json.object?["kind"], .object(["$type": .string("events.openmusic.defs#eventPlace" + suffix)]))
        expectNoDifference(try EventPlace.decodeLexicon(json, metadata: .init(uri: placeURI)), place)
    }

    @Test
    func `verified ingestion rejects foreign event ownership without making decoding depend on a cache`() throws {
        var payload = try #require(EventPlace(id: placeURI, event: eventURI, name: "Gate", createdAt: createdAt).encodeLexicon().object)
        payload["event"] = "at://did:plc:anotherorganizer/events.openmusic.event/3mrdbziccpcah"
        let decoded = try EventPlace.decodeLexicon(.object(payload), metadata: .init(uri: placeURI))
        // Decode preserves the declared data. The verified ingestion/authoring boundary rejects its ownership.
        #expect(throws: ValidationError.self) { try decoded.validateReferences() }

        let valid = try EventPlace(id: placeURI, event: eventURI, name: "Gate", createdAt: createdAt)
        try valid.validateReferences() // No Event or Stage fetch is needed.
    }

    @Test(arguments: [
        "at://did:plc:wickedwoods/events.openmusic.stage/3mrdbziccpcah",
        "at://wickedwoods.example/events.openmusic.event/3mrdbziccpcah",
        "at://did:plc:wickedwoods/events.openmusic.event",
    ])
    func `ingestion requires a complete event record address`(_ address: String) throws {
        let place = try EventPlace(
            id: placeURI, event: #require(ATProto.URI(address)), name: "Gate", createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try place.validateReferences() }
    }

    @Test
    func `a continuity reference must address a persistent stage`() throws {
        let place = try EventPlace(
            id: placeURI, event: eventURI, name: "Stage", createdAt: createdAt,
            kind: .known(.stage(.init(stage: eventURI)))
        )
        #expect(throws: ValidationError.self) { try place.validateReferences() }
    }

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
        try database.write { db in
            try Self.createPlaceTable(db)
            try EventPlace.insert { place }.execute(db)
        }
        let stored = try database.read { db in try #require(try EventPlace.find(placeURI).fetchOne(db)) }
        expectNoDifference(stored, place)
        for field in ["kind", "locators", "media"] {
            expectNoDifference(try stored.encodeLexicon().object?[field], original.object?[field])
        }
    }

    @Test(arguments: [
        #"{"$type":"events.openmusic.defs#eventPlaceStage","color":16777216}"#,
        #"{"$type":"events.openmusic.defs#eventPlaceStage","stage":42}"#,
        #"{"color":42}"#,
    ])
    func `malformed known kinds cannot become unknown variants`(_ kind: String) throws {
        var payload = try #require(EventPlace(id: placeURI, event: eventURI, name: "Stage", createdAt: createdAt).encodeLexicon().object)
        payload["kind"] = try JSONDecoder().decode(Lexicon.JSONValue.self, from: Data(kind.utf8))
        #expect(throws: (any Error).self) { try EventPlace.decodeLexicon(.object(payload), metadata: .init(uri: placeURI)) }
    }

    @Test(arguments: ["stage", "generic", "future"])
    func `schedule rows read event place presentation without a persistent stage table`(_ use: String) throws {
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
        let performance = try PerformanceFixture(
            id: #require(ATProto.URI("at://did:plc:wickedwoods/events.example.performance/3mrdbziccpcak")),
            event: eventURI, eventPlace: placeURI, title: "Opening set", startsAt: "2026-09-04T20:00:00Z"
        )
        let database = try DatabaseQueue()
        try database.write { db in
            // This partial cache deliberately has no Event or Stage table.
            try Self.createPlaceTable(db)
            try #sql("""
                CREATE TABLE "testPlacePerformances" (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
                  "eventPlace" TEXT NOT NULL, "title" TEXT NOT NULL, "startsAt" TEXT NOT NULL
                ) STRICT
                """).execute(db)
            try place.validateReferences()
            try EventPlace.insert { place }.execute(db)
            try PerformanceFixture.insert { performance }.execute(db)
        }
        let rows = try database.read { db in
            try PerformanceFixture.all
                .join(EventPlace.all) { $0.eventPlace.eq($1.id) && $0.event.eq($1.event) }
                .fetchAll(db)
        }
        let (scheduled, destination) = try #require(rows.first)
        expectNoDifference(scheduled, performance)
        expectNoDifference(destination, place)
        expectNoDifference(destination.media, [.known(.image(icon))])

        // Linking to a place in a different edition must not produce a schedule row.
        try database.write { db in
            try PerformanceFixture.find(performance.id).update {
                $0.event = #bind(ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcam")!)
            }.execute(db)
        }
        let mismatchedCount = try database.read { db in
            try PerformanceFixture.all
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
        try database.write { db in
            try Self.createPlaceTable(db)
            try #sql("""
                CREATE TABLE "events.openmusic.stage" (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL, "description" TEXT, "links" TEXT, "media" TEXT
                ) STRICT
                """).execute(db)
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

    @Test
    func `export roots include both records and the stage use definition without exporting the performance fixture`() throws {
        let documents = try LexiconExporter.documents(for: [
            Event.self, Stage.self, EventPlace.self, Program.self,
            OpenMusicEventLexicon.Schedule.self, ProgramItem.self, OME.Color.self,
        ])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "events.openmusic.event", "events.openmusic.stage", "events.openmusic.eventPlace",
            "events.openmusic.program", "events.openmusic.schedule", "events.openmusic.programItem",
            "events.openmusic.defs",
            "community.lexicon.location.address", "community.lexicon.location.geo",
            "community.lexicon.location.fsq", "community.lexicon.location.hthree",
        ])
        let place = try #require(documents.first { $0.id.rawValue == "events.openmusic.eventPlace" })
        let record = try #require(Lexicon.JSONValue(encoding: place).object?["defs"]?.object?["main"]?.object?["record"]?.object)
        expectNoDifference(record["required"], ["event", "name", "createdAt"])
        let properties = try #require(record["properties"]?.object)
        #expect(properties["id"] == nil && properties["cid"] == nil)
        #expect(properties["category"] == nil && properties["sortIndex"] == nil && properties["color"] == nil)
        let kind = try #require(properties["kind"]?.object)
        expectNoDifference(kind["type"], "union")
        // An omitted closed flag is an open union under the Lexicon specification.
        #expect(kind["closed"] == nil || kind["closed"] == .bool(false))
        let defs = try #require(documents.first { $0.id.rawValue == "events.openmusic.defs" })
        let definitions = try #require(Lexicon.JSONValue(encoding: defs).object?["defs"]?.object)
        let stageUse = try #require(definitions["eventPlaceStage"]?.object)
        expectNoDifference(Set(try #require(stageUse["properties"]?.object).keys), ["stage", "color"])
        #expect(definitions["stage"] == nil)
    }

    static func createPlaceTable(_ db: Database) throws {
        try #sql("""
            CREATE TABLE "events.openmusic.eventPlace" (
              "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
              "name" TEXT NOT NULL, "createdAt" TEXT NOT NULL, "description" TEXT,
              "locators" TEXT, "links" TEXT, "media" TEXT, "kind" TEXT
            ) STRICT
            """).execute(db)
    }
}

// Only the place-reference contract is modeled here; this is not the public Performance schema.
@Table("testPlacePerformances")
@Lexicon("events.example.performance", type: .record(key: .tid))
struct PerformanceFixture: RecordCodable, Equatable {
    @LexiconIgnored @Column(primaryKey: true) let id: ATProto.URI
    @LexiconIgnored var cid: ATProto.CID? = nil
    var event: ATProto.URI
    var eventPlace: ATProto.URI
    var title: String
    var startsAt: ATProto.DateTime
}
