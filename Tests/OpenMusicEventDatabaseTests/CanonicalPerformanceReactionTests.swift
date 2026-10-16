import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalPerformanceReactionTests {
    @Test
    func eventReactionsFollowProgramItemRecordURIs() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let firstEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let secondEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"
        ))
        let firstProgramID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcaj"
        ))
        let secondProgramID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcak"
        ))
        let firstItemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcal"
        ))
        let secondItemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcam"
        ))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))

        var firstEvent = try Event(
            id: firstEventID,
            name: "First Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        firstEvent.programs = [firstProgramID]
        var secondEvent = try Event(
            id: secondEventID,
            name: "Second Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        secondEvent.programs = [secondProgramID]
        let firstProgram = try Program(
            id: firstProgramID,
            event: firstEventID,
            title: "Music",
            createdAt: "2026-09-01T12:00:00Z",
            eventPlaces: []
        )
        let secondProgram = try Program(
            id: secondProgramID,
            event: secondEventID,
            title: "Workshops",
            createdAt: "2026-09-01T12:00:00Z",
            eventPlaces: []
        )
        let firstItem = try ProgramItem(
            id: firstItemID,
            event: firstEventID,
            program: firstProgramID,
            title: "Opening Set",
            createdAt: "2026-09-01T12:00:00Z"
        )
        let secondItem = try ProgramItem(
            id: secondItemID,
            event: secondEventID,
            program: secondProgramID,
            title: "Workshop",
            createdAt: "2026-09-01T12:00:00Z"
        )

        try database.write { db in
            try Event.insert { [firstEvent, secondEvent] }.execute(db)
            try Program.insert { [firstProgram, secondProgram] }.execute(db)
            try ProgramItem.insert { [firstItem, secondItem] }.execute(db)
            try db.execute(sql: """
                CREATE TABLE "performanceReactions" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "performanceID" TEXT NOT NULL,
                  "emoji" TEXT NOT NULL,
                  "reactedAt" TEXT NOT NULL,
                  "userDID" TEXT,
                  UNIQUE ("performanceID", "emoji")
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE "performanceReactionEmojiUsage" (
                  "emoji" TEXT PRIMARY KEY NOT NULL,
                  "selectionCount" INTEGER NOT NULL,
                  "lastUsedAt" TEXT NOT NULL
                ) STRICT
                """)
            try PerformanceReaction.toggle(
                performanceID: firstItemID,
                emoji: .heart,
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                date: Date(timeIntervalSince1970: 1),
                in: db
            )
            try PerformanceReaction.toggle(
                performanceID: secondItemID,
                emoji: .fire,
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                date: Date(timeIntervalSince1970: 2),
                in: db
            )
        }

        let firstEventReactions = try database.read {
            try PerformanceReaction.forEvent(eventID: firstEventID).fetchAll($0)
        }
        let secondEventReactions = try database.read {
            try PerformanceReaction.forEvent(eventID: secondEventID).fetchAll($0)
        }
        #expect(firstEventReactions.map(\.performanceID) == [firstItemID])
        #expect(secondEventReactions.map(\.performanceID) == [secondItemID])
    }
}
