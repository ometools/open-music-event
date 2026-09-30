import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ProgramItemTests {
    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let programURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal")!
    let scheduleURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam")!
    let itemURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.programItem/3mrdbziccpcai")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcaj")!
    let createdAt: ATProto.DateTime = "2026-09-22T12:00:00Z"

    @Test
    func `an attendee facing item can be announced before credits place or time are assigned`() throws {
        let doors = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Doors open",
            createdAt: createdAt
        )
        try doors.validateReferences()
        expectNoDifference(try doors.encodeLexicon(), .object([
            "$type": "events.openmusic.programItem",
            "event": .string(eventURI.description),
            "program": .string(programURI.description),
            "title": "Doors open",
            "createdAt": .string(createdAt.rawValue),
        ]))
        #expect(doors.credits == nil)
        #expect(doors.eventPlace == nil)
        #expect(doors.startsAt == nil)
    }

    @Test(arguments: ["event", "program", "title", "createdAt"])
    func `required program fields cannot disappear`(_ field: String) throws {
        var payload = try #require(ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Doors open",
            createdAt: createdAt
        ).encodeLexicon().object)
        payload.removeValue(forKey: field)
        #expect(throws: (any Error).self) {
            try ProgramItem.decodeLexicon(.object(payload), metadata: .init(uri: itemURI))
        }
    }

    @Test(arguments: ["description", "schedule", "eventPlace", "startsAt", "endsAt", "credits", "media"])
    func `optional program fields accept null and encode absence`(_ field: String) throws {
        let item = try ProgramItem(
            id: itemURI, event: eventURI, program: programURI, title: "Doors open", createdAt: createdAt
        )
        var payload = try #require(item.encodeLexicon().object)
        payload[field] = .null
        let decoded = try ProgramItem.decodeLexicon(.object(payload), metadata: .init(uri: itemURI))
        expectNoDifference(decoded, item)
        expectNoDifference(try decoded.encodeLexicon(), try item.encodeLexicon())
    }

    @Test
    func `credits may be omitted but cannot be an empty published list`() throws {
        var item = try ProgramItem(id: itemURI, event: eventURI, program: programURI, title: "Set", createdAt: createdAt)
        item.credits = []
        #expect(throws: (any Error).self) { try item.encodeLexicon() }
    }

    @Test
    func `ordered credits preserve names contributor references billing and occurrence roles`() throws {
        let contributorURI = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.contributor/3mrdbziccpcak"
        ))
        let credits = [
            ProgramItem.Credit(name: "Wicked Woods"),
            ProgramItem.Credit(
                name: "Visual Crew",
                contributor: contributorURI,
                billing: .known(.supporting),
                role: "projection art"
            ),
        ]
        let item = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Wicked Woods Live",
            createdAt: createdAt,
            credits: credits
        )
        try item.validateReferences()
        let json = try item.encodeLexicon()
        guard case .array(let encodedCredits) = json.object?["credits"] else {
            Issue.record("Expected ordered program credits")
            return
        }
        expectNoDifference(encodedCredits.map { $0.object?["name"] }, ["Wicked Woods", "Visual Crew"])
        expectNoDifference(encodedCredits[0].object?["billing"], "primary")
        expectNoDifference(encodedCredits[1].object?["contributor"], .string(contributorURI.description))
        expectNoDifference(try ProgramItem.decodeLexicon(json, metadata: .init(uri: itemURI)), item)
    }

    @Test(arguments: [
        "at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcak",
        "at://did:plc:another/events.openmusic.contributor/3mrdbziccpcak",
        "at://wickedwoods.example/events.openmusic.contributor/3mrdbziccpcak",
    ])
    func `identified credits require a contributor record in the event repository`(_ address: String) throws {
        let item = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Set",
            createdAt: createdAt,
            credits: [.init(name: "Artist", contributor: ATProto.URI(address))]
        )
        #expect(throws: ValidationError.self) { try item.validateReferences() }
    }

    @Test
    func `assigning and changing scheduling facts preserves occurrence identity`() throws {
        var item = try ProgramItem(
            id: itemURI,
            cid: "first-revision",
            event: eventURI,
            program: programURI,
            title: "Live set",
            createdAt: createdAt
        )
        item.schedule = scheduleURI
        item.eventPlace = placeURI
        item.startsAt = "2026-09-04T20:00:00Z"
        item.endsAt = "2026-09-04T21:00:00Z"
        try item.validateReferences()
        expectNoDifference(item.id, itemURI)
        expectNoDifference(item.createdAt, createdAt)
        expectNoDifference(item.cid, "first-revision")

        item.startsAt = "2026-09-05T01:00:00Z"
        item.endsAt = "2026-09-05T02:30:00Z"
        try item.validateReferences()
        expectNoDifference(item.id, itemURI)
        expectNoDifference(item.createdAt, createdAt)
    }

    @Test
    func `an end requires an earlier start`() throws {
        var item = try ProgramItem(
            id: itemURI, event: eventURI, program: programURI,
            title: "Set", createdAt: createdAt, schedule: scheduleURI
        )
        item.endsAt = "2026-09-04T21:00:00Z"
        #expect(throws: ValidationError.self) { try item.validateReferences() }

        item.startsAt = "2026-09-04T21:00:00Z"
        #expect(throws: ValidationError.self) { try item.validateReferences() }

        item.endsAt = "2026-09-04T20:00:00Z"
        #expect(throws: ValidationError.self) { try item.validateReferences() }
    }

    @Test
    func `a timed item requires an organizer assigned schedule while an untimed item may omit one`() throws {
        var item = try ProgramItem(
            id: itemURI, event: eventURI, program: programURI, title: "Lineup announcement", createdAt: createdAt
        )
        try item.validateReferences()

        item.startsAt = "2026-09-06T06:30:00Z"
        #expect(throws: ValidationError.self) { try item.validateReferences() }

        item.schedule = scheduleURI
        try item.validateReferences()
    }

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
        try database.write { db in
            try #sql("""
                CREATE TABLE \(quote: ProgramItem.tableName) (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
                  "program" TEXT NOT NULL, "schedule" TEXT,
                  "title" TEXT NOT NULL, "createdAt" TEXT NOT NULL, "description" TEXT,
                  "eventPlace" TEXT, "startsAt" TEXT, "endsAt" TEXT, "credits" TEXT, "media" TEXT
                ) STRICT
                """).execute(db)
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

    @Test
    func `program items and places must belong to the event repository`() throws {
        let foreignItem = try ProgramItem(
            id: #require(ATProto.URI("at://did:plc:another/events.openmusic.programItem/3mrdbziccpcai")),
            event: eventURI,
            program: programURI,
            title: "Foreign",
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try foreignItem.validateReferences() }

        let foreignPlace = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Foreign place",
            createdAt: createdAt,
            eventPlace: ATProto.URI("at://did:plc:another/events.openmusic.eventPlace/3mrdbziccpcaj")!
        )
        #expect(throws: ValidationError.self) { try foreignPlace.validateReferences() }

        let foreignProgram = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: #require(ATProto.URI("at://did:plc:another/events.openmusic.program/3mrdbziccpcal")),
            title: "Foreign program",
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try foreignProgram.validateReferences() }
    }

    @Test
    func `the exported record exposes the minimal program boundary`() throws {
        let documents = try LexiconExporter.documents(for: [ProgramItem.self])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "events.openmusic.programItem", "events.openmusic.defs",
        ])
        let document = try #require(documents.first { $0.id.rawValue == "events.openmusic.programItem" })
        let record = try #require(Lexicon.JSONValue(encoding: document).object?["defs"]?.object?["main"]?.object?["record"]?.object)
        expectNoDifference(record["required"], ["event", "program", "title", "createdAt"])
        expectNoDifference(record["nullable"], ["description", "schedule", "eventPlace", "startsAt", "endsAt", "credits", "media"])
        let properties = try #require(record["properties"]?.object)
        expectNoDifference(properties["credits"]?.object?["minLength"], 1)
        let credit = try #require(documents.first { $0.id.rawValue == "events.openmusic.defs" })
        let definitions = try #require(Lexicon.JSONValue(encoding: credit).object?["defs"]?.object)
        let contributor = try #require(definitions["programCredit"]?.object?["properties"]?.object?["contributor"]?.object)
        expectNoDifference(contributor["type"], "string")
        expectNoDifference(contributor["format"], "at-uri")
        #expect(definitions["programCredit"]?.object?["properties"]?.object?["subject"] == nil)
        #expect(definitions["programCreditActor"] == nil)
        #expect(definitions["programCreditRecord"] == nil)
        expectNoDifference(properties["media"]?.object?["items"]?.object?["refs"], [
            "events.openmusic.defs#image",
            "events.openmusic.defs#mediaRecord",
            "events.openmusic.defs#externalMedia",
        ])
        expectNoDifference(properties["program"]?.object?["format"], "at-uri")
        expectNoDifference(properties["schedule"]?.object?["format"], "at-uri")
        #expect(properties["kind"] == nil)
    }
}
