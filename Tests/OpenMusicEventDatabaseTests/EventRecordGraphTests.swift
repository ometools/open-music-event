import ATProto
import ATProtoTypes
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct EventRecordGraphTests {
    @Test
    func relatedRecordsAreStoredAndQueriedByProtocolEventID() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        EventRecordMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let id = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let programID = try #require(Program.ID("at://did:plc:organizer/events.openmusic.program/3mrdbziccpcah"))
        let scheduleID = try #require(Schedule.ID("at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcah"))
        let placeID = try #require(EventPlace.ID("at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcah"))
        let contributorID = try #require(Contributor.ID("at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpcah"))
        let itemID = try #require(ProgramItem.ID("at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcah"))
        let categoryID = try #require(Social.Category.ID("at://did:plc:organizer/social.ome.category/3mrdbziccpcah"))
        let event = try Event(
            id: id, name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            programs: [programID], schedules: [scheduleID], categories: [categoryID]
        )
        let graph = try EventRecordGraph(
            event: event,
            programs: [
                Program(id: programID, event: id, title: "Music",
                        createdAt: "2026-09-01T12:00:00Z", eventPlaces: [placeID])
            ],
            schedules: [
                Schedule(id: scheduleID, event: id, date: #require(LocalDate("2026-09-04")),
                         createdAt: "2026-09-01T12:00:00Z")
            ],
            places: [
                EventPlace(id: placeID, event: id, name: "Main Stage",
                           createdAt: "2026-09-01T12:00:00Z")
            ],
            contributors: [
                Contributor(id: contributorID, event: id, name: "Artist",
                            createdAt: "2026-09-01T12:00:00Z")
            ],
            items: [
                ProgramItem(id: itemID, event: id, program: programID, title: "Opening Set",
                            createdAt: "2026-09-01T12:00:00Z",
                            schedule: scheduleID, eventPlace: placeID)
            ],
            categories: [
                Social.Category(id: categoryID, event: id, name: "Announcements",
                                createdAt: "2026-09-01T12:00:00Z")
            ]
        )

        // All related records retain their protocol identities; no source IDs are needed.
        try database.write { try graph.upsert(in: $0) }
        expectNoDifference(try database.read { try EventRecordGraph.fetch(eventID: id, from: $0) }, graph)

        // Bundle round trips preserve canonical identities and reject malformed envelopes.
        let values: [any RecordCodable] = [
            event, graph.programs[0], graph.schedules[0], graph.places[0],
            graph.contributors[0], graph.items[0], graph.categories[0]
        ]
        let records = try values.map { value in
            Event.IndexedRecord(uri: value.id, cid: nil, value: try value.encodeLexicon())
        }
        let bundle = Event.Bundle(uri: id, revision: "snapshot", records: records)
        expectNoDifference(try EventRecordGraph(bundle: bundle), graph)
        var duplicate = bundle
        duplicate.records.append(duplicate.records[0])
        #expect(throws: ValidationError.self) { try EventRecordGraph(bundle: duplicate) }

        // Relationship validation still rejects unavailable or undeclared dependencies.
        for scenario in ["program", "schedule", "place", "membership", "duplicate"] {
            var broken = graph
            switch scenario {
            case "program": broken.programs = []
            case "schedule": broken.schedules = []
            case "place": broken.places = []
            case "membership": broken.programs[0].eventPlaces = []
            default: broken.items.append(broken.items[0])
            }
            #expect(throws: ValidationError.self) { try broken.validateRelationships() }
        }

        // A second edition cannot see the first edition's programs or places.
        let anotherID = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"))
        let anotherEvent = try Event(
            id: anotherID, name: "Next Edition", createdAt: "2026-09-01T12:00:00Z",
            timeZone: event.timeZone
        )
        let anotherGraph = EventRecordGraph(event: anotherEvent)
        try database.write { try anotherGraph.upsert(in: $0) }
        expectNoDifference(
            try database.read { try EventRecordGraph.fetch(eventID: anotherID, from: $0) },
            anotherGraph
        )

        // Replacing a place with one owned by another edition fails before any writes.
        var invalid = graph
        invalid.event.name = "Must not be saved"
        invalid.places[0].event = anotherID
        #expect(throws: ValidationError.self) {
            try database.write { try invalid.upsert(in: $0) }
        }
        expectNoDifference(try database.read { try EventRecordGraph.fetch(eventID: id, from: $0) }, graph)
    }
}
