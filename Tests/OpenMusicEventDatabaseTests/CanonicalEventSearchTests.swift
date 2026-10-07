import CustomDump
import ATProto
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalEventSearchTests {
    @Test
    func dashboardPreservesTimingTiesStageMediaAndEventIsolation() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let eventID = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let otherEventID = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj"))
        let programID = try #require(Program.ID("at://did:plc:organizer/events.openmusic.program/3mrdbziccpcah"))
        let createdAt: ATProto.DateTime = "2026-09-01T12:00:00Z"
        let meadow = try EventPlace(
            id: #require(EventPlace.ID("at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcah")),
            event: eventID, name: "Meadow", createdAt: createdAt,
            media: [.unknown(.object(["$type": "media.example.image#image", "alt": "Meadow logo"]))],
            kind: .known(.stage(.init(color: #require(OME.Color(rawValue: 0x336699)), sortIndex: 0)))
        )
        let hollow = try EventPlace(
            id: #require(EventPlace.ID("at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcai")),
            event: eventID, name: "Hollow", createdAt: createdAt,
            kind: .known(.stage(.init(sortIndex: 1)))
        )
        let foreignPlace = try EventPlace(
            id: #require(EventPlace.ID("at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcaj")),
            event: otherEventID, name: "Other event stage", createdAt: createdAt,
            kind: .known(.stage(.init())))
        func item(_ key: String, _ title: String, place: EventPlace.ID?, start: ATProto.DateTime?, end: ATProto.DateTime?) throws -> ProgramItem {
            try ProgramItem(
                id: #require(ProgramItem.ID("at://did:plc:organizer/events.openmusic.programItem/" + key)),
                event: eventID, program: programID, title: title, createdAt: createdAt,
                eventPlace: place, startsAt: start, endsAt: end)
        }
        let ended = try item("3mrdbziccpcaa", "Ended", place: meadow.id, start: "2026-09-04T19:00:00Z", end: "2026-09-04T20:00:00Z")
        let current = try item("3mrdbziccpcab", "Current", place: meadow.id, start: "2026-09-04T20:00:00Z", end: "2026-09-04T21:00:00Z")
        let nextA = try item("3mrdbziccpcac", "Alpha", place: meadow.id, start: "2026-09-04T21:00:00Z", end: "2026-09-04T22:00:00Z")
        let nextB = try item("3mrdbziccpcad", "Beta", place: meadow.id, start: "2026-09-04T21:00:00Z", end: nil)
        let earlier = try item("3mrdbziccpcae", "Earlier", place: hollow.id, start: "2026-09-04T20:30:00.000Z", end: nil)
        let unplaced = try item("3mrdbziccpcaf", "Unplaced", place: nil, start: "2026-09-04T20:30:00.000Z", end: nil)
        let foreign = try item("3mrdbziccpcag", "Foreign reference", place: foreignPlace.id, start: "2026-09-04T20:00:00Z", end: "2026-09-04T21:00:00Z")
        let untimed = try item("3mrdbziccpcak", "To be announced", place: meadow.id, start: nil, end: nil)
        try database.write { db in
            try EventPlace.insert { [meadow, hollow, foreignPlace] }.execute(db)
            try ProgramItem.insert { [ended, current, nextA, nextB, earlier, unplaced, foreign, untimed] }.execute(db)
        }
        try database.read { db in
            // A set is current at its start and disappears exactly at its end.
            let now = try Date("2026-09-04T20:00:00Z", strategy: .iso8601)
            let dashboard = try EventSearchDashboard.fetch(eventID: eventID, now: now, db: db)
            expectNoDifference(dashboard.nowPlayingRows.map(\.id), [current.id, foreign.id])
            expectNoDifference(dashboard.nowPlayingRows.first?.stage, meadow)
            #expect(dashboard.nowPlayingRows.last?.stage == nil)
            expectNoDifference(dashboard.comingNextRows.map(\.id), [earlier.id, unplaced.id])
            // The stage playing next comes first; all simultaneous sets survive.
            expectNoDifference(dashboard.stageRows.map(\.id), [hollow.id, meadow.id])
            expectNoDifference(dashboard.stageRows.last?.comingNextRows.map(\.id), [nextA.id, nextB.id])
            expectNoDifference(dashboard.stageRows.last?.nowPlayingRows.map(\.id), [current.id])
            expectNoDifference(dashboard.stageRows.last?.comingNextRows.map(\.stage), [meadow, meadow])
            let after = try EventSearchDashboard.fetch(eventID: eventID, now: now.addingTimeInterval(86400), db: db)
            #expect(after.nowPlayingRows.isEmpty)
            #expect(after.comingNextRows.isEmpty)
            expectNoDifference(after.stageRows.map(\.id), [meadow.id, hollow.id])
        }
    }

    @Test
    func searchAndDashboardUseCanonicalEventRecords() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let otherEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj"
        ))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        let otherEvent = try Event(
            id: otherEventID,
            name: "Another Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        try database.write { db in
            try Event.insert { event }.execute(db)
            try Event.insert { otherEvent }.execute(db)
        }

        let color = try #require(OME.Color(rawValue: 0x336699))
        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let stageID = try database.write { db in
            try EventPlaceRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    name: "The Hollow",
                    kind: .known(.stage(.init(
                        color: color,
                        category: "main",
                        sortIndex: 1
                    )))
                ),
                createdAt: createdAt,
                in: db
            )
        }
        let categoryID = try database.write { db in
            try SocialCategoryRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    name: "Announcements",
                    defaultNotificationState: .known(.subscribed),
                    notificationsRequired: false
                ),
                createdAt: createdAt,
                in: db
            )
        }

        try database.read { db in
            let stageTerm = try #require(EventSearchTerm("hollow"))
            let stageMatches = try EventSearchIndex.results(
                matching: stageTerm,
                in: eventID,
                db: db
            )
            #expect(stageMatches.map(\.document.target) == [.stage(stageID)])
            #expect(try EventSearchIndex.results(
                matching: stageTerm,
                in: otherEventID,
                db: db
            ).isEmpty)

            let categoryTerm = try #require(EventSearchTerm("announcements"))
            let categoryMatches = try EventSearchIndex.results(
                matching: categoryTerm,
                in: eventID,
                db: db
            )
            #expect(categoryMatches.contains { $0.document.target == .channel(categoryID) })

            let dashboard = try EventSearchDashboard.fetch(eventID: eventID, db: db)
            #expect(dashboard.stageRows.map(\.id) == [stageID])
            #expect(dashboard.channelRows.map(\.id) == [categoryID])
            #expect(dashboard.featureRows.map(\.id).contains(EventSearchFeature.KnownID.schedule))
        }

        try database.write { db in
            try EventPlaceRecordEditing.update(
                stageID,
                eventID: eventID,
                fields: .init(
                    name: "The Meadow",
                    kind: .known(.stage(.init(
                        color: color,
                        category: "main",
                        sortIndex: 1
                    )))
                ),
                in: db
            )
            try SocialCategoryRecordEditing.delete(categoryID, eventID: eventID, in: db)
        }
        try database.read { db in
            let oldStageTerm = try #require(EventSearchTerm("hollow"))
            #expect(try EventSearchIndex.results(
                matching: oldStageTerm,
                in: eventID,
                db: db
            ).isEmpty)
            let renamedStageTerm = try #require(EventSearchTerm("meadow"))
            #expect(try EventSearchIndex.results(
                matching: renamedStageTerm,
                in: eventID,
                db: db
            ).map(\.document.target) == [.stage(stageID)])
            let deletedCategoryTerm = try #require(EventSearchTerm("announcements"))
            let deletedCategoryMatches = try EventSearchIndex.results(
                matching: deletedCategoryTerm,
                in: eventID,
                db: db
            )
            #expect(!deletedCategoryMatches.contains {
                $0.document.target == .channel(categoryID)
            })

            let dashboard = try EventSearchDashboard.fetch(eventID: eventID, db: db)
            #expect(dashboard.stageRows.map(\.stage.name) == ["The Meadow"])
            #expect(dashboard.channelRows.isEmpty)
        }
    }
}
