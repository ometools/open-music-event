import ATProto
import ComposableArchitecture2
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@Suite(.serialized, .tcaExhaustivity(.off))
struct UserScheduleTests {
    let organizerID = DID("did:web:user-schedule-tests.example")!

    @Test
    func canonicalScheduleMigrationKeepsRowsAndMemberships() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Use canonical Event IDs for viewer state")

        let eventID = eventID("festival")
        let scheduleID = UUID(0)
        let otherScheduleID = UUID(1)
        let canonicalScheduleID = UUID(2)
        let otherOrganizerID = DID("did:web:another-user-schedule-tests.example")!
        let performanceID = programItemID("opening")
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "userSchedules" ("id", "organizerID", "eventID", "title")
                    VALUES (?, ?, ?, ?), (?, ?, ?, ?), (?, ?, ?, ?)
                    """,
                arguments: [
                    scheduleID.uuidString,
                    organizerID.description,
                    "festival",
                    "My Schedule",
                    otherScheduleID.uuidString,
                    otherOrganizerID.description,
                    "festival",
                    "My Schedule",
                    canonicalScheduleID.uuidString,
                    organizerID.description,
                    eventID.description,
                    "My Schedule",
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "userSchedulePerformances" ("scheduleID", "performanceID")
                    VALUES (?, ?), (?, ?)
                    """,
                arguments: [
                    scheduleID.uuidString, performanceID.description,
                    otherScheduleID.uuidString, performanceID.description,
                ]
            )
        }

        try migrator.migrate(database)

        try await database.read { db in
            let columns = try String.fetchAll(
                db, sql: #"SELECT "name" FROM pragma_table_info('userSchedules')"#
            )
            #expect(!columns.contains("organizerID"))
            #expect(
                try UserSchedule.find(scheduleID).fetchOne(db)?.eventID.description
                    == "at://\(organizerID)/app.openmusicevent.event/festival"
            )
            #expect(
                try UserSchedule.find(otherScheduleID).fetchOne(db)?.eventID.description
                    == "at://\(otherOrganizerID)/app.openmusicevent.event/festival"
            )
            #expect(try UserSchedule.find(canonicalScheduleID).fetchOne(db)?.eventID == eventID)
            #expect(try UserSchedule.Performance.fetchAll(db).count == 2)
            #expect(
                try UserSchedule.Performance.fetchAll(db).allSatisfy {
                    $0.id.performanceID == performanceID
                }
            )
        }
    }

    @Test
    func migrationReplacesLegacyViewerSelectionWhileApplyingAttendeeMigrations() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add many-stage schedule orientation")

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "eventViewerState" (
                      "organizerID", "eventID", "selectedScheduleID"
                    ) VALUES (?, ?, ?)
                    """,
                arguments: [
                    organizerID.description,
                    "festival",
                    "published-friday",
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "performancePreferences" (
                      "organizerID", "eventID", "performanceID", "interested", "seen"
                    ) VALUES (?, ?, ?, 1, 1)
                    """,
                arguments: [
                    organizerID.description,
                    "festival",
                    "opening",
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "contributorPreferences" (
                      "organizerID", "eventID", "contributorID", "isFavorite"
                    ) VALUES (?, ?, ?, 1)
                    """,
                arguments: [
                    organizerID.description,
                    "festival",
                    "artist",
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "scheduleViewerState" (
                      "organizerID", "eventID", "category",
                      "filteringFavorites", "filteringInterested"
                    ) VALUES (?, ?, ?, 1, 1)
                    """,
                arguments: [
                    organizerID.description,
                    "festival",
                    "schedule",
                ]
            )
        }

        try migrator.migrate(database)

        try await database.read { db in
            let columns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('eventViewerState')"#
            )
            #expect(columns.contains("selectedUserScheduleID"))
            #expect(columns.contains("didInitializeUserSchedules"))

            let selectedScheduleID = try String.fetchOne(
                db,
                sql: #"SELECT "selectedScheduleID" FROM "eventViewerState""#
            )
            #expect(selectedScheduleID == nil)

            #expect(!(try db.tableExists("performancePreferences")))

            let favorite = try Int.fetchOne(
                db,
                sql: #"SELECT "isFavorite" FROM "contributorPreferences""#
            )
            #expect(favorite == 1)

            let scheduleViewerColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('scheduleViewerState')"#
            )
            #expect(scheduleViewerColumns.contains("filteringFavorites"))
            #expect(!scheduleViewerColumns.contains("filteringInterested"))
        }
    }

    @Test
    func failedMigrationRollsBackAndLeavesSentinelRecoverable() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add many-stage schedule orientation")

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "eventViewerState" (
                      "organizerID", "eventID", "selectedScheduleID"
                    ) VALUES (?, ?, ?)
                    """,
                arguments: [organizerID.description, "festival", "sentinel"]
            )
            try db.execute(sql: #"CREATE TABLE "userSchedulePerformances" ("sentinel" TEXT)"#)
        }

        #expect(throws: (any Error).self) {
            try migrator.migrate(database)
        }

        try await database.read { db in
            #expect(!(try db.tableExists("userSchedules")))
            #expect(try db.tableExists("userSchedulePerformances"))
            let selectedScheduleID = try String.fetchOne(
                db,
                sql: #"SELECT "selectedScheduleID" FROM "eventViewerState""#
            )
            #expect(selectedScheduleID == "sentinel")
            let columns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('eventViewerState')"#
            )
            #expect(!columns.contains("selectedUserScheduleID"))
        }
    }

    @Test
    func schedulesEnforceNamesRoundTripDIDAndPreserveUnavailableMemberships() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let otherEventID = self.eventID("another-festival")
        let scheduleID = UUID(0)
        let secondScheduleID = UUID(1)
        let performanceID = programItemID("opening")
        let userDID = try #require(DID("did:plc:attendee"))

        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: scheduleID,
                    eventID: eventID,
                    title: "My Schedule",
                    userDID: userDID
                )
            }
            .execute(db)
            try UserSchedule.insert {
                UserSchedule(
                    id: secondScheduleID,
                    eventID: eventID,
                    title: "Jamie"
                )
            }
            .execute(db)
            try UserSchedule.insert {
                UserSchedule(
                    id: UUID(4),
                    eventID: otherEventID,
                    title: "MY SCHEDULE"
                )
            }
            .execute(db)

            try UserSchedule.Performance.insert {
                [
                    UserSchedule.Performance(
                        scheduleID: scheduleID,
                        performanceID: performanceID
                    ),
                    UserSchedule.Performance(
                        scheduleID: secondScheduleID,
                        performanceID: performanceID
                    ),
                ]
            }
            .execute(db)
        }

        let storedSchedule = try await database.read { db in
            try UserSchedule.find(scheduleID).fetchOne(db)
        }
        #expect(storedSchedule?.title == "My Schedule")
        #expect(storedSchedule?.userDID == userDID)

        let memberships = try await database.read { db in
            try UserSchedule.Performance.fetchAll(db)
        }
        #expect(memberships.count == 2)
        #expect(memberships.allSatisfy { $0.id.performanceID == performanceID })

        await #expect(throws: (any Error).self) {
            try await database.write { db in
                try UserSchedule.insert {
                    UserSchedule(
                        id: UUID(2),
                        eventID: eventID,
                        title: "my schedule"
                    )
                }
                .execute(db)
            }
        }

        await #expect(throws: (any Error).self) {
            try await database.write { db in
                try UserSchedule.insert {
                    UserSchedule(
                        id: UUID(3),
                        eventID: eventID,
                        title: " Padded "
                    )
                }
                .execute(db)
            }
        }

        #expect(try UserSchedule.normalizedTitle("  Jamie  ") == "Jamie")
        #expect(throws: UserSchedule.ValidationError.self) {
            try UserSchedule.normalizedTitle(" \n ")
        }
        #expect(throws: UserSchedule.ValidationError.self) {
            try UserSchedule.normalizedTitle(String(repeating: "a", count: 81))
        }
    }

    @Test
    func duplicateMembershipIsPreventedAndRemovalIsIdempotent() async throws {
        let database = try makePreparedDatabase()
        let scheduleID = UUID(0)
        let performanceID = programItemID("opening")
        let membership = UserSchedule.Performance(
            scheduleID: scheduleID,
            performanceID: performanceID
        )

        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: scheduleID,
                    eventID: eventID("festival"),
                    title: "My Schedule"
                )
            }
            .execute(db)
            try UserSchedule.Performance.insert { membership }.execute(db)
        }

        await #expect(throws: (any Error).self) {
            try await database.write { db in
                try UserSchedule.Performance.insert { membership }.execute(db)
            }
        }

        try await database.write { db in
            try UserSchedule.Performance.find(membership.id).delete().execute(db)
            try UserSchedule.Performance.find(membership.id).delete().execute(db)
        }

        let count = try await database.read { db in
            try UserSchedule.Performance.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test
    func deletingScheduleCascadesMembershipWithoutTouchingOtherSchedule() async throws {
        let database = try makePreparedDatabase()
        let firstID = UUID(0)
        let secondID = UUID(1)
        let performanceID = programItemID("opening")

        try await database.write { db in
            try UserSchedule.insert {
                [
                    UserSchedule(id: firstID, eventID: eventID("festival"), title: "Mine"),
                    UserSchedule(id: secondID, eventID: eventID("festival"), title: "Friend"),
                ]
            }
            .execute(db)
            try UserSchedule.Performance.insert {
                [
                    UserSchedule.Performance(scheduleID: firstID, performanceID: performanceID),
                    UserSchedule.Performance(scheduleID: secondID, performanceID: performanceID),
                ]
            }
            .execute(db)
            try UserSchedule.find(firstID).delete().execute(db)
        }

        let remaining = try await database.read { db in
            try UserSchedule.Performance.fetchAll(db)
        }
        #expect(remaining.map(\.id.scheduleID) == [secondID])
    }

    @Test
    func overlayKeepsFullPerformanceSetAndClassifiesMembershipWithoutGeometryChanges() {
        let includedID = programItemID("included")
        let excludedID = programItemID("excluded")
        let scheduleID = UUID(0)
        let eventScheduleOverlay = UserScheduleOverlay(
            schedules: [
                UserSchedule(
                    id: scheduleID,
                    eventID: eventID("festival"),
                    title: "Mine"
                )
            ],
            memberships: [
                UserSchedule.Performance(
                    scheduleID: scheduleID,
                    performanceID: includedID
                )
            ],
            selectedScheduleID: nil
        )

        let performanceIDs = [includedID, excludedID]
        #expect(performanceIDs.count == 2)
        #expect(eventScheduleOverlay.showsMembershipIndicator(performanceID: includedID))
        #expect(!eventScheduleOverlay.showsMembershipIndicator(performanceID: excludedID))
        #expect(!eventScheduleOverlay.isDimmed(performanceID: includedID))
        #expect(!eventScheduleOverlay.isDimmed(performanceID: excludedID))

        let personalScheduleOverlay = UserScheduleOverlay(
            schedules: eventScheduleOverlay.schedules,
            memberships: eventScheduleOverlay.memberships,
            selectedScheduleID: scheduleID
        )
        #expect(personalScheduleOverlay.isMember(performanceID: includedID))
        #expect(!personalScheduleOverlay.showsMembershipIndicator(performanceID: includedID))
        #expect(!personalScheduleOverlay.isDimmed(performanceID: includedID))
        #expect(personalScheduleOverlay.isDimmed(performanceID: excludedID))
        #expect(personalScheduleOverlay.selectedTitle == "Mine")
    }

    @MainActor
    @Test
    func creatingScheduleStoresSelectedAccountDIDAndRenamePreservesIt() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let aliceDID = try #require(DID("did:plc:alice"))
        let bobDID = try #require(DID("did:plc:bob"))

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(aliceDID) }
            $0.uuid = .constant(UUID(0))
        } operation: {
            var state = UserScheduleForm.State(eventID: eventID)
            state.title = "Alice's Schedule"
            let store = Store(initialState: state) {
                UserScheduleForm()
            }
            let task = store.send(.saveButtonTapped)
            await task?.value
        }

        let createdSchedule = try await database.read { db in
            try UserSchedule.find(UUID(0)).fetchOne(db)
        }
        #expect(createdSchedule?.userDID == aliceDID)

        let schedule = try #require(createdSchedule)
        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(bobDID) }
        } operation: {
            var state = UserScheduleForm.State(eventID: eventID, schedule: schedule)
            state.title = "Renamed Schedule"
            let store = Store(initialState: state) {
                UserScheduleForm()
            }
            let task = store.send(.saveButtonTapped)
            await task?.value
        }

        let renamedSchedule = try await database.read { db in
            try UserSchedule.find(UUID(0)).fetchOne(db)
        }
        #expect(renamedSchedule?.title == "Renamed Schedule")
        #expect(renamedSchedule?.userDID == aliceDID)
    }

    func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    func eventID(_ value: String) -> Event.ID {
        let rkey: String
        switch value {
        case "festival": rkey = "3mrdbziccpcah"
        case "another-festival": rkey = "3mrdbziccpcai"
        default: preconditionFailure("Unexpected test event")
        }
        return Event.ID(
            "at://\(organizerID)/events.openmusic.event/\(rkey)"
        )!
    }

    func programItemID(_ value: String) -> ProgramItem.ID {
        let rkey: String
        switch value {
        case "opening": rkey = "3mrdbziccpcak"
        case "included": rkey = "3mrdbziccpcam"
        case "excluded": rkey = "3mrdbziccpcan"
        default: preconditionFailure("Unexpected test program item")
        }
        return ProgramItem.ID(
            "at://\(organizerID)/events.openmusic.programItem/\(rkey)"
        )!
    }
}
