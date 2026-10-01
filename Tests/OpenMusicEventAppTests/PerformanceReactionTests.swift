import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@Suite(.serialized)
struct PerformanceReactionTests {
    let organizerID = DID("did:web:reactions.example")!
    let eventID = Event.ID(
        "at://did:web:reactions.example/events.openmusic.event/3mrdbziccpcae"
    )!
    let performanceID = ProgramItem.ID(
        "at://did:web:reactions.example/events.openmusic.programItem/3mrdbziccpcae"
    )!
    let scheduleID = Schedule.ID(
        "at://did:web:reactions.example/events.openmusic.schedule/3mrdbziccpcae"
    )!
    let stageID = EventPlace.ID(
        "at://did:web:reactions.example/events.openmusic.eventPlace/3mrdbziccpcae"
    )!
    let programID = Program.ID(
        "at://did:web:reactions.example/events.openmusic.program/3mrdbziccpcae"
    )!

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
    func reactionMenuTriggerKeepsEverySelectedReactionInOrder() {
        let selected: [PerformanceReaction.Emoji] = [
            .heart,
            .fire,
            .eyes,
            .raisedHands,
            .explodingHead,
        ]
        let reactions = selected.enumerated().map { offset, emoji in
            PerformanceReaction(
                id: UUID(offset),
                performanceID: performanceID,
                emoji: emoji,
                reactedAt: Date(timeIntervalSince1970: TimeInterval(offset))
            )
        }
        let context = PerformanceReactionMenuContext(reactions: reactions)

        #expect(context.selectedEmojis(for: performanceID) == selected)
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
                arguments: [organizerID.description, "event"]
            )
            try db.execute(
                sql: """
                    INSERT INTO "app.openmusicevent.schedule" (organizerID, eventID, scheduleID, date, customTitle)
                    VALUES (?, ?, 'sentinel-schedule', '2026-07-28', 'Sentinel Schedule')
                    """,
                arguments: [organizerID.description, "event"]
            )
            try db.execute(
                sql: """
                    INSERT INTO contributorPreferences
                      (organizerID, eventID, contributorID, isFavorite)
                    VALUES (?, ?, 'sentinel-contributor', 1)
                    """,
                arguments: [organizerID.description, "event"]
            )
            try db.execute(
                sql: """
                    INSERT INTO performancePreferences
                      (organizerID, eventID, performanceID, interested, seen)
                    VALUES (?, ?, 'sentinel-performance', 1, 1)
                    """,
                arguments: [organizerID.description, "event"]
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
                arguments: [organizerID.description, "event"]
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
            var item = try #require(try ProgramItem.find(performanceID).fetchOne(db))
            item.title = "Refreshed"
            try ProgramItem.upsert { item }.execute(db)
        }

        let reaction = try await database.read { db in
            try PerformanceReaction.forPerformance(performanceID: performanceID).fetchOne(db)
        }
        #expect(reaction?.emoji == .eyes)
    }

    @Test @MainActor
    func scheduleDetailAndViewerActionsShareStateWithoutTriggeringNavigation() async throws {
        let database = try preparedDatabase()
        try await seedPerformance(in: database, title: "Live")
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
                    performanceID: performanceID,
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
        let eventID = self.eventID
        let stageID = self.stageID
        let scheduleID = self.scheduleID
        let programID = self.programID
        let performanceID = self.performanceID
        let date = try #require(LocalDate("2026-07-28"))
        try await database.write { db in
            var event = try Event(
                id: eventID,
                name: "Reaction Event",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt
            )
            event.schedules = [scheduleID]
            event.programs = [programID]
            try Event.insert { event }.execute(db)

            var stage = try EventPlace(
                id: stageID,
                event: eventID,
                name: "Stage",
                createdAt: "2026-09-01T12:00:00Z"
            )
            stage.kind = .known(.stage(EventPlace.Kind.Stage()))
            try EventPlace.insert { stage }.execute(db)

            let schedule = try Schedule(
                id: scheduleID,
                event: eventID,
                date: date,
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Schedule.insert { schedule }.execute(db)

            let program = try Program(
                id: programID,
                event: eventID,
                title: "Main Schedule",
                createdAt: "2026-09-01T12:00:00Z",
                eventPlaces: [stageID]
            )
            try Program.insert { program }.execute(db)

            var item = try ProgramItem(
                id: performanceID,
                event: eventID,
                program: programID,
                title: title,
                createdAt: "2026-09-01T12:00:00Z"
            )
            item.schedule = scheduleID
            item.eventPlace = stageID
            item.startsAt = ATProto.DateTime(rawValue: "1970-01-01T00:01:40Z")
            item.endsAt = ATProto.DateTime(rawValue: "1970-01-01T00:03:20Z")
            try ProgramItem.insert { item }.execute(db)
        }
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
