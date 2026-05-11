import Dependencies
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

public extension OME.SourceDatabaseInsertion {
    func migrateAndInsertIntoDefaultDatabase() async throws {
        @Dependency(\.defaultDatabase) var database
        try await migrateAndInsert(into: database)
    }

    func migrateAndInsert(into database: any DatabaseWriter) async throws {
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try await insert(into: database)
    }

    func insert(into database: any DatabaseWriter) async throws {
        try await database.write { db in
            try insert(into: db)
        }
    }

    func insert(into db: Database) throws {
        if !organizers.isEmpty {
            try OME.Organizer.insert {
                organizers
            } onConflict: {
                $0.id
            }
            .execute(db)
        }
        if !events.isEmpty {
            try OME.Event.insert { events }.execute(db)
        }
        if !eventOrganizers.isEmpty {
            try OME.EventOrganizer.insert {
                eventOrganizers
            } onConflict: {
                (
                    $0.id.organizerID,
                    $0.id.eventID,
                    $0.id.eventOrganizerID
                )
            }
            .execute(db)
        }
        if !stages.isEmpty {
            try OME.Stage.insert { stages }.execute(db)
        }
        if !schedules.isEmpty {
            try OME.Schedule.insert { schedules }.execute(db)
        }
        if !participants.isEmpty {
            try OME.Participant.insert { participants }.execute(db)
        }
        if !channels.isEmpty {
            try OME.Channel.insert { channels }.execute(db)
        }
        if !posters.isEmpty {
            try OME.Poster.insert { posters }.execute(db)
        }
        if !performances.isEmpty {
            try OME.Performance.insert { performances }.execute(db)
        }
        if !performanceParticipants.isEmpty {
            try OME.Performance.Participants.insert { performanceParticipants }.execute(db)
        }
    }
}

public extension OpenMusicEventSourceValidator {
    func validateAndInsertIntoDefaultDatabase() async throws -> OpenMusicEventSourceValidationResult {
        @Dependency(\.defaultDatabase) var database
        return try await validateAndInsert(into: database)
    }

    func validateAndInsert(into database: any DatabaseWriter) async throws -> OpenMusicEventSourceValidationResult {
        let result = try await validate()
        try await result.insertion.migrateAndInsert(into: database)
        return result
    }
}
