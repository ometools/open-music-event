import ATProto
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp

struct AppStateMigrationTests {
    @Test
    func viewerStateUpgradeUsesCanonicalIDsAndPreservesOtherDatabaseData() throws {
        let database = try DatabaseQueue(path: ":memory:")
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Store selected canonical event URI")

        try database.write { db in
            try #sql("CREATE TABLE upgradeSentinel (value TEXT NOT NULL)").execute(db)
            try #sql("INSERT INTO upgradeSentinel VALUES ('keep this')").execute(db)
            try #sql("""
                INSERT INTO eventViewerState (organizerID, eventID, selectedScheduleID)
                VALUES ('did:plc:organizer', 'old-event', NULL)
                """).execute(db)
            try #sql("""
                INSERT INTO scheduleViewerState (organizerID, eventID, category)
                VALUES ('did:plc:organizer', 'old-event', 'schedule')
                """).execute(db)
        }

        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let viewerState = EventDetailState(id: eventID, didInitializeUserSchedules: true)
        let scheduleState = ScheduleListState(
            id: .init(eventID: eventID, category: "schedule"),
            filteringFavorites: true
        )
        try database.write { db in
            try EventDetailState.insert { viewerState }.execute(db)
            try ScheduleListState.insert { scheduleState }.execute(db)
        }

        let savedViewer = try database.read { db in
            try EventDetailState.where { $0.id.eq(eventID) }.fetchOne(db)
        }
        #expect(savedViewer == viewerState)
        let savedScheduleID = try database.read { db in
            try #sql("SELECT eventID FROM scheduleViewerState", as: String.self).fetchOne(db)
        }
        #expect(savedScheduleID == eventID.description)
        let sentinel = try database.read { db in
            try #sql("SELECT value FROM upgradeSentinel", as: String.self).fetchOne(db)
        }
        #expect(sentinel == "keep this")
        let viewerRowCount = try database.read { db in
            try #sql("SELECT count(*) FROM eventViewerState", as: Int.self).fetchOne(db)
        }
        let scheduleRowCount = try database.read { db in
            try #sql("SELECT count(*) FROM scheduleViewerState", as: Int.self).fetchOne(db)
        }
        #expect(viewerRowCount == 1)
        #expect(scheduleRowCount == 1)
    }

    @Test
    func legacySelectionSurvivesWhileNewSelectionUsesCanonicalURI() throws {
        let database = try DatabaseQueue(path: ":memory:")
        try database.write { db in
            try #sql("""
                CREATE TABLE appState (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  organizerID TEXT,
                  eventID TEXT
                ) STRICT
                """).execute(db)
            try #sql("""
                INSERT INTO appState (id, organizerID, eventID)
                VALUES (1, 'did:plc:organizer', 'old-event')
                """).execute(db)
        }

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let canonicalID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        try database.write { db in
            try AppState.update {
                $0.selectedEventURI = #bind(canonicalID)
            }.execute(db)
        }

        let selection = try database.read { db in
            try AppState.find(1).fetchOne(db)?.selectedEventID
        }
        #expect(selection == canonicalID)
        let previousOrganizer = try database.read { db in
            try #sql("SELECT organizerID FROM appState", as: String.self).fetchOne(db)
        }
        let previousEvent = try database.read { db in
            try #sql("SELECT eventID FROM appState", as: String.self).fetchOne(db)
        }
        #expect(previousOrganizer == "did:plc:organizer")
        #expect(previousEvent == "old-event")
    }
}
