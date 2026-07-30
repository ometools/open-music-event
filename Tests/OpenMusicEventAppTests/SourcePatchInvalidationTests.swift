import BlueskyActorCache
import ATProto
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

struct SourcePatchInvalidationTests {
    @Test
    func sourceTableInsertPublishesInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Contributor.insert {
                OME.Contributor.Draft(
                    id: contributorID(eventID: eventID),
                    name: "Artist"
                )
            }
            .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .insert,
            tableName: OME.Contributor.tableName
        ))
    }

    @Test
    func sourceTableUpdatePublishesInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let contributorID = contributorID(eventID: eventID)
        try seedContributor(contributorID, in: database)
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Contributor
                .find(contributorID)
                .update { $0.bio = #bind("Updated bio") }
                .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Contributor.tableName
        ))
    }

    @Test
    func sourceTableDeletePublishesInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let contributorID = contributorID(eventID: eventID)
        try seedContributor(contributorID, in: database)
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Contributor
                .find(contributorID)
                .delete()
                .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .delete,
            tableName: OME.Contributor.tableName
        ))
    }

    @Test
    func compatibilityPerformanceUpdatePublishesCanonicalScheduleItemInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "stages" (
                      "organizerID", "eventID", "stageID", "name", "color"
                    ) VALUES (?, ?, 'main-stage', 'Main Stage', 0)
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "performances" (
                      "organizerID", "eventID", "performanceID", "stageID",
                      "startTime", "endTime", "title", "recordings"
                    ) VALUES (
                      ?, ?, 'opening-set', 'main-stage',
                      '2027-01-15T08:00:00Z', '2027-01-15T09:00:00Z', 'Opening Set', '[]'
                    )
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }

        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE "performances"
                    SET "title" = 'Updated Opening Set'
                    WHERE "organizerID" = ?
                      AND "eventID" = ?
                      AND "performanceID" = 'opening-set'
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.ScheduleItem.tableName
        ))
    }

    @Test
    func scheduleItemDetailAndContributorUpdatesPublishCanonicalInvalidations() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "stages" (
                      "organizerID", "eventID", "stageID", "name", "color"
                    ) VALUES (?, ?, 'main-stage', 'Main Stage', 0)
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO "performances" (
                      "organizerID", "eventID", "performanceID", "stageID",
                      "startTime", "endTime", "title", "recordings"
                    ) VALUES (
                      ?, ?, 'opening-set', 'main-stage',
                      '2027-01-15T08:00:00Z', '2027-01-15T09:00:00Z', 'Opening Set', '[]'
                    )
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }

        let invalidations = try installSourcePatchInvalidations(in: database)
        let detailInvalidationTask = nextInvalidationTask(from: invalidations.stream())
        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE "scheduleItemPerformanceDetails"
                    SET "recordings" = '[{"url":"https://example.com/set.mp3"}]'
                    WHERE "organizerID" = ?
                      AND "eventID" = ?
                      AND "scheduleItemID" = 'opening-set'
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }
        #expect(try await nextInvalidation(from: detailInvalidationTask) == SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.ScheduleItem.PerformanceDetails.tableName
        ))

        let contributorInvalidationTask = nextInvalidationTask(from: invalidations.stream())
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "scheduleItemContributors" (
                      "organizerID", "eventID", "scheduleItemID", "anonymousName",
                      "billing", "sortIndex"
                    ) VALUES (?, ?, 'opening-set', 'Guest Artist', 'supporting', 0)
                    """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }
        #expect(try await nextInvalidation(from: contributorInvalidationTask) == SourcePatchInvalidation(
            eventID: eventID,
            operation: .insert,
            tableName: OME.ScheduleItem.Contributor.tableName
        ))
    }

    @Test
    func calendarUpdatePublishesCalendarInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let calendarID = OME.Calendar.ID(
            ownerID: eventID.organizerID,
            calendarID: OME.Calendar.defaultID
        )
        try await database.write { db in
            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "Original calendar"
                )
            }
            .execute(db)
        }
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Calendar
                .find(calendarID)
                .update { $0.name = #bind("Updated calendar") }
                .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            calendarID: calendarID,
            operation: .update,
            tableName: OME.Calendar.tableName
        ))
    }

    @Test
    func workspaceRelationshipInsertPublishesWorkspaceInvalidation() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let collaboratorID = try #require(DID("did:plc:collaborator"))
        let workspace = EditingWorkspaceRecord(
            id: .init(rawValue: "team.workspace"),
            kind: .team,
            databaseFileName: "workspace.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            publicRecord: OME.Relationship.RecordReference(
                author: ownerID,
                collection: OME.SourceRecord.nsid,
                rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
            )
        )
        try await database.write { db in
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())
        let relationship = OME.Relationship(
            subject: .identity(did: collaboratorID),
            role: .collaborator([.propose]),
            object: .record(try #require(workspace.publicRecord)),
            createdAt: "2026-07-29T00:00:00Z"
        )

        try await database.write { db in
            try WorkspaceRelationshipRecord.insert {
                WorkspaceRelationshipRecord(
                    id: .init(workspaceID: workspace.id, actorID: collaboratorID),
                    recordKey: WorkspaceRelationshipRecord.recordKey(for: collaboratorID),
                    relationship: relationship
                )
            }
            .execute(db)
        }

        #expect(try await nextInvalidation(from: invalidationTask) == SourcePatchInvalidation(
            workspaceID: workspace.id,
            operation: .insert,
            tableName: WorkspaceRelationshipRecord.tableName
        ))
    }

    @Test
    func blueskyActorCacheWritesDoNotPublishSourceInvalidations() async throws {
        let database = try makePreparedDatabase()
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try BlueskyActorProfile.insert {
                BlueskyActorProfile(
                    did: "did:plc:alice123",
                    handle: "alice.bsky.social",
                    displayName: "Alice Example"
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: "alice.bsky.social",
                    did: "did:plc:alice123",
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        try await expectNoInvalidation(from: invalidationTask)
    }

    private func installSourcePatchInvalidations(
        in database: any DatabaseWriter
    ) throws -> SourcePatchInvalidations {
        let invalidations = SourcePatchInvalidations.live()
        try database.write { db in
            try invalidations.installTriggers(db)
        }
        return invalidations
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            let database = try SQLiteData.defaultDatabase()
            var migrator = DatabaseMigrator()
            OME.DatabaseMigrations.register(into: &migrator)
            BlueskyActorCacheMigrations.register(into: &migrator)
            try migrator.migrate(database)
            return database
        }
    }

    private func seedEvent(
        in database: any DatabaseWriter
    ) throws -> OME.Event.ID {
        let organizerID = try #require(OME.Organizer.ID("did:plc:sourcepatch"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("test-event")
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
        }
        return eventID
    }

    private func seedContributor(
        _ contributorID: OME.Contributor.ID,
        in database: any DatabaseWriter
    ) throws {
        try database.write { db in
            try OME.Contributor.insert {
                OME.Contributor.Draft(
                    id: contributorID,
                    name: "Artist",
                    bio: "Original bio"
                )
            }
            .execute(db)
        }
    }

    private func contributorID(eventID: OME.Event.ID) -> OME.Contributor.ID {
        OME.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: localID("artist")
        )
    }
}

private func nextInvalidationTask(
    from stream: AsyncStream<SourcePatchInvalidation>
) -> Task<SourcePatchInvalidation?, Never> {
    Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}

private func nextInvalidation(
    from task: Task<SourcePatchInvalidation?, Never>
) async throws -> SourcePatchInvalidation {
    try await withThrowingTaskGroup(of: SourcePatchInvalidation?.self) { group in
        group.addTask {
            await task.value
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            return nil
        }

        let invalidation = try await group.next()
        group.cancelAll()
        task.cancel()
        guard let invalidation, let invalidation else {
            throw SourcePatchInvalidationTimedOut()
        }
        return invalidation
    }
}

private struct SourcePatchInvalidationTimedOut: Error {}

private func expectNoInvalidation(
    from task: Task<SourcePatchInvalidation?, Never>
) async throws {
    try await withThrowingTaskGroup(of: SourcePatchInvalidation?.self) { group in
        group.addTask {
            await task.value
        }
        group.addTask {
            try await Task.sleep(for: .milliseconds(100))
            return nil
        }

        let result = try await group.next()
        group.cancelAll()
        task.cancel()
        guard let invalidation = result else { return }
        #expect(invalidation == nil)
    }
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}
