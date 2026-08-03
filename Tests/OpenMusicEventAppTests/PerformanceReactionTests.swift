import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@Suite(.serialized)
struct PerformanceReactionTests {
    let organizerID = OMERecord.Organizer.ID("did:web:reactions.example")!

    var eventID: OMERecord.Event.ID {
        OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: localID("event")
        )
    }

    var performanceID: OMERecord.Performance.ID {
        OMERecord.Performance.ID(
            organizerID: organizerID,
            eventID: eventID.eventID,
            performanceID: localID("performance")
        )
    }

    @Test
    func independentTogglesRetainHistoricalUsageAndRefreshTimestamps() async throws {
        let database = try preparedDatabase()
        let firstID = UUID(0)
        let secondID = UUID(1)
        let thirdID = UUID(2)
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        let thirdDate = Date(timeIntervalSince1970: 3_000)

        try await database.write { db in
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .heart,
                id: firstID,
                date: firstDate,
                in: db
            )
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .fire,
                id: secondID,
                date: secondDate,
                in: db
            )
        }

        var reactions = try await database.read { db in
            try PerformanceReaction.forPerformance(performanceID: performanceID).fetchAll(db)
        }
        #expect(reactions.map(\.emoji) == [.heart, .fire])
        #expect(reactions.map(\.reactedAt) == [firstDate, secondDate])

        try await database.write { db in
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .heart,
                id: UUID(99),
                date: Date(timeIntervalSince1970: 9_999),
                in: db
            )
        }

        reactions = try await database.read { db in
            try PerformanceReaction.forPerformance(performanceID: performanceID).fetchAll(db)
        }
        #expect(reactions.map(\.emoji) == [.fire])

        try await database.write { db in
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .heart,
                id: thirdID,
                date: thirdDate,
                in: db
            )
        }

        let result = try await database.read { db in
            (
                try PerformanceReaction.forPerformance(performanceID: performanceID).fetchAll(db),
                try PerformanceReactionEmojiUsage.ranked.fetchAll(db)
            )
        }
        let heart = try #require(result.0.first { $0.emoji == .heart })
        let heartUsage = try #require(result.1.first { $0.emoji == .heart })
        let fireUsage = try #require(result.1.first { $0.emoji == .fire })
        #expect(heart.id == thirdID)
        #expect(heart.reactedAt == thirdDate)
        #expect(heartUsage.selectionCount == 2)
        #expect(heartUsage.lastUsedAt == thirdDate)
        #expect(fireUsage.selectionCount == 1)
    }

    @Test
    func learnedOrderingFillsFiveWhileKeepingEverySelectionRemovable() throws {
        let custom = try #require(PerformanceReaction.Emoji(rawValue: "🪩"))
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let usage = [
            PerformanceReactionEmojiUsage(
                emoji: .fire,
                selectionCount: 4,
                lastUsedAt: newer
            ),
            PerformanceReactionEmojiUsage(
                emoji: custom,
                selectionCount: 20,
                lastUsedAt: older
            ),
        ]

        let learned = PerformanceReaction.menuEmojis(
            selected: [],
            usage: usage
        )
        #expect(learned.count == 5)
        #expect(learned.first == custom)
        #expect(learned.contains(.fire))

        let selected = [custom, .heart, .fire, .eyes, .raisedHands, .explodingHead]
        let withManySelections = PerformanceReaction.menuEmojis(
            selected: selected,
            usage: []
        )
        #expect(withManySelections == selected)
    }

    @Test
    func addingAnAlreadySelectedCustomEmojiDoesNotTeachUsageAgain() async throws {
        let database = try preparedDatabase()
        let custom = try #require(PerformanceReaction.Emoji(rawValue: "🪩"))

        try await database.write { db in
            try PerformanceReaction.add(
                performanceID: performanceID,
                emoji: custom,
                id: UUID(30),
                date: Date(timeIntervalSince1970: 30),
                in: db
            )
            try PerformanceReaction.add(
                performanceID: performanceID,
                emoji: custom,
                id: UUID(31),
                date: Date(timeIntervalSince1970: 31),
                in: db
            )
        }

        let result = try await database.read { db in
            (
                try PerformanceReaction.fetchAll(db),
                try PerformanceReactionEmojiUsage.fetchAll(db)
            )
        }
        #expect(result.0.map(\.id) == [UUID(30)])
        #expect(result.1.map(\.selectionCount) == [1])
    }

    @Test(
        arguments: ["", "fire", "🔥❤️", "1", "A", "  "]
    )
    func invalidEmojiValuesAreRejected(_ value: String) {
        #expect(PerformanceReaction.Emoji(rawValue: value) == nil)
    }

    @Test(
        arguments: ["❤️", "🔥", "👀", "🙌", "🤯", "🪩", "👩🏽‍🎤", "🇨🇦"]
    )
    func oneEmojiGraphemeIsAccepted(_ value: String) {
        #expect(PerformanceReaction.Emoji(rawValue: value)?.rawValue == value)
    }

    @Test
    func forwardMigrationPreservesInstalledDataAndRemovesLegacyPreferences() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add many-stage schedule orientation")

        try await database.write { db in
            try db.execute(
                sql: #"INSERT INTO "app.openmusicevent.organizer" (id) VALUES (?)"#,
                arguments: [organizerID.description]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.event" (organizerID, eventID, name, timeZone)
                    VALUES (?, ?, 'Sentinel Event', 'America/Denver')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.schedule" (organizerID, eventID, scheduleID, date, customTitle)
                    VALUES (?, ?, 'sentinel-schedule', '2026-07-28', 'Sentinel Schedule')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO contributorPreferences
                      (organizerID, eventID, contributorID, isFavorite)
                    VALUES (?, ?, 'sentinel-contributor', 1)
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO performancePreferences
                      (organizerID, eventID, performanceID, interested, seen)
                    VALUES (?, ?, 'sentinel-performance', 1, 1)
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
        }

        try migrator.migrate(database)

        let migrated = try await database.read { db in
            let scheduleViewerColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('scheduleViewerState')"
            )
            return (
                try db.tableExists("performanceReactions"),
                try db.tableExists("performanceReactionEmojiUsage"),
                try db.tableExists("performancePreferences"),
                scheduleViewerColumns,
                try String.fetchOne(db, sql: #"SELECT name FROM "app.openmusicevent.event""#),
                try String.fetchOne(db, sql: #"SELECT customTitle FROM "app.openmusicevent.schedule""#),
                try Int.fetchOne(db, sql: "SELECT isFavorite FROM contributorPreferences")
            )
        }
        #expect(migrated.0)
        #expect(migrated.1)
        #expect(!migrated.2)
        #expect(!migrated.3.contains("filteringInterested"))
        #expect(migrated.3.contains("filteringFavorites"))
        #expect(migrated.4 == "Sentinel Event")
        #expect(migrated.5 == "Sentinel Schedule")
        #expect(migrated.6 == 1)
    }

    @Test
    func failedMigrationLeavesInstalledDatabaseIntact() async throws {
        let database = try preparedDatabase()
        try await database.write { db in
            try db.execute(sql: #"INSERT INTO "app.openmusicevent.organizer" (id) VALUES (?)"#, arguments: [organizerID.description])
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.event" (organizerID, eventID, name, timeZone)
                    VALUES (?, ?, 'Before Failure', 'America/Denver')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
        }

        var failingMigrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &failingMigrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &failingMigrator)
        failingMigrator.registerMigration("Expected reaction migration failure") { db in
            try db.execute(sql: #"UPDATE "app.openmusicevent.event" SET name = 'Damaged'"#)
            try db.execute(sql: "CREATE TABLE shouldRollBack (id INTEGER)")
            throw ExpectedMigrationError()
        }

        #expect(throws: ExpectedMigrationError.self) {
            try failingMigrator.migrate(database)
        }

        let installedState = try await database.read { db in
            (
                try String.fetchOne(db, sql: #"SELECT name FROM "app.openmusicevent.event""#),
                try db.tableExists("shouldRollBack")
            )
        }
        #expect(installedState.0 == "Before Failure")
        #expect(!installedState.1)
    }

    @Test
    func reactionSurvivesPerformanceReplacement() async throws {
        let database = try preparedDatabase()
        try await seedPerformance(in: database, title: "Original")
        try await database.write { db in
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .eyes,
                id: UUID(10),
                date: Date(timeIntervalSince1970: 10),
                in: db
            )
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO "app.openmusicevent.performance"
                      (organizerID, eventID, performanceID, stageID, scheduleID,
                       startTime, endTime, title, recordings)
                    VALUES (?, ?, ?, 'stage', 'schedule', ?, ?, 'Refreshed', '[]')
                    """,
                arguments: [
                    organizerID.description,
                    eventID.eventID.rawValue.rawValue,
                    performanceID.performanceID.rawValue.rawValue,
                    "1970-01-01 00:01:40.000",
                    "1970-01-01 00:03:20.000",
                ]
            )
        }

        let reaction = try await database.read { db in
            try PerformanceReaction.forPerformance(performanceID: performanceID).fetchOne(db)
        }
        #expect(reaction?.emoji == .eyes)
    }

    @Test
    func explicitEventDeletionRemovesActiveReactionsButKeepsUsage() async throws {
        let database = try preparedDatabase()
        try await seedPerformance(in: database, title: "Delete Me")
        try await database.write { db in
            try PerformanceReaction.toggle(
                performanceID: performanceID,
                emoji: .raisedHands,
                id: UUID(20),
                date: Date(timeIntervalSince1970: 20),
                in: db
            )
            try OMERecord.Event.find(eventID).delete().execute(db)
        }

        let result = try await database.read { db in
            (
                try PerformanceReaction.fetchCount(db),
                try PerformanceReactionEmojiUsage.fetchCount(db)
            )
        }
        #expect(result.0 == 0)
        #expect(result.1 == 1)
    }

    @Test @MainActor
    func scheduleDetailAndViewerActionsShareStateWithoutTriggeringNavigation() async throws {
        let database = try preparedDatabase()
        let reactionDate = Date(timeIntervalSince1970: 40)
        let userDID = try #require(DID("did:plc:reaction-user"))

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(reactionDate)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(userDID) }
            $0.uuid = .incrementing
        } operation: {
            let scheduleStore = Store(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }
            let detailStore = Store(
                initialState: PerformanceDetail.State(
                    performanceID: performanceID.performanceID,
                    eventID: eventID
                )
            ) {
                PerformanceDetail()
            }
            let eventViewerStore = Store(
                initialState: EventViewer.State(eventID: eventID)
            ) {
                EventViewer()
            }

            await scheduleStore.send(
                .reactionButtonTapped(performanceID, .heart)
            )?.value
            let didNavigate = scheduleStore.destination != nil
            #expect(!didNavigate)

            let detailReactions = try await database.read { db in
                try PerformanceReaction
                    .forPerformance(performanceID: performanceID)
                    .fetchAll(db)
            }
            #expect(detailReactions.map(\.emoji) == [.heart])

            await detailStore.send(.reactionButtonTapped(.fire))?.value
            await eventViewerStore.send(
                .reactionButtonTapped(performanceID, .eyes)
            )?.value

            let scheduleReactions = try await database.read { db in
                try PerformanceReaction
                    .forEvent(eventID: eventID)
                    .fetchAll(db)
            }
            expectNoDifference(
                Set(scheduleReactions.map(\.emoji)),
                [.heart, .fire, .eyes]
            )
            #expect(Set(scheduleReactions.compactMap(\.userDID)) == [userDID])
        }
    }

    func preparedDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    func seedPerformance(
        in database: any DatabaseWriter,
        title: String
    ) async throws {
        try await database.write { db in
            try db.execute(sql: #"INSERT INTO "app.openmusicevent.organizer" (id) VALUES (?)"#, arguments: [organizerID.description])
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.event" (organizerID, eventID, name, timeZone)
                    VALUES (?, ?, 'Reaction Event', 'America/Denver')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.stage" (organizerID, eventID, stageID, name, color)
                    VALUES (?, ?, 'stage', 'Stage', 0)
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.schedule" (organizerID, eventID, scheduleID, date)
                    VALUES (?, ?, 'schedule', '2026-07-28')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.performance"
                      (organizerID, eventID, performanceID, stageID, scheduleID,
                       startTime, endTime, title, recordings)
                    VALUES (?, ?, ?, 'stage', 'schedule', ?, ?, ?, '[]')
                    """,
                arguments: [
                    organizerID.description,
                    eventID.eventID.rawValue.rawValue,
                    performanceID.performanceID.rawValue.rawValue,
                    "1970-01-01 00:01:40.000",
                    "1970-01-01 00:03:20.000",
                    title,
                ]
            )
        }
    }

    func localID<T>(_ value: String) -> OMERecord.ID<T> {
        OMERecord.ID<T>(rawValue: ATProto.Record.Key(rawValue: value))
    }
}

private struct ExpectedMigrationError: Error {}

private extension UUID {
    init(_ value: UInt8) {
        self.init(uuid: (
            0, 0, 0, 0,
            0, 0,
            0, 0,
            0, 0,
            0, 0,
            0, 0, 0, value
        ))
    }
}
