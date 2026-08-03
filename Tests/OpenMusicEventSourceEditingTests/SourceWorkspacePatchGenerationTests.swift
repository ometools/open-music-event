import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
import Testing

@Suite("Source workspace patch generation", .serialized)
struct SourceWorkspacePatchGenerationTests {
    @Test
    func onePatchCapturesEveryEventOwnedByTheSourceWorkspace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let workspace = try fixture.workspace(
            organizer: "did:plc:wickedwoods",
            repository: "tangled.org/wickedwoods/events"
        )
        let eventDirectories = ["forest-2026", "meadow-2026"]

        try await fixture.install(
            workspace,
            repository: Self.sourceRepository(
                eventDirectories: eventDirectories,
                names: ["Forest", "Meadow"]
            )
        )
        let installedEvents = try await fixture.installedEvents(for: workspace)
        #expect(installedEvents.map(\.sourceEventDirectory) == eventDirectories)

        try await fixture.database.write { db in
            for sourceEvent in installedEvents {
                try OME.Event.find(sourceEvent.id).update {
                    $0.name = "Updated \(sourceEvent.sourceEventDirectory)"
                }
                .execute(db)
            }
        }

        let patch = try await fixture.patch(for: workspace)

        expectNoDifference(
            patch.fileChanges.map(\.path),
            eventDirectories.map { "events/\($0)/event.yml" }
        )
        expectNoDifference(
            patch.fileChanges.map(\.kind),
            [.modified, .modified]
        )
    }

    @Test
    func aWorkspacePatchCannotCaptureAnotherOrganizationSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wickedWoods = try fixture.workspace(
            organizer: "did:plc:wickedwoods",
            repository: "tangled.org/wickedwoods/events"
        )
        let otherFestival = try fixture.workspace(
            organizer: "did:plc:otherfestival",
            repository: "tangled.org/otherfestival/events"
        )

        try await fixture.install(
            wickedWoods,
            repository: Self.sourceRepository(
                eventDirectories: ["wicked-woods-2026"],
                names: ["Wicked Woods"]
            )
        )
        try await fixture.install(
            otherFestival,
            repository: Self.sourceRepository(
                eventDirectories: ["other-2026"],
                names: ["Other Festival"]
            )
        )

        let wickedWoodsEvent = try #require(
            try await fixture.installedEvents(for: wickedWoods).first
        )
        let otherEvent = try #require(
            try await fixture.installedEvents(for: otherFestival).first
        )
        try await fixture.database.write { db in
            try OME.Event.find(wickedWoodsEvent.id).update { $0.name = "Updated Woods" }
                .execute(db)
            try OME.Event.find(otherEvent.id).update { $0.name = "Updated Other" }
                .execute(db)
        }

        let patch = try await fixture.patch(for: wickedWoods)

        expectNoDifference(
            patch.fileChanges.map(\.path),
            ["events/wicked-woods-2026/event.yml"]
        )
        #expect(
            patch.fileChanges.allSatisfy {
                String(data: $0.newContents ?? Data(), encoding: .utf8)?
                    .contains("Updated Other") == false
            }
        )
    }

    @Test
    func editingAnInferredStageMaterializesThatAuthorChange() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let workspace = try fixture.workspace(
            organizer: "did:plc:wickedwoods",
            repository: "tangled.org/wickedwoods/events"
        )
        try await fixture.install(
            workspace,
            repository: Self.sourceRepository(
                eventDirectories: ["wicked-woods-2026"],
                names: ["Wicked Woods"]
            )
        )
        let sourceEvent = try #require(
            try await fixture.installedEvents(for: workspace).first
        )
        let stageID = OME.Stage.ID(
            organizerID: sourceEvent.id.organizerID,
            eventID: sourceEvent.id.eventID,
            stageID: OME.Stage.singletonID
        )

        try await fixture.database.write { db in
            try OME.Stage.find(stageID).update { $0.name = "Forest" }.execute(db)
        }

        let patch = try await fixture.patch(for: workspace)

        expectNoDifference(
            patch.fileChanges.map(\.path),
            ["events/wicked-woods-2026/stages/stage.yml"]
        )
        expectNoDifference(patch.fileChanges.map(\.kind), [.added])
    }

    private static func sourceRepository(
        eventDirectories: [String],
        names: [String]
    ) -> OpenMusicEventSourceRepository {
        precondition(eventDirectories.count == names.count)
        return OpenMusicEventSourceRepository(
            calendar: CalendarDTO(name: "Events"),
            events: zip(eventDirectories, names).map { directory, name in
                DirectoryContent(
                    directoryName: directory,
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: nil,
                            name: name,
                            description: nil,
                            startDate: nil,
                            endDate: nil,
                            status: nil,
                            mode: nil,
                            locations: nil,
                            uris: nil,
                            timeZone: TimeZone(secondsFromGMT: 0)!,
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        )
                    )
                )
            }
        )
    }
}

private final class Fixture {
    let database: any DatabaseWriter
    let rootURL: URL
    let storage: SourceWorkspaceStorage

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SourceWorkspacePatchGeneration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        storage = .fileBacked(rootURL: rootURL.appending(path: "workspaces"))
        database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func workspace(
        organizer: String,
        repository: String
    ) throws -> SourceWorkspace {
        SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID(organizer)),
            repository: repository,
            branch: "main"
        )
    }

    func install(
        _ workspace: SourceWorkspace,
        repository: OpenMusicEventSourceRepository
    ) async throws {
        let location = try storage.location(workspace.id)
        try FileManager.default.createDirectory(
            at: location.repositoryURL,
            withIntermediateDirectories: true
        )
        _ = try OpenMusicEventSourceRepositoryFileTree().write(
            repository,
            to: location.repositoryURL
        )
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: repository,
                organizerID: workspace.organizerID,
                sourceProvenance: workspace.sourceProvenance,
                sourceRootURL: location.repositoryURL
            )
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            revision: "base-revision",
            in: database
        )
    }

    func installedEvents(
        for workspace: SourceWorkspace
    ) async throws -> [EventSourceProvenanceRecord] {
        try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.organizerID.eq(workspace.organizerID) }
                .fetchAll(db)
                .filter { $0.workspace?.id == workspace.id }
                .sorted { $0.sourceEventDirectory < $1.sourceEventDirectory }
        }
    }

    func patch(for workspace: SourceWorkspace) async throws -> SourcePatch {
        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceWorkspaceStorage = storage
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: rootURL
            )
            $0.sourceWorkspacePatchConversion = .live
        } operation: {
            try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
        }
    }
}
