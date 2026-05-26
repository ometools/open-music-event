import ComposableArchitecture2
import ATProto
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import Foundation
import HTTPClient
import IssueReporting
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEvent

@MainActor
struct TangledSourceDownloadFeatureTests {
    @Test
    func myEventsPresentsDownloadFeature() throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        store.send(.didTapImportSource)

        guard case .sourceImport = store.state.destination else {
            Issue.record("Expected My Events to present the Tangled source download feature.")
            return
        }
    }

    @Test
    func myEventsFetchesDownloadedOrganizers() async throws {
        let database = try makePreparedDatabase()
        let eventID = importedEventID()
        try await insertImportedEvent(eventID, into: database)

        let organizers = try await database.read { db in
            try MyEvents.organizersQuery.fetchAll(db)
        }
        let events = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }

        #expect(organizers.map(\.id) == [eventID.organizerID])
        #expect(events.isEmpty)
    }

    @Test
    func myEventsDeletesDownloadedOrganizer() async throws {
        let database = try makePreparedDatabase()
        let eventID = importedEventID()
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/imported-source",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let sourceRepositoryRemovals = SourceRepositoryRemovalRecorder()

        try await insertImportedEvent(eventID, into: database)
        try await insertImportedEventData(eventID, into: database)
        try await database.write { db in
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: eventID.eventID.rawValue.rawValue
                )
            }
            .execute(db)
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.exhaustivity = .off
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                store: { repositoryURL, _ in repositoryURL },
                remove: { sourceRepositoryRemovals.record($0) }
            )
        } operation: {
            var initialState = MyEvents.State()
            initialState.organizerDetail = OrganizerDetail.State(
                organizerID: eventID.organizerID
            )
            return TestStore(initialState: initialState) {
                MyEvents()
            }
        }

        await store.send(.deleteOrganizers([eventID.organizerID]))?.value

        let organizerCount = try await database.read { db in
            try OMERecord.Organizer.fetchCount(db)
        }
        let eventCount = try await database.read { db in
            try OMERecord.Event.fetchCount(db)
        }
        let eventOrganizerCount = try await database.read { db in
            try OMERecord.EventOrganizer.fetchCount(db)
        }
        let stageCount = try await database.read { db in
            try OMERecord.Stage.fetchCount(db)
        }
        let scheduleCount = try await database.read { db in
            try OMERecord.Schedule.fetchCount(db)
        }
        let participantCount = try await database.read { db in
            try OMERecord.Participant.fetchCount(db)
        }
        let channelCount = try await database.read { db in
            try OMERecord.Channel.fetchCount(db)
        }
        let posterCount = try await database.read { db in
            try OMERecord.Poster.fetchCount(db)
        }
        let performanceCount = try await database.read { db in
            try OMERecord.Performance.fetchCount(db)
        }
        let performanceParticipantCount = try await database.read { db in
            try OMERecord.Performance.Participants.fetchCount(db)
        }
        let sourceBaselineCount = try await database.read { db in
            try SourceBaselineRecord.fetchCount(db)
        }
        let sourceProvenanceCount = try await database.read { db in
            try EventSourceProvenanceRecord.fetchCount(db)
        }
        let organizers = try await database.read { db in
            try MyEvents.organizersQuery.fetchAll(db)
        }
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }

        #expect(store.state.errorMessage == nil)
        #expect(store.state.organizerDetail == nil)
        #expect(organizerCount == 0)
        #expect(eventCount == 0)
        #expect(eventOrganizerCount == 0)
        #expect(stageCount == 0)
        #expect(scheduleCount == 0)
        #expect(participantCount == 0)
        #expect(channelCount == 0)
        #expect(posterCount == 0)
        #expect(performanceCount == 0)
        #expect(performanceParticipantCount == 0)
        #expect(sourceBaselineCount == 0)
        #expect(sourceProvenanceCount == 0)
        #expect(organizers.isEmpty)
        #expect(appState?.selectedEventID == nil)
        #expect(sourceRepositoryRemovals.values == [sourceProvenance])
    }

    @Test
    func importsTangledSourceUsingRepositoryRef() async throws {
        let recorder = ImportRecorder()
        let eventID = importedEventID()
        let result = try validationResult(eventID: eventID)

        let store = withDependencies {
            $0.context = .test
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { request in
                await recorder.record(request)
                return result
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = " https://tangled.org/woody.fm/shambhala-ome "
            initialState.ref = " main "
            return TestStore(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        await store.send(.importButtonTapped) {
            $0.isImporting = true
        }?.value
        #expect(store.state.isImporting == false)
        #expect(store.state.importedSummary == result.summary)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        #expect(
            await recorder.requests == [
                OpenMusicEventSourceValidationRequest(
                    source: "https://tangled.org/woody.fm/shambhala-ome",
                    ref: "main"
                )
            ]
        )
    }

    @Test
    func emptyRefDefaultsToHEAD() async throws {
        let recorder = ImportRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { request in
                await recorder.record(request)
                return try validationResult()
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = "woody.fm/shambhala-ome"
            initialState.ref = " "
            return TestStore(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        await store.send(.importButtonTapped)?.value

        #expect(await recorder.requests.map(\.ref) == ["HEAD"])
    }

    @Test
    func failedImportPostsErrorReported() async throws {
        let clock = TestClock()
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = clock
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { _ in
                throw ImportFailure()
            }
        } operation: {
            var initialState = SourceImportErrorHost.State()
            initialState.sourceImport.state.repository = "https://tangled.org/woody.fm/shambhala-ome"
            return TestStore(initialState: initialState) {
                SourceImportErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.sourceImport, .importButtonTapped)?.value
        }

        #expect(store.state.sourceImport.state.isImporting == false)
        #expect(store.state.sourceImport.state.importedSummary == nil)
        #expect(store.state.sourceImport.state.errorMessage == nil)
        #expect(store.isPresented == true)
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .unhandled)
        #expect(latestError?.message.fallback == "Unable to import source.")
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func failedImportParsesInvalidRepositoryError() async throws {
        let latestError = await reportedSourceImportError(
            throwing: "Repository reference must be shaped like owner/repo."
        )

        #expect(latestError?.kind == .sourceImportInvalidRepository)
        #expect(latestError?.message.fallback == "Enter a valid Tangled repository.")
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func failedImportParsesTangledArchiveResponseError() async throws {
        let latestError = await reportedSourceImportError(
            throwing: "Tangled did not return an archive: error code: 520"
        )

        #expect(latestError?.kind == .sourceImportArchiveUnavailable)
        #expect(latestError?.message.fallback == "Tangled did not return a source archive.")
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func failedImportParsesArchiveDestinationExistsError() async throws {
        let latestError = await reportedSourceImportError(
            throwing: """
            Failed to extract Tangled source archive: Error Domain=NSCocoaErrorDomain Code=516 \
            "\"extract-0\" could not be moved to \"SourceRepositories\" because an item with the same name already exists." \
            UserInfo={NSUnderlyingError=0x1 {Error Domain=NSPOSIXErrorDomain Code=17 "File exists"}}
            """
        )

        #expect(latestError?.kind == .sourceImportArchiveDestinationExists)
        #expect(
            latestError?.message.fallback
                == "Unable to prepare the downloaded source because a file already exists."
        )
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func liveImportReplacesExistingStoredRepositoryAfterSuccessfulImport() async throws {
        let database = try makePreparedDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        let targetURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-repository-\(UUID().uuidString)")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try "old".write(
            to: targetURL.appending(path: "old.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: targetURL) }

        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let expectedTemporaryURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid)
        defer { try? FileManager.default.removeItem(at: expectedTemporaryURL) }

        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome",
            ref: "HEAD"
        )
        nonisolated(unsafe) var removedProvenances: [OMERecord.SourceDatabaseInsertion.SourceProvenance] = []

        let result = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultBaselineDatabase = baselineDatabase
            $0.uuid = .constant(uuid)
            $0.httpClient = .testClient { _, _, _ in
                Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { _, outputURL in
                #expect(outputURL == expectedTemporaryURL)
                try writeMinimalSourceRepository(at: outputURL)
            }
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                repositoryURL: { provenance in
                    #expect(provenance == sourceProvenance)
                    return targetURL
                },
                store: { repositoryURL, provenance in
                    #expect(repositoryURL == expectedTemporaryURL)
                    #expect(provenance == sourceProvenance)
                    if FileManager.default.fileExists(atPath: targetURL.path()) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    try FileManager.default.moveItem(at: repositoryURL, to: targetURL)
                    return targetURL
                },
                remove: { provenance in
                    removedProvenances.append(provenance)
                }
            )
        } operation: {
            try await TangledSourceImportClient.live.importSource(
                OpenMusicEventSourceValidationRequest(
                    source: "https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome"
                )
            )
        }

        let eventCount = try await database.read { db in
            try OMERecord.Event.fetchCount(db)
        }

        #expect(result.repositoryURL == targetURL)
        #expect(eventCount == 1)
        #expect(removedProvenances.isEmpty)
        #expect(FileManager.default.fileExists(atPath: targetURL.appending(path: "events").path()))
        #expect(!FileManager.default.fileExists(atPath: targetURL.appending(path: "old.txt").path()))
        #expect(
            FileManager.default.fileExists(
                atPath: targetURL.appending(path: ".ome/reference.sqlite").path()
            )
        )

        let gitignore = try String(
            contentsOf: targetURL.appending(path: ".gitignore"),
            encoding: .utf8
        )
        #expect(gitignore.split(separator: "\n").contains(".ome/reference.sqlite"))

        let sourceReferenceDatabase = try defaultBaselineDatabase(
            path: targetURL.appending(path: ".ome/reference.sqlite").path()
        )
        let sourceReferenceBaselineCount = try sourceReferenceDatabase.read { db in
            try SourceBaselineRecord.fetchCount(db)
        }
        let appBaselineCount = (try? baselineDatabase.read { db in
            try SourceBaselineRecord.fetchCount(db)
        }) ?? 0

        #expect(sourceReferenceBaselineCount == 1)
        #expect(appBaselineCount == 0)
    }

    @Test
    func liveStorageResolvesLocalRepositoryURL() throws {
        let expectedURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-local-source-\(UUID().uuidString)", directoryHint: .isDirectory)
            .standardizedFileURL
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .local,
            reference: expectedURL.path(percentEncoded: false)
        )

        let resolvedURL = try SourceRepositoryStorageClient.live.repositoryURL(sourceProvenance)

        #expect(resolvedURL == expectedURL)
    }

    @Test
    func liveStorageResolvesTangledRepositoryURL() throws {
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:repository-url-test/repository",
            ref: "HEAD"
        )

        let expectedURL = try SourceRepositoryStorageClient
            .storedRepositoryURL(for: sourceProvenance)
            .standardizedFileURL
        let firstURL = try SourceRepositoryStorageClient.live.repositoryURL(sourceProvenance)
        let secondURL = try SourceRepositoryStorageClient.live.repositoryURL(sourceProvenance)

        #expect(firstURL == expectedURL)
        #expect(secondURL == expectedURL)
    }

    @Test
    func liveStorageResolvesEqualTangledProvenanceToEqualURLs() throws {
        let firstProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:equal-provenance-test/repository",
            ref: "main"
        )
        let secondProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:equal-provenance-test/repository",
            ref: "main"
        )

        let firstURL = try SourceRepositoryStorageClient.live.repositoryURL(firstProvenance)
        let secondURL = try SourceRepositoryStorageClient.live.repositoryURL(secondProvenance)

        #expect(firstURL == secondURL)
    }

    @Test
    func liveStorageReplacesExistingStoredRepository() throws {
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:replace-test/repository-\(UUID().uuidString)",
            ref: "HEAD"
        )
        let storedURL = try SourceRepositoryStorageClient
            .storedRepositoryURL(for: sourceProvenance)
            .standardizedFileURL
        try? FileManager.default.removeItem(at: storedURL)
        defer { try? FileManager.default.removeItem(at: storedURL) }

        try FileManager.default.createDirectory(at: storedURL, withIntermediateDirectories: true)
        try "old".write(
            to: storedURL.appending(path: "old.txt"),
            atomically: true,
            encoding: .utf8
        )

        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-repository-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeMinimalSourceRepository(at: sourceURL)

        let result = try SourceRepositoryStorageClient.live.store(
            sourceURL,
            sourceProvenance
        )

        #expect(result.normalizedSourceRepositoryPath == storedURL.normalizedSourceRepositoryPath)
        #expect(
            FileManager.default.fileExists(
                atPath: storedURL.appending(path: "events").path(percentEncoded: false)
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: storedURL.appending(path: "old.txt").path(percentEncoded: false)
            )
        )
    }

    @Test
    func liveStorageReplacesDanglingStoredRepositorySymlink() throws {
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:replace-symlink-test/repository-\(UUID().uuidString)",
            ref: "HEAD"
        )
        let storedURL = try SourceRepositoryStorageClient
            .storedRepositoryURL(for: sourceProvenance)
            .standardizedFileURL
        try? FileManager.default.removeItem(at: storedURL)
        defer { try? FileManager.default.removeItem(at: storedURL) }

        let missingURL = storedURL
            .deletingLastPathComponent()
            .appending(path: "missing-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(
            at: storedURL,
            withDestinationURL: missingURL
        )
        #expect(!FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))

        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-repository-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeMinimalSourceRepository(at: sourceURL)

        let result = try SourceRepositoryStorageClient.live.store(
            sourceURL,
            sourceProvenance
        )

        #expect(result.normalizedSourceRepositoryPath == storedURL.normalizedSourceRepositoryPath)
        #expect(
            FileManager.default.fileExists(
                atPath: storedURL.appending(path: "events").path(percentEncoded: false)
            )
        )
    }

    @Test
    func reportsEmptyRepository() throws {
        let store = withDependencies {
            $0.context = .test
        } operation: {
            TestStore(initialState: TangledSourceDownload.State()) {
                TangledSourceDownload()
            }
        }

        store.send(.importButtonTapped) {
            $0.errorMessage = "Enter a Tangled repository."
        }
    }

    private func reportedSourceImportError(
        throwing failureDescription: String
    ) async -> HandledError? {
        let store = withDependencies {
            $0.context = .test
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { _ in
                throw SourceImportFailure(description: failureDescription)
            }
        } operation: {
            var initialState = SourceImportErrorHost.State()
            initialState.sourceImport.state.repository = "https://tangled.org/woody.fm/shambhala-ome"
            return TestStore(initialState: initialState) {
                SourceImportErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.sourceImport, .importButtonTapped)?.value
        }

        #expect(store.state.sourceImport.state.isImporting == false)
        #expect(store.state.sourceImport.state.importedSummary == nil)
        #expect(store.state.sourceImport.state.errorMessage == nil)
        #expect(store.isPresented == true)
        return store.state.errorNotifications.state.latestError
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }
}

