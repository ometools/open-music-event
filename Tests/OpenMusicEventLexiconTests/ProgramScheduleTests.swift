import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ProgramScheduleTests {
    typealias PublicSchedule = OpenMusicEventLexicon.Schedule

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let programURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal")!
    let scheduleURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcaj")!
    let itemURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.programItem/3mrdbziccpcai")!
    let createdAt: ATProto.DateTime = "2026-09-22T12:00:00Z"

    @Test
    func `a program declares its complete ordered place list`() throws {
        let secondPlace = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcan"
        ))
        let program = try Program(
            id: programURI,
            event: eventURI,
            title: "Schedule",
            createdAt: createdAt,
            description: "Music across the festival stages",
            icon: .calendar,
            eventPlaces: [placeURI, secondPlace]
        )
        try program.validateReferences()
        expectNoDifference(try program.encodeLexicon(), .object([
            "$type": "events.openmusic.program",
            "event": .string(eventURI.description),
            "title": "Schedule",
            "createdAt": .string(createdAt.rawValue),
            "description": "Music across the festival stages",
            "icon": "calendar",
            "eventPlaces": .array([
                .string(placeURI.description),
                .string(secondPlace.description),
            ]),
        ]))
        expectNoDifference(
            try Program.decodeLexicon(program.encodeLexicon(), metadata: .init(uri: programURI)),
            program
        )
    }

    @Test
    func `a program can exhaustively declare that it has no places`() throws {
        let program = try Program(
            id: programURI,
            event: eventURI,
            title: "Announcements",
            createdAt: createdAt,
            eventPlaces: []
        )
        try program.validateReferences()
        expectNoDifference(try program.encodeLexicon().object?["eventPlaces"], .array([]))
    }

    @Test
    func `program places are unique records in the event repository`() throws {
        var program = try Program(
            id: programURI,
            event: eventURI,
            title: "Schedule",
            createdAt: createdAt,
            eventPlaces: [placeURI, placeURI]
        )
        #expect(throws: ValidationError.self) { try program.validateReferences() }

        program.eventPlaces = [try #require(ATProto.URI(
            "at://did:plc:another/events.openmusic.eventPlace/3mrdbziccpcaj"
        ))]
        #expect(throws: ValidationError.self) { try program.validateReferences() }
    }

    @Test
    func `a schedule is an organizer defined festival day rather than a timestamp date`() throws {
        let saturday = try PublicSchedule(
            id: scheduleURI,
            event: eventURI,
            date: #require(LocalDate("2026-09-05")),
            createdAt: createdAt,
            title: "Saturday"
        )
        try saturday.validateReferences()
        expectNoDifference(try saturday.encodeLexicon(), .object([
            "$type": "events.openmusic.schedule",
            "event": .string(eventURI.description),
            "date": "2026-09-05",
            "createdAt": .string(createdAt.rawValue),
            "title": "Saturday",
        ]))
        expectNoDifference(
            try PublicSchedule.decodeLexicon(saturday.encodeLexicon(), metadata: .init(uri: scheduleURI)),
            saturday
        )
    }

    @Test
    func `Distinct Motive remains on Saturday after midnight`() throws {
        let saturday = try PublicSchedule(
            id: scheduleURI,
            event: eventURI,
            date: #require(LocalDate("2026-09-05")),
            createdAt: createdAt
        )
        let program = try Program(
            id: programURI,
            event: eventURI,
            title: "Schedule",
            createdAt: createdAt,
            icon: .calendar,
            eventPlaces: [placeURI]
        )
        let place = try EventPlace(
            id: placeURI,
            event: eventURI,
            name: "Ursus",
            createdAt: createdAt
        )
        let event = try Event(
            id: eventURI,
            name: "Wicked Woods",
            createdAt: createdAt,
            timeZone: #require(TimeZone(identifier: "America/Edmonton")),
            programs: [programURI],
            schedules: [scheduleURI]
        )
        let item = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Distinct Motive",
            createdAt: createdAt,
            schedule: scheduleURI,
            eventPlace: placeURI,
            startsAt: "2026-09-06T06:30:00Z",
            endsAt: "2026-09-06T08:00:00Z"
        )

        try item.validateGraph(event: event, program: program, schedule: saturday, eventPlace: place)
        let start = try #require(item.startsAt.flatMap(ProgramItem.date))
        let sundayDate = try #require(LocalDate("2026-09-06"))
        let saturdayDate = try #require(LocalDate("2026-09-05"))
        expectNoDifference(LocalDate(start, in: event.timeZone), sundayDate)
        expectNoDifference(saturday.date, saturdayDate)
    }

    @Test
    func `resolved graph validation rejects records from another event`() throws {
        let otherEvent = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcao"
        ))
        let event = try Event(
            id: eventURI,
            name: "Wicked Woods",
            createdAt: createdAt,
            timeZone: .gmt,
            programs: [programURI]
        )
        let program = try Program(
            id: programURI,
            event: otherEvent,
            title: "Schedule",
            createdAt: createdAt,
            eventPlaces: []
        )
        let item = try ProgramItem(
            id: itemURI,
            event: eventURI,
            program: programURI,
            title: "Lineup announcement",
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) {
            try item.validateGraph(event: event, program: program)
        }
    }

    @Test
    func `programs and schedules round trip through independent tables`() throws {
        let program = try Program(
            id: programURI,
            event: eventURI,
            title: "Schedule",
            createdAt: createdAt,
            eventPlaces: [placeURI]
        )
        let schedule = try PublicSchedule(
            id: scheduleURI,
            event: eventURI,
            date: #require(LocalDate("2026-09-05")),
            createdAt: createdAt
        )
        let database = try DatabaseQueue()
        try database.write { db in
            try #sql("""
                CREATE TABLE \(quote: Program.tableName) (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
                  "title" TEXT NOT NULL, "createdAt" TEXT NOT NULL,
                  "description" TEXT, "icon" TEXT, "eventPlaces" TEXT NOT NULL
                ) STRICT
                """).execute(db)
            try #sql("""
                CREATE TABLE \(quote: PublicSchedule.tableName) (
                  "id" TEXT PRIMARY KEY NOT NULL, "cid" TEXT, "event" TEXT NOT NULL,
                  "date" TEXT NOT NULL, "createdAt" TEXT NOT NULL, "title" TEXT
                ) STRICT
                """).execute(db)
            try Program.insert { program }.execute(db)
            try PublicSchedule.insert { schedule }.execute(db)
        }
        expectNoDifference(
            try database.read { db in try Program.find(programURI).fetchOne(db) },
            program
        )
        expectNoDifference(
            try database.read { db in try PublicSchedule.find(scheduleURI).fetchOne(db) },
            schedule
        )
    }

    @Test
    func `the exporter exposes separate program and festival day records`() throws {
        let documents = try LexiconExporter.documents(for: [Program.self, PublicSchedule.self])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "events.openmusic.defs",
            "events.openmusic.program",
            "events.openmusic.schedule",
        ])

        let program = try #require(documents.first { $0.id.rawValue == "events.openmusic.program" })
        let programRecord = try #require(
            Lexicon.JSONValue(encoding: program).object?["defs"]?.object?["main"]?.object?["record"]?.object
        )
        expectNoDifference(programRecord["required"], ["event", "title", "createdAt", "eventPlaces"])
        expectNoDifference(programRecord["nullable"], ["description", "icon"])
        expectNoDifference(programRecord["properties"]?.object?["icon"], .object([
            "type": "ref",
            "ref": "events.openmusic.defs#semanticIcon",
            "description": "A platform-neutral icon for this program's tab or section.",
        ]))

        let schedule = try #require(documents.first { $0.id.rawValue == "events.openmusic.schedule" })
        let scheduleRecord = try #require(
            Lexicon.JSONValue(encoding: schedule).object?["defs"]?.object?["main"]?.object?["record"]?.object
        )
        expectNoDifference(scheduleRecord["required"], ["event", "date", "createdAt"])
        expectNoDifference(scheduleRecord["nullable"], ["title"])
        expectNoDifference(scheduleRecord["properties"]?.object?["date"]?.object?["type"], "string")
    }
}
