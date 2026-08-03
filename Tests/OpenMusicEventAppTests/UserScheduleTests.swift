import ATProto
import ComposableArchitecture2
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import OpenMusicEventAuthentication
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@Suite(.serialized, .tcaExhaustivity(.off))
struct UserScheduleTests {
    let organizerID = OMERecord.Organizer.ID("did:web:user-schedule-tests.example")!

    @Test
    func migrationPreservesShippedStateWhileApplyingAttendeeMigrations() async throws {
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
            #expect(selectedScheduleID == "published-friday")

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
        let performanceID = performanceLocalID("opening")
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
        let performanceID = performanceLocalID("opening")
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
        let performanceID = performanceLocalID("opening")

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
    func deletingLocalEventRemovesItsUserSchedulesMembershipsAndViewerState() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let scheduleID = UUID(0)

        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Festival",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil,
                    policies: nil,
                    reportingLinks: nil
                )
            }
            .execute(db)
            try UserSchedule.insert {
                UserSchedule(id: scheduleID, eventID: eventID, title: "Mine")
            }
            .execute(db)
            try UserSchedule.Performance.insert {
                UserSchedule.Performance(
                    scheduleID: scheduleID,
                    performanceID: performanceLocalID("opening")
                )
            }
            .execute(db)
            try EventViewerState.insert {
                EventViewerState(
                    id: eventID,
                    selectedUserScheduleID: scheduleID,
                    didInitializeUserSchedules: true
                )
            }
            .execute(db)

            try OMERecord.Event.find(eventID).delete().execute(db)
        }

        let remainingCounts = try await database.read { db in
            (
                try UserSchedule.fetchCount(db),
                try UserSchedule.Performance.fetchCount(db),
                try EventViewerState.fetchCount(db),
                try OMERecord.Event.fetchCount(db)
            )
        }
        #expect(remainingCounts.0 == 0)
        #expect(remainingCounts.1 == 0)
        #expect(remainingCounts.2 == 0)
        #expect(remainingCounts.3 == 0)
    }

    @Test
    func overlayKeepsFullPerformanceSetAndClassifiesMembershipWithoutGeometryChanges() {
        let includedID = performanceLocalID("included")
        let excludedID = performanceLocalID("excluded")
        let scheduleID = UUID(0)
        let overlay = UserScheduleOverlay(
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
            selectedScheduleID: scheduleID
        )

        let performanceIDs = [includedID, excludedID]
        #expect(performanceIDs.count == 2)
        #expect(overlay.isMember(performanceID: includedID))
        #expect(!overlay.isDimmed(performanceID: includedID))
        #expect(overlay.isDimmed(performanceID: excludedID))
        #expect(overlay.selectedTitle == "Mine")
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

    @MainActor
    @Test
    func firstMountCreatesMyScheduleOnceWithoutSelectingItOrRecreatingItAfterDeletion() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let userDID = try #require(DID("did:plc:attendee"))

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(userDID) }
            $0.uuid = .incrementing
        } operation: {
            let store = Store(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
            for _ in 0..<100 {
                let didInitialize = try? await database.read { db in
                    try EventViewerStateRequest(eventID: eventID)
                        .fetch(db)
                        .didInitializeUserSchedules
                }
                if didInitialize == true { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            _ = store
        }

        var result = try await database.read { db in
            (
                try UserSchedule.all(eventID: eventID).fetchAll(db),
                try EventViewerStateRequest(eventID: eventID).fetch(db)
            )
        }
        #expect(result.0.map(\.title) == ["My Schedule"])
        #expect(result.0.map(\.userDID) == [userDID])
        #expect(result.1.didInitializeUserSchedules)
        #expect(result.1.selectedUserScheduleID == nil)

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.uuid = .incrementing
        } operation: {
            let store = TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
            await store.dismount()
        }

        try await database.write { db in
            try UserSchedule
                .where { $0.eventID.eq(eventID) }
                .delete()
                .execute(db)
        }

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.uuid = .incrementing
        } operation: {
            let store = TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
            await store.dismount()
        }

        result = try await database.read { db in
            (
                try UserSchedule.all(eventID: eventID).fetchAll(db),
                try EventViewerStateRequest(eventID: eventID).fetch(db)
            )
        }
        #expect(result.0.isEmpty)
        #expect(result.1.didInitializeUserSchedules)
        #expect(result.1.selectedUserScheduleID == nil)

        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: UUID(42),
                    eventID: eventID,
                    title: "Later Schedule"
                )
            }
            .execute(db)
        }
        let laterSchedules = try await database.read { db in
            try UserSchedule.all(eventID: eventID).fetchAll(db)
        }
        #expect(laterSchedules.map(\.title) == ["Later Schedule"])
    }

    @MainActor
    @Test
    func selectionRestoresAndFallsBackWhenSelectedScheduleDisappears() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let scheduleID = UUID(0)

        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: scheduleID,
                    eventID: eventID,
                    title: "Jamie"
                )
            }
            .execute(db)
            try EventViewerState.insert {
                EventViewerState(
                    id: eventID,
                    selectedUserScheduleID: scheduleID,
                    didInitializeUserSchedules: true
                )
            }
            .execute(db)
        }

        let restoredState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }
        #expect(restoredState.userScheduleOverlay.selectedSchedule?.title == "Jamie")

        try await database.write { db in
            try UserSchedule.find(scheduleID).delete().execute(db)
        }

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            let store = TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
            await store.dismount()
        }

        let viewerState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }
        #expect(viewerState.selectedUserScheduleID == nil)
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

    func eventID(_ value: String) -> OMERecord.Event.ID {
        OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(
                rawValue: ATProto.Record.Key(rawValue: value)
            )
        )
    }

    func performanceLocalID(
        _ value: String
    ) -> OMERecord.ID<OMERecord.Performance> {
        OMERecord.ID<OMERecord.Performance>(
            rawValue: ATProto.Record.Key(rawValue: value)
        )
    }
}