private func insertImportedEventData(
    _ eventID: OMERecord.Event.ID,
    into database: any DatabaseWriter
) async throws {
    let scheduleDate = try #require(LocalDate("2026-08-07"))
    try await database.write { db in
        try OMERecord.Stage.insert {
            OMERecord.Stage.Draft(
                id: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: localID("main")
                ),
                name: "Main",
                color: 0x336699
            )
        }
        .execute(db)
        try OMERecord.Schedule.insert {
            OMERecord.Schedule.Draft(
                id: OMERecord.Schedule.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    scheduleID: localID("friday")
                ),
                date: scheduleDate,
                startsAt: nil,
                endsAt: nil,
                customTitle: nil
            )
        }
        .execute(db)
        try OMERecord.Participant.insert {
            OMERecord.Participant.Draft(
                id: OMERecord.Participant.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    participantID: localID("artist")
                ),
                name: "Artist"
            )
        }
        .execute(db)
        try OMERecord.Channel.insert {
            OMERecord.Channel.Draft(
                id: OMERecord.Channel.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    channelID: localID("general")
                ),
                name: "General",
                description: "Updates",
                iconImageURL: nil,
                headerImageURL: nil,
                sortIndex: nil,
                defaultNotificationState: .subscribed,
                notificationsRequired: false
            )
        }
        .execute(db)
        try OMERecord.Poster.insert {
            OMERecord.Poster.Draft(
                id: OMERecord.Poster.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    posterID: localID("lineup")
                ),
                title: "Lineup",
                imageURL: URL(string: "https://example.com/lineup.png")!
            )
        }
        .execute(db)
        try OMERecord.Performance.insert {
            OMERecord.Performance.Draft(
                id: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: localID("opening")
                ),
                stageID: localID("main"),
                scheduleID: localID("friday"),
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Opening",
                description: nil,
                recordings: []
            )
        }
        .execute(db)
        try OMERecord.Performance.Participants.insert {
            OMERecord.Performance.Participants.Draft(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                performanceID: localID("opening"),
                participantID: localID("artist"),
                anonymousName: nil
            )
        }
        .execute(db)
    }
}

