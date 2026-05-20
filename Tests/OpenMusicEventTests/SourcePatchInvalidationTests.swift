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
            try OME.Participant.insert {
                OME.Participant.Draft(
                    id: participantID(eventID: eventID),
                    name: "Artist"
                )
            }
            .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .insert,
            tableName: OME.Participant.tableName
        ))
    }

    @Test
    func sourceTableUpdatePublishesInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let participantID = participantID(eventID: eventID)
        try seedParticipant(participantID, in: database)
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Participant
                .find(participantID)
                .update { $0.bio = #bind("Updated bio") }
                .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Participant.tableName
        ))
    }

    @Test
    func sourceTableDeletePublishesInvalidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = try seedEvent(in: database)
        let participantID = participantID(eventID: eventID)
        try seedParticipant(participantID, in: database)
        let invalidations = try installSourcePatchInvalidations(in: database)
        let invalidationTask = nextInvalidationTask(from: invalidations.stream())

        try await database.write { db in
            try OME.Participant
                .find(participantID)
                .delete()
                .execute(db)
        }

        let invalidation = try await nextInvalidation(from: invalidationTask)
        #expect(invalidation == SourcePatchInvalidation(
            eventID: eventID,
            operation: .delete,
            tableName: OME.Participant.tableName
        ))
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

    private func seedParticipant(
        _ participantID: OME.Participant.ID,
        in database: any DatabaseWriter
    ) throws {
        try database.write { db in
            try OME.Participant.insert {
                OME.Participant.Draft(
                    id: participantID,
                    name: "Artist",
                    bio: "Original bio"
                )
            }
            .execute(db)
        }
    }

    private func participantID(eventID: OME.Event.ID) -> OME.Participant.ID {
        OME.Participant.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            participantID: localID("artist")
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

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}
