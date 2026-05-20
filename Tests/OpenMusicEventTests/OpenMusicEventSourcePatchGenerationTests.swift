import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import Testing

struct OpenMusicEventSourcePatchGenerationTests {
    @Test
    func generatorReadsExistingSourceAndUsesConversion() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: """
            name: Old Event
            timeZone: UTC
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let repositoryURL = fixture.repositoryURL
        let sourceReference = repositoryURL.path
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Old Event",
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
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: sourceReference,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = OpenMusicEventSourcePatchConversion {
                sourceEvent,
                _ in
                var sourceEvent = sourceEvent
                sourceEvent.event.name = "New Event"
                return sourceEvent
            }
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/event.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        #expect(String(decoding: newContents, as: UTF8.self).contains("name: New Event"))

        let originalContents = try String(
            contentsOf: repositoryURL
                .appending(path: "events/test-event/event.yml"),
            encoding: .utf8
        )
        #expect(originalContents.contains("name: Old Event"))
    }

    @Test
    func liveConversionUpdatesParticipantMarkdownFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/participants/artist-one.md",
            contents: """
            ---
            name: Artist One
            ---
            Old bio.
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let participantID = OME.Participant.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            participantID: localID("artist-one")
        )
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
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
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Participant.insert {
                OME.Participant.Draft(
                    id: participantID,
                    name: "Artist One",
                    bio: "New bio."
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/participants/artist-one.md")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Artist One"))
        #expect(newText.contains("New bio."))
        #expect(!newText.contains("Old bio."))
        #expect(!newText.contains("bio:"))
    }

    @Test
    func liveConversionUpdatesEventYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Old Event\ntimeZone: GMT\n"
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "New Event",
                    description: "Updated from the database.",
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/event.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Event"))
        #expect(newText.contains("description: Updated from the database."))
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
}

private final class OpenMusicEventSourcePatchGenerationFixture {
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "OpenMusicEventSourcePatchGenerationTests-\(UUID().uuidString)")
            .standardizedFileURL
        self.repositoryURL = rootURL.appending(path: "repository").standardizedFileURL

        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeFile(_ path: String, contents: String) throws {
        let url = repositoryURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:plc:sourcepatch")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}