private func insertImportedEvent(
    _ eventID: OMERecord.Event.ID,
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        }
        .execute(db)
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: "Imported Event",
                startDate: nil,
                endDate: nil
            )
        }
        .execute(db)
        try OMERecord.EventOrganizer.insert {
            OMERecord.EventOrganizer.Draft(
                id: .init(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    eventOrganizerID: eventID.organizerID
                )
            )
        }
        .execute(db)
    }
}

private actor ImportRecorder {
    var requests: [OpenMusicEventSourceValidationRequest] = []

    func record(_ request: OpenMusicEventSourceValidationRequest) {
        requests.append(request)
    }
}

private final class SourceRepositoryRemovalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [OMERecord.SourceDatabaseInsertion.SourceProvenance] = []

    var values: [OMERecord.SourceDatabaseInsertion.SourceProvenance] {
        lock.withLock { _values }
    }

    func record(_ sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance) {
        lock.withLock {
            _values.append(sourceProvenance)
        }
    }
}

private struct ImportFailure: Error {}

private struct SourceImportFailure: CustomStringConvertible, Error, Sendable {
    var description: String
}

@Feature
private struct SourceImportErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var sourceImport = Spawn(TangledSourceDownload.State())
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.sourceImport) {
                TangledSourceDownload()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

private func validationResult(
    eventID: OMERecord.Event.ID = importedEventID()
) throws -> OpenMusicEventSourceValidationResult {
    let source = OpenMusicEventSourceRepository(events: [])
    let insertion = try OMERecord.SourceDatabaseInsertion(
        .init(source: source, organizerID: eventID.organizerID)
    )
    return OpenMusicEventSourceValidationResult(
        repositoryURL: FileManager.default.temporaryDirectory,
        organizerID: eventID.organizerID,
        insertion: insertion,
        insertedEventIDs: [eventID],
        summary: SourceValidationSummary(
            events: [.init(eventID: eventID.eventID.rawValue.rawValue, name: "Imported Event")],
            stageCount: 0,
            scheduleCount: 0,
            participantCount: 0,
            channelCount: 0,
            posterCount: 0,
            performanceCount: 0,
            performanceParticipantCount: 0
        )
    )
}

private func importedEventID() -> OMERecord.Event.ID {
    let organizerID = OMERecord.Organizer.ID("did:plc:imported")!
    return OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(.init("imported-event"))
    )
}

private func localID<Record>(_ string: String) -> OMERecord.ID<Record> {
    OMERecord.ID<Record>(rawValue: ATProto.Record.Key(rawValue: string))
}

private extension URL {
    var normalizedSourceRepositoryPath: String {
        var path = path(percentEncoded: false)
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

private func writeMinimalSourceRepository(at repositoryURL: URL) throws {
    let eventURL = repositoryURL
        .appending(path: "events", directoryHint: .isDirectory)
        .appending(path: "imported-event", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
    try """
    name: Imported Event
    timeZone: America/Denver
    """
    .write(
        to: eventURL.appending(path: "event.yml"),
        atomically: true,
        encoding: .utf8
    )
}
