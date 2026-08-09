import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
@testable import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
import Testing

@Suite("Source workspace patch generation", .serialized)
struct SourceWorkspacePatchGenerationTests {
    @Test
    func attachedPostImageIsCopiedIntoTheEventSource() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let selectedImageURL = rootURL.appending(path: "selected.png")
        let selectedImageData = Data("selected image".utf8)
        try selectedImageData.write(to: selectedImageURL)

        let source = OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: "postival",
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: nil,
                            name: "Postival",
                            description: nil,
                            startDate: nil,
                            endDate: nil,
                            status: nil,
                            mode: nil,
                            locations: nil,
                            uris: nil,
                            timeZone: try #require(TimeZone(identifier: "America/Denver")),
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        ),
                        communicationPosts: [
                            DirectoryContent(
                                directoryName: "general",
                                components: [
                                    try FileContent(
                                        fileName: "welcome",
                                        fileType: "md",
                                        data: CommunicationPostDTO(
                                            title: "Welcome",
                                            contents: "Welcome to Postival.",
                                            images: [
                                                SourceImageAsset(
                                                    source: .url(selectedImageURL),
                                                    role: .photo,
                                                    renderKind: .fullImage,
                                                    materializationPolicy: .lazy
                                                )
                                            ]
                                        )
                                    )
                                ]
                            )
                        ]
                    )
                )
            ]
        )

        let repositoryURL = rootURL.appending(path: "repository", directoryHint: .isDirectory)
        let materialized = try source.materializingLocalImageFiles(at: repositoryURL)
        let image = try #require(
            materialized.events.first?.components.communicationPosts?.first?.components.first?.data.images?.first
        )
        guard case let .file(path) = image.source else {
            Issue.record("Expected the attached post image to use a repository-relative file path.")
            return
        }

        #expect(path.hasPrefix("images/general-welcome-photo"))
        #expect(
            try Data(
                contentsOf: repositoryURL
                    .appending(path: "events/postival")
                    .appending(path: path)
            ) == selectedImageData
        )
    }

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
    func `a saved comms post becomes the normal source proposal patch`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let workspace = try fixture.workspace(
            organizer: "did:plc:wickedwoods",
            repository: "tangled.org/wickedwoods/events"
        )
        try await fixture.install(
            workspace,
            sourceFiles: [
                "calendar.yml": """
                name: Wicked Woods
                """,
                "events/woods-2026/event.yml": """
                name: Wicked Woods 2026
                timeZone: America/Denver
                """,
                "events/woods-2026/channels/general.yml": """
                name: General
                description: Official updates.
                defaultNotificationState: subscribed
                notificationsRequired: false
                """,
                "events/woods-2026/communications/general/channel-info.yaml": """
                name: General
                description: Official updates.
                defaultNotificationState: subscribed
                notificationsRequired: false
                """,
                "events/woods-2026/communications/general/welcome.md": """
                ---
                title: Welcome
                ---

                The gates open Friday.
                """,
            ]
        )
        let sourceEvent = try #require(
            try await fixture.installedEvents(for: workspace).first
        )
        let postID = CommsPost.ID(
            organizerID: sourceEvent.id.organizerID,
            eventID: sourceEvent.id.eventID,
            channelID: OME.ID<OME.Channel>(rawValue: "general"),
            postID: CommsPost.PostID("welcome")
        )

        // The post form has saved the author's changes into defaultDatabase.
        try await fixture.database.write { db in
            try CommsPost.find(postID).update {
                $0.title = "Gates are open"
                $0.contents = "**Welcome** to Wicked Woods."
            }
            .execute(db)
        }

        // The existing workspace proposal generator turns that database diff into Markdown.
        let patch = try await fixture.patch(for: workspace)
        expectNoDifference(
            patch.fileChanges.map(\.path),
            ["events/woods-2026/communications/general/welcome.md"]
        )
        let markdown = String(
            decoding: try #require(patch.fileChanges.first?.newContents),
            as: UTF8.self
        )
        #expect(markdown.contains("title: Gates are open"))
        #expect(markdown.contains("**Welcome** to Wicked Woods."))
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

    @Test
    func changingOneScheduleItemPreservesTheSourceStageOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let workspace = try fixture.workspace(
            organizer: "did:plc:wickedwoods",
            repository: "tangled.org/wickedwoods/events"
        )
        let expectedStageOrder = [
            "ursus",
            "unicorn-lounge",
            "the-hallow",
            "the-portal",
            "relaxation-ridge",
        ]

        // The organizer's Friday source has a deliberate stage order.
        try await fixture.install(
            workspace,
            sourceFiles: [
                "calendar.yml": """
                name: Wicked Woods
                """,
                "events/woods-2026/event.yml": """
                name: Wicked Woods 2026
                timeZone: America/Denver
                """,
                "events/woods-2026/stages/ursus.yml": """
                name: Ursus
                color: "0x111111"
                """,
                "events/woods-2026/stages/unicorn-lounge.yml": """
                name: Unicorn Lounge
                color: "0x222222"
                """,
                "events/woods-2026/stages/the-hallow.yml": """
                name: The Hallow
                color: "0x333333"
                """,
                "events/woods-2026/stages/the-portal.yml": """
                name: The Portal
                color: "0x444444"
                """,
                "events/woods-2026/stages/relaxation-ridge.yml": """
                name: Relaxation Ridge
                color: "0x555555"
                """,
                "events/woods-2026/schedules/friday.yml": """
                date: 2026-09-04
                performances:
                  ursus:
                    - id: ursus-opening
                      title: Ursus Opening
                      startTime: "15:00"
                      endTime: "16:00"
                  unicorn-lounge:
                    - id: unicorn-opening
                      title: Unicorn Opening
                      startTime: "15:00"
                      endTime: "16:00"
                  the-hallow:
                    - id: hallow-opening
                      title: Hallow Opening
                      startTime: "15:00"
                      endTime: "16:00"
                  the-portal:
                    - id: portal-opening
                      title: Portal Opening
                      startTime: "15:00"
                      endTime: "16:00"
                  relaxation-ridge:
                    - id: ridge-opening
                      title: Ridge Opening
                      startTime: "15:00"
                      endTime: "16:00"
                """,
            ]
        )
        let sourceEvent = try #require(
            try await fixture.installedEvents(for: workspace).first
        )

        // The organizer changes one item without rearranging the schedule.
        try await fixture.database.write { db in
            try OME.ScheduleItem.find(
                OME.ScheduleItem.ID(
                    organizerID: sourceEvent.id.organizerID,
                    eventID: sourceEvent.id.eventID,
                    scheduleItemID: OME.ID<OME.ScheduleItem>(.init("ursus-opening"))
                )
            )
            .update { $0.title = "Updated Ursus Opening" }
            .execute(db)
        }

        // The proposal should change the item while retaining the source's stage order.
        let patch = try await fixture.patch(for: workspace)
        expectNoDifference(
            patch.fileChanges.map(\.path),
            ["events/woods-2026/schedules/friday.yml"]
        )
        let scheduleChange = try #require(patch.fileChanges.first)
        let scheduleSource = String(
            decoding: try #require(scheduleChange.newContents),
            as: UTF8.self
        )
        let proposedStageOrder = scheduleSource
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("  "),
                      !line.hasPrefix("    "),
                      line.hasSuffix(":")
                else { return nil }
                return String(line.dropFirst(2).dropLast())
            }
        expectNoDifference(proposedStageOrder, expectedStageOrder)
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

    func install(
        _ workspace: SourceWorkspace,
        sourceFiles: [String: String]
    ) async throws {
        let location = try storage.location(workspace.id)
        for (path, contents) in sourceFiles {
            let fileURL = location.repositoryURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: location.repositoryURL)
            .output
            .requiredValue
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
