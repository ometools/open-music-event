import ATProto
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalEventSearchTests {
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
