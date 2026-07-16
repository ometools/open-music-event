import ATProto
import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import Foundation
import HTTPClient
import HTTPTypes
import IssueReporting
import OpenMusicEventAuthentication
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SourceEditing
import SQLiteData
import Synchronization
import Testing
import XRPCClient

@testable import ATProtoOAuth
@testable import OpenMusicEventApp

@MainActor
@Suite(.tcaExhaustivity(.off), .dependencies { $0.defaultPort = 443 })
struct TangledSourceDownloadFeatureTests {
    @Test
    func myEventsPresentsDownloadFeature() throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        store.send(.didTapImportTeamWorkspace)

        guard case .sourceImport = store.state.destination else {
            Issue.record("Expected My Events to present the Tangled source download feature.")
            return
        }
    }

    @Test
    func myEventsFetchesTeamWorkspaces() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = importedEventID("wicked-woods-2026")
        let secondEventID = importedEventID("atmosphere-conf-2026")
        let firstSourceProvenance = tangledSourceProvenance(
            "wicked-woods-ome",
            ref: "HEAD"
        )
        let secondSourceProvenance = tangledSourceProvenance(
            "atmosphere-conf-ome",
            ref: "HEAD"
        )
        try await insertTeamWorkspace(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertTeamWorkspace(
            eventID: secondEventID,
            sourceProvenance: secondSourceProvenance,
            into: database
        )

        let teamWorkspaces = try await database.read { db in
            try MyEvents.teamWorkspacesQuery.fetchAll(db)
        }
        let events = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }

        expectNoDifference(
            teamWorkspaces.map(\.id),
            [
                SourceBaselineRecord.ID(source: secondSourceProvenance),
                SourceBaselineRecord.ID(source: firstSourceProvenance),
            ]
        )
        expectNoDifference(
            teamWorkspaces.map(\.organizer.id),
            [firstEventID.organizerID, firstEventID.organizerID]
        )
        expectNoDifference(teamWorkspaces.map(\.eventCount), [1, 1])
        #expect(events.isEmpty)
    }

    @Test
    func teamWorkspaceDetailFetchesEventsForOneTeamWorkspace() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = importedEventID("wicked-woods-2026")
        let secondEventID = importedEventID("atmosphere-conf-2026")
        let firstSourceProvenance = tangledSourceProvenance("wicked-woods-ome")
        let secondSourceProvenance = tangledSourceProvenance("atmosphere-conf-ome")
        try await insertTeamWorkspace(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertTeamWorkspace(
            eventID: secondEventID,
            sourceProvenance: secondSourceProvenance,
            into: database
        )

        let events = try await database.read { db in
            try TeamWorkspaceDetail
                .eventsQuery(
                    sourceBaselineID: SourceBaselineRecord.ID(source: secondSourceProvenance)
                )
                .fetchAll(db)
        }

        expectNoDifference(events.map(\.id), [secondEventID])
    }

    @Test
    func myEventsDeletesTeamWorkspace() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = importedEventID("wicked-woods-2026")
        let secondEventID = importedEventID("atmosphere-conf-2026")
        let firstSourceProvenance = tangledSourceProvenance(
            "wicked-woods-ome",
            ref: "HEAD"
        )
        let secondSourceProvenance = tangledSourceProvenance(
            "atmosphere-conf-ome",
            ref: "HEAD"
        )
        let firstSourceBaselineID = SourceBaselineRecord.ID(source: firstSourceProvenance)
        let secondSourceBaselineID = SourceBaselineRecord.ID(source: secondSourceProvenance)
        let sourceRepositoryRemovals = SourceRepositoryRemovalRecorder()

        try await insertTeamWorkspace(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertImportedEventData(firstEventID, into: database)
        try await insertTeamWorkspace(
            eventID: secondEventID,
            sourceProvenance: secondSourceProvenance,
            into: database
        )
        try await insertImportedEventData(secondEventID, into: database)
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(firstEventID.organizerID)
                $0.eventID = #bind(firstEventID.eventID)
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                store: { repositoryURL, _ in repositoryURL },
                remove: { sourceRepositoryRemovals.record($0) }
            )
        } operation: {
            var initialState = MyEvents.State()
            initialState.teamWorkspaceDetail = TeamWorkspaceDetail.State(
                sourceBaselineID: firstSourceBaselineID
            )
            return TestStore(initialState: initialState) {
                MyEvents()
            }
        }

        await store.send(.deleteTeamWorkspaces([firstSourceBaselineID]))?.value

        let organizers = try await database.read { db in
            try OMERecord.Organizer.fetchAll(db)
        }
        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let eventOrganizers = try await database.read { db in
            try OMERecord.EventOrganizer.fetchAll(db)
        }
        let stages = try await database.read { db in
            try OMERecord.Stage.fetchAll(db)
        }
        let schedules = try await database.read { db in
            try OMERecord.Schedule.fetchAll(db)
        }
        let contributors = try await database.read { db in
            try OMERecord.Contributor.fetchAll(db)
        }
        let channels = try await database.read { db in
            try OMERecord.Channel.fetchAll(db)
        }
        let posters = try await database.read { db in
            try OMERecord.Poster.fetchAll(db)
        }
        let performances = try await database.read { db in
            try OMERecord.Performance.fetchAll(db)
        }
        let performanceContributors = try await database.read { db in
            try OMERecord.Performance.Contributors.fetchAll(db)
        }
        let sourceBaselines = try await database.read { db in
            try SourceBaselineRecord.fetchAll(db)
        }
        let sourceProvenances = try await database.read { db in
            try EventSourceProvenanceRecord.fetchAll(db)
        }
        let workspaceRecords = try await database.read { db in
            try EditingWorkspaceRecord.fetchAll(db)
        }
        let eventWorkspaceRecords = try await database.read { db in
            try EventEditingWorkspaceRecord.fetchAll(db)
        }
        let teamWorkspaces = try await database.read { db in
            try MyEvents.teamWorkspacesQuery.fetchAll(db)
        }
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }

        #expect(store.state.errorMessage == nil)
        #expect(store.state.teamWorkspaceDetail == nil)
        expectNoDifference(organizers.map(\.id), [secondEventID.organizerID])
        expectNoDifference(events.map(\.id), [secondEventID])
        expectNoDifference(eventOrganizers.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(stages.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(schedules.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(contributors.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(channels.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(posters.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(performances.map(\.id.eventID), [secondEventID.eventID])
        expectNoDifference(performanceContributors.map(\.performanceID.eventID), [secondEventID.eventID])
        expectNoDifference(sourceBaselines.map(\.id), [secondSourceBaselineID])
        expectNoDifference(sourceProvenances.map(\.id), [secondEventID])
        expectNoDifference(
            workspaceRecords.map(\.id),
            [EditingWorkspaceRecord.ID(sourceBaselineID: secondSourceBaselineID)]
        )
        expectNoDifference(eventWorkspaceRecords.map(\.id), [secondEventID])
        expectNoDifference(teamWorkspaces.map(\.id), [secondSourceBaselineID])
        #expect(appState?.selectedEventID == nil)
        expectNoDifference(sourceRepositoryRemovals.values, [firstSourceProvenance])
    }

    @Test
    func myEventsConfirmsCreatedEventDeletion() throws {
        let database = try makePreparedDatabase()
        let eventID = createdEventID("delete-me")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        store.send(.deleteCreatedEventsButtonTapped([eventID]))

        expectNoDifference(store.state.deleteCreatedEventIDs, [eventID])
        #expect(store.state.isDeleteCreatedEventsConfirmationPresented)
    }

    @Test
    func myEventsDeletesCreatedEventAfterConfirmation() async throws {
        let database = try makePreparedDatabase()
        let deletedEventID = createdEventID("delete-me")
        let retainedEventID = createdEventID("keep-me")
        let sourceEventID = importedEventID("source-event")
        let sourceProvenance = tangledSourceProvenance("wicked-woods-ome")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)

        try await insertCreatedEvent(deletedEventID, name: "Delete Me", into: database)
        try await insertCreatedEvent(retainedEventID, name: "Keep Me", into: database)
        try await insertImportedEventData(deletedEventID, into: database)
        try await insertTeamWorkspace(
            eventID: sourceEventID,
            sourceProvenance: sourceProvenance,
            into: database
        )
        try await database.write { db in
            let calendarID = OMERecord.Calendar.ID(
                ownerID: deletedEventID.organizerID,
                calendarID: OMERecord.Calendar.defaultID
            )
            try OMERecord.Calendar.insert {
                OMERecord.Calendar.Draft(
                    id: calendarID,
                    name: "Local Calendar"
                )
            }
            .execute(db)
            try OMERecord.CalendarEntry.insert {
                OMERecord.CalendarEntry.Draft(
                    id: OMERecord.CalendarEntry.ID(
                        calendarOwnerID: calendarID.ownerID,
                        calendarID: calendarID.calendarID,
                        entryID: localID("delete-me")
                    ),
                    event: OMERecord.Event.reference(id: deletedEventID),
                    createdAt: Date(timeIntervalSince1970: 0),
                    pinned: false
                )
            }
            .execute(db)
            try OMERecord.CalendarEntry.insert {
                OMERecord.CalendarEntry.Draft(
                    id: OMERecord.CalendarEntry.ID(
                        calendarOwnerID: calendarID.ownerID,
                        calendarID: calendarID.calendarID,
                        entryID: localID("keep-me")
                    ),
                    event: OMERecord.Event.reference(id: retainedEventID),
                    createdAt: Date(timeIntervalSince1970: 1),
                    pinned: false
                )
            }
            .execute(db)
            try AppState.update {
                $0.organizerID = #bind(deletedEventID.organizerID)
                $0.eventID = #bind(deletedEventID.eventID)
            }
            .execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        store.send(.deleteCreatedEventsButtonTapped([deletedEventID]))
        await store.send(.deleteCreatedEventsConfirmationDeleteButtonTapped)?.value

        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let visibleCreatedEvents = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }
        let calendarEntries = try await database.read { db in
            try OMERecord.CalendarEntry.fetchAll(db)
        }
        let stages = try await database.read { db in
            try OMERecord.Stage.fetchAll(db)
        }
        let schedules = try await database.read { db in
            try OMERecord.Schedule.fetchAll(db)
        }
        let performances = try await database.read { db in
            try OMERecord.Performance.fetchAll(db)
        }
        let sourceProvenances = try await database.read { db in
            try EventSourceProvenanceRecord.fetchAll(db)
        }
        let teamWorkspaces = try await database.read { db in
            try MyEvents.teamWorkspacesQuery.fetchAll(db)
        }
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }

        #expect(store.state.errorMessage == nil)
        expectNoDifference(Set(events.map(\.id)), Set([retainedEventID, sourceEventID]))
        expectNoDifference(visibleCreatedEvents.map(\.id), [retainedEventID])
        expectNoDifference(calendarEntries.compactMap(\.event.localEventID), [retainedEventID])
        #expect(stages.allSatisfy { $0.id.eventID != deletedEventID.eventID })
        #expect(schedules.allSatisfy { $0.id.eventID != deletedEventID.eventID })
        #expect(performances.allSatisfy { $0.id.eventID != deletedEventID.eventID })
        expectNoDifference(sourceProvenances.map(\.id), [sourceEventID])
        expectNoDifference(teamWorkspaces.map(\.id), [sourceBaselineID])
        #expect(appState?.selectedEventID == nil)
    }

    @Test
    func importsTangledSourceUsingRepositoryRef() async throws {
        let recorder = ImportRecorder()
        let eventID = importedEventID()
        let result = try validationResult(eventID: eventID)

        let store = withDependencies {
            $0.context = .test
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
    func localSourceImportUsesSelectedSessionOrganizerAndOpensTeamWorkspace() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-local-import-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeMinimalSourceRepository(at: sourceURL)
        let organizerID = try #require(
            OMERecord.Organizer.ID(OAuth.Session.placeholder.accountID.rawValue.description)
        )
        let result = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: sourceURL.path(percentEncoded: false),
                organizerID: organizerID
            )
        )
        .validate()
        let expectedSourceProvenance = try #require(
            result.insertion.eventSourceProvenances.first?.source
        )
        let expectedSourceBaselineID = SourceBaselineRecord.ID(source: expectedSourceProvenance)
        let recorder = ImportRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.getOptionalDefaultSession = { .placeholder }
            $0.tangledSourceImport = TangledSourceImportClient { request in
                await recorder.record(request)
                return result
            }
        } operation: {
            var initialState = SourceImportCompletionHost.State()
            initialState.sourceImport.state.repository = " \(sourceURL.path(percentEncoded: false)) "
            return TestStore(initialState: initialState) {
                SourceImportCompletionHost()
            }
        }

        await store.send(to: \.sourceImport, .importButtonTapped)?.value

        let request = try #require(await recorder.requests.first)
        #expect(request.source == sourceURL.path(percentEncoded: false))
        #expect(request.organizerID == organizerID)
        #expect(request.ref == "HEAD")
        #expect(store.state.importedSource?.organizerID == organizerID)
        #expect(store.state.importedSource?.sourceBaselineID == expectedSourceBaselineID)
        #expect(store.state.sourceImport.state.isImporting == false)
        #expect(store.state.sourceImport.state.errorMessage == nil)
    }

    @Test
    func localSourceImportRequiresSelectedSession() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-local-import-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let store = withDependencies {
            $0.context = .test
            $0.getOptionalDefaultSession = { nil }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = sourceURL.path(percentEncoded: false)
            return TestStore(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        store.send(.importButtonTapped) {
            $0.errorMessage = "Sign in before opening a local source."
        }
    }

    @Test
    func localFolderSelectionFillsSourceField() {
        let store = withDependencies {
            $0.context = .test
        } operation: {
            TestStore(initialState: TangledSourceDownload.State()) {
                TangledSourceDownload()
            }
        }

        store.send(.sourceFolderSelected("/tmp/festival-source")) {
            $0.repository = "/tmp/festival-source"
            $0.errorMessage = nil
        }
    }

    @Test
    func teamWorkspaceDetailPresentsUploadForLocalSource() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .local,
            reference: "/tmp/festival-source"
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 0)
        )
        try await database.write { db in
            try SourceBaselineRecord.insert { sourceBaseline }
                .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: TeamWorkspaceDetail.State(sourceBaselineID: sourceBaseline.id)) {
                TeamWorkspaceDetail()
            }
        }

        store.send(.uploadToTangledButtonTapped)

        guard case let .uploadToTangled(upload)? = store.state.destination else {
            Issue.record("Expected local team workspace to present Tangled upload.")
            return
        }
        #expect(upload.state.sourceBaselineID == sourceBaseline.id)
        #expect(upload.state.repositoryName == "festival-source")
    }

    @Test
    func uploadPostsBootstrapCompletionAfterRequestSucceeds() async throws {
        let oldSourceBaselineID = SourceBaselineRecord.ID(rawValue: "local-source")
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:placeholder/festival-source",
            ref: "main"
        )
        let result = TangledWorkspaceBootstrapResult(
            sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance),
            sourceProvenance: sourceProvenance,
            repositoryReference: TangledRepositoryReference(
                host: "tangled.org",
                owner: "did:plc:placeholder",
                repository: "festival-source"
            ),
            repoDID: "did:plc:targetrepo"
        )
        let recorder = TangledWorkspaceBootstrapRequestRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.tangledWorkspaceBootstrap = TangledWorkspaceBootstrapClient { request in
                await recorder.record(request)
                return result
            }
        } operation: {
            TestStore(
                initialState: TangledWorkspaceUploadCompletionHost.State(
                    sourceBaselineID: oldSourceBaselineID,
                    repositoryName: " Festival.Source.git "
                )
            ) {
                TangledWorkspaceUploadCompletionHost()
            }
        }

        await store.send(to: \.upload, .uploadButtonTapped)?.value

        let requests = await recorder.requests
        expectNoDifference(
            requests,
            [
                TangledWorkspaceBootstrapRequest(
                    sourceBaselineID: oldSourceBaselineID,
                    repositoryName: " Festival.Source.git ",
                    description: "",
                    knotHost: "tangled.org",
                    defaultBranch: "main"
                )
            ]
        )
        #expect(store.state.result == result)
        #expect(store.state.upload.state.isUploading == false)
        #expect(store.state.upload.state.errorMessage == nil)
    }

    @Test
    func liveBootstrapUploadsLocalSourceAndPromotesDatabaseToTangledSource() async throws {
        let database = try makePreparedDatabase()
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-bootstrap-source-\(UUID().uuidString)")
            .standardizedFileURL
        let storedRepositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-bootstrap-stored-\(UUID().uuidString)")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: storedRepositoryURL)
        }
        try writeMinimalSourceRepository(at: sourceURL)

        let organizerID = try #require(
            OMERecord.Organizer.ID(OAuth.Session.placeholder.accountID.rawValue.description)
        )
        let imported = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            try await TangledSourceImportClient.live.importSource(
                OpenMusicEventSourceValidationRequest(
                    source: sourceURL.path(percentEncoded: false),
                    organizerID: organizerID
                )
            )
        }
        let oldSourceProvenance = try #require(
            imported.insertion.eventSourceProvenances.first?.source
        )
        let oldSourceBaselineID = SourceBaselineRecord.ID(source: oldSourceProvenance)
        let storage = SourceRepositoryStorageMapping(
            localURL: sourceURL,
            storedURL: storedRepositoryURL
        )
        let sourceControlRequests = SourceControlRequestRecorder()
        let httpRequests = BootstrapHTTPRequestRecorder()
        let authorizedRequirements = Mutex([OAuth.AuthRequirement]())
        let credentials = Credentials(
            ssh: SSHCredentials(
                publicKey: "ssh-ed25519 public-key Open Music Event",
                privateKey: "private-key"
            ),
            hostKeyPolicy: .acceptForTesting
        )

        let result = try await withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 1_783_500_000)
            $0.defaultDatabase = database
            $0.getDefaultSession = { .placeholder }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                authorizedRequirements.withLock { $0.append(requirement) }
            }
            $0.pdsHost = "placeholder.example"
            $0.uuid = .constant(
                try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000042"))
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await httpRequests.record(request, body)
                switch request.url?.path {
                case "/xrpc/sh.tangled.repo.create":
                    return Data(#"{"repoDid":"did:plc:targetrepo"}"#.utf8)

                case "/xrpc/com.atproto.repo.createRecord":
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:placeholder/sh.tangled.repo/festival-source",
                          "cid": "bafyreirepo"
                        }
                        """
                        .utf8
                    )

                case "/xrpc/com.atproto.repo.putRecord":
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:placeholder/app.openmusicevent.source/canonical",
                          "cid": "bafyreisource"
                        }
                        """
                        .utf8
                    )

                default:
                    throw BootstrapUnexpectedHTTPRequest(path: request.url?.path)
                }
            }
            $0.sourceRepositoryStorage = storage.client
            $0.sourceControl = SourceControlClient(
                clone: { request in
                    await sourceControlRequests.recordClone(request)
                    try FileManager.default.createDirectory(
                        at: request.destinationURL,
                        withIntermediateDirectories: true
                    )
                    return Repository(url: request.destinationURL)
                },
                open: { url in
                    await sourceControlRequests.recordOpen(url)
                    return Repository(url: url)
                },
                fetch: { _ in },
                checkout: { _ in },
                createBranch: { request in Branch(name: request.name) },
                status: { _ in [] },
                stage: { request in
                    await sourceControlRequests.recordStage(request)
                },
                commit: { request in
                    await sourceControlRequests.recordCommit(request)
                    return Commit(id: "abc123")
                },
                formatPatch: { _ in Data() },
                push: { request in
                    await sourceControlRequests.recordPush(request)
                }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                credentials
            }
        } operation: {
            try await TangledWorkspaceBootstrapClient.live.bootstrap(
                TangledWorkspaceBootstrapRequest(
                    sourceBaselineID: oldSourceBaselineID,
                    repositoryName: "Festival-Source.git",
                    description: " Festival source ",
                    knotHost: "tangled.org",
                    defaultBranch: "main"
                )
            )
        }

        let expectedSourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:placeholder/festival-source",
            ref: "main"
        )
        let expectedSourceBaselineID = SourceBaselineRecord.ID(source: expectedSourceProvenance)
        #expect(result.sourceBaselineID == expectedSourceBaselineID)
        #expect(result.sourceProvenance == expectedSourceProvenance)
        #expect(result.repoDID == "did:plc:targetrepo")

        let rows = try await database.read { db in
            (
                sourceBaselines: try SourceBaselineRecord.fetchAll(db),
                sourceProvenances: try EventSourceProvenanceRecord.fetchAll(db),
                workspaces: try EditingWorkspaceRecord.fetchAll(db),
                eventWorkspaces: try EventEditingWorkspaceRecord.fetchAll(db)
            )
        }
        expectNoDifference(rows.sourceBaselines.map(\.id), [expectedSourceBaselineID])
        expectNoDifference(rows.sourceProvenances.map(\.sourceProvenance), [expectedSourceProvenance])
        expectNoDifference(rows.sourceProvenances.map(\.sourceBaselineID), [expectedSourceBaselineID])
        expectNoDifference(
            rows.workspaces.map(\.id),
            [EditingWorkspaceRecord.ID(sourceBaselineID: expectedSourceBaselineID)]
        )
        expectNoDifference(
            rows.eventWorkspaces.map(\.workspaceID),
            [EditingWorkspaceRecord.ID(sourceBaselineID: expectedSourceBaselineID)]
        )

        let stageRequests = await sourceControlRequests.stageRequests
        let pushRequests = await sourceControlRequests.pushRequests
        let stagedPaths = try #require(stageRequests.first?.paths)
            .map(\.rawValue)
        #expect(stagedPaths.contains("events/imported-event/event.yml"))
        #expect(!stagedPaths.contains(".ome/reference.sqlite"))
        let pushRequest = try #require(pushRequests.first)
        #expect(pushRequest.localBranch == "main")
        #expect(pushRequest.remoteBranch == "main")
        #expect(pushRequest.credentials == result.repositoryReference.sourceControlCredentials(credentials))

        #expect(
            FileManager.default.fileExists(
                atPath: storedRepositoryURL
                    .appending(path: "events", directoryHint: .isDirectory)
                    .appending(path: "imported-event", directoryHint: .isDirectory)
                    .appending(path: "event.yml")
                    .path(percentEncoded: false)
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: storedRepositoryURL
                    .appending(path: ".ome", directoryHint: .isDirectory)
                    .appending(path: "reference.sqlite")
                    .path(percentEncoded: false)
            )
        )

        let requests = await httpRequests.requests
        let createRepositoryRequest = try #require(
            requests.first { $0.url?.path == "/xrpc/sh.tangled.repo.create" }
        )
        #expect(createRepositoryRequest.url?.host == "tangled.org")
        let createRepositoryBody = try #require(createRepositoryRequest.body)
        let createRepositoryJSON = try #require(
            JSONSerialization.jsonObject(with: createRepositoryBody) as? [String: Any]
        )
        #expect(createRepositoryJSON["rkey"] as? String == "festival-source")
        #expect(createRepositoryJSON["name"] as? String == "festival-source")
        #expect(createRepositoryJSON["defaultBranch"] as? String == "main")

        let createRecordRequest = try #require(
            requests.first { $0.url?.path == "/xrpc/com.atproto.repo.createRecord" }
        )
        #expect(createRecordRequest.url?.host == "placeholder.example")
        let createRecordBody = try #require(createRecordRequest.body)
        let createRecordJSON = try #require(
            JSONSerialization.jsonObject(with: createRecordBody) as? [String: Any]
        )
        #expect(createRecordJSON["repo"] as? String == "did:plc:placeholder")
        #expect(createRecordJSON["collection"] as? String == "sh.tangled.repo")
        #expect(createRecordJSON["rkey"] as? String == "festival-source")
        let record = try #require(createRecordJSON["record"] as? [String: Any])
        #expect(record["$type"] as? String == "sh.tangled.repo")
        #expect(record["name"] as? String == "festival-source")
        #expect(record["knot"] as? String == "tangled.org")
        #expect(record["description"] as? String == "Festival source")
        #expect(record["repoDid"] as? String == "did:plc:targetrepo")

        let putRecordRequest = try #require(
            requests.first { $0.url?.path == "/xrpc/com.atproto.repo.putRecord" }
        )
        #expect(putRecordRequest.url?.host == "placeholder.example")
        let putRecordBody = try #require(putRecordRequest.body)
        let putRecordJSON = try #require(
            JSONSerialization.jsonObject(with: putRecordBody) as? [String: Any]
        )
        #expect(putRecordJSON["repo"] as? String == "did:plc:placeholder")
        #expect(putRecordJSON["collection"] as? String == "app.openmusicevent.source")
        #expect(putRecordJSON["rkey"] as? String == "canonical")
        let sourceRecord = try #require(putRecordJSON["record"] as? [String: Any])
        #expect(sourceRecord["$type"] as? String == "app.openmusicevent.source")
        #expect(sourceRecord["kind"] as? String == "tangled")
        #expect(sourceRecord["reference"] as? String == "tangled.org/did:plc:placeholder/festival-source")
        #expect(sourceRecord["ref"] as? String == "main")
        #expect(sourceRecord["createdAt"] as? String == "2026-07-08T08:40:00Z")

        let authorizedPermissions = authorizedRequirements.withLock {
            $0.flatMap(\.permissions).map(\.rawValue)
        }
        #expect(authorizedPermissions.contains("rpc:sh.tangled.repo.create?aud=*"))
        #expect(authorizedPermissions.contains("repo:sh.tangled.repo?action=create"))
        #expect(authorizedPermissions.contains("repo:sh.tangled.publicKey?action=create"))
        #expect(authorizedPermissions.contains("repo:app.openmusicevent.source?action=create"))
        #expect(authorizedPermissions.contains("repo:app.openmusicevent.source?action=update"))
    }

    @Test
    func preparedDependenciesUseArchiveCheckoutForPublicTangledImports() async throws {
        let archiveData = Data("archive".utf8)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-public-tangled-checkout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let requestedPaths = Mutex<[String]>([])
        let extractedOutputURL = Mutex<URL?>(nil)

        try await withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
            $0.httpClient = .testClient { _, path, _ in
                requestedPaths.withLock { $0.append(path) }
                return archiveData
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient {
                downloadedArchiveData,
                outputURL in
                expectNoDifference(downloadedArchiveData, archiveData)
                extractedOutputURL.withLock { $0 = outputURL }
            }
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                Issue.record("Public Tangled archive checkout should not request SSH credentials.")
                throw PublicTangledCheckoutRequestedSSHCredentials()
            }
        } operation: {
            @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout
            let checkout = try await tangledSourceCheckout.checkout(
                TangledSourceCheckoutRequest(
                    repository: TangledRepositoryReference(
                        host: "tangled.org",
                        owner: "woody.fm",
                        repository: "shambhala-ome"
                    ),
                    ref: "HEAD",
                    outputURL: outputURL
                )
            )

            #expect(checkout.repositoryURL == outputURL.standardizedFileURL)
        }

        expectNoDifference(
            requestedPaths.withLock { $0 },
            ["/woody.fm/shambhala-ome/archive/HEAD.tar.gz"]
        )
        #expect(extractedOutputURL.withLock { $0 } == outputURL.standardizedFileURL)
    }

    @Test
    func sourceDataRefreshImportsSourceBaselineUsingBaseContext() async throws {
        let recorder = SourceDataRefreshImportRecorder()
        let sourceProvenance = tangledSourceProvenance(
            "refresh-source",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let result = try validationResult()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "source-data-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let baselineDatabasePath = temporaryURL.appending(path: "baseline.sqlite").path()
        let baselineDatabase = try DatabasePool(path: baselineDatabasePath)
        try await baselineDatabase.write { db in
            try db.execute(sql: "PRAGMA user_version = 0")
        }
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: temporaryURL.appending(path: "working.sqlite").path(),
            baselineDatabasePath: baselineDatabasePath
        )

        try await withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
            $0.sourceEditingSession = sourceEditingSession
            $0.tangledSourceImport = TangledSourceImportClient { request in
                @Dependency(\.sourceEditingSession) var sourceEditingSession
                await recorder.record(
                    request,
                    sourceEditingSessionIsNil: sourceEditingSession == nil
                )
                return result
            }
        } operation: {
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceDataRefresh) var sourceDataRefresh
            try await database.write { db in
                try SourceBaselineRecord.insert {
                    SourceBaselineRecord(
                        source: sourceProvenance,
                        databaseFileName: "baseline.sqlite",
                        importedAt: Date(timeIntervalSince1970: 0)
                    )
                }
                .execute(db)
            }

            try await sourceDataRefresh.refresh(sourceBaselineID)
        }

        let requests = await recorder.requests
        let sourceEditingSessionIsNilValues = await recorder.sourceEditingSessionIsNilValues
        expectNoDifference(
            requests,
            [
                OpenMusicEventSourceValidationRequest(
                    source: sourceProvenance.reference,
                    ref: "main"
                )
            ]
        )
        expectNoDifference(sourceEditingSessionIsNilValues, [true])
    }

    @Test
    func importResumesAfterAuthorizationRequestSuccess() async throws {
        let eventID = importedEventID()
        let result = try validationResult(eventID: eventID)
        let requirement = OpenMusicEventOAuth.tangledPublicKeyAuthRequirement
        let authorizationCenter = AuthorizationRequestCenter()

        let store = withDependencies {
            $0.context = .test
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.oauthAuthorizationBroker = authorizationCenter.broker
            $0.tangledSourceImport = TangledSourceImportClient { _ in
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(requirement)
                return result
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = "https://tangled.org/woody.fm/shambhala-ome"
            return Store(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        let task = store.send(.importButtonTapped)
        await fulfillAuthorizationRequest(
            from: authorizationCenter,
            requirement: requirement
        )
        await task?.value

        #expect(store.importedSummary == result.summary)
        #expect(store.errorMessage == nil)
        #expect(store.isPresented == false)
    }

    @Test
    func importRequiredXRPCUsesAuthorizedSessionFromRequestCenter() async throws {
        OpenMusicEventOAuth.resetStoredSession()
        var session = OAuth.Session.placeholder
        session.scope = OAuth.Scope(
            rawValue: [
                "atproto",
                OpenMusicEventOAuth.tangledPublicKeyCreatePermission.rawValue,
            ].joined(separator: " ")
        )
        let eventID = importedEventID()
        let result = try validationResult(eventID: eventID)
        let requirement = OpenMusicEventOAuth.tangledPublicKeyAuthRequirement
        let recorder = ImportAuthorizationRecorder()
        let authorizationCenter = AuthorizationRequestCenter()
        let selectedSession = Mutex<OAuth.Session?>(nil)

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.getDefaultSession = {
                selectedSession.withLock { $0 } ?? .placeholder
            }
            $0.getOptionalDefaultSession = {
                selectedSession.withLock { $0 }
            }
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.oauthAuthorizationBroker = authorizationCenter.broker
            $0.p256Sign = { _, _ in Data(repeating: 0xAB, count: 64) }
            $0.uuid = .constant(UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!)
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.xrpcAuthorizationGate = .defaultSessionAuthorization
            $0.dataForURL = { request, _ in
                await recorder.record(request)
                return (Data(#"{"ok":true}"#.utf8), HTTPResponse(status: .ok))
            }
            $0.tangledSourceImport = TangledSourceImportClient { _ in
                @Dependency(XRPC.Client.self) var xrpcClient
                let response = try await xrpcClient.run(
                    EmbeddedAuthorizationProbeRequest(requirement: requirement)
                )
                #expect(response.ok)
                return result
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = "https://tangled.org/woody.fm/shambhala-ome"
            return Store(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        let task = store.send(.importButtonTapped)
        await fulfillAuthorizationRequest(
            from: authorizationCenter,
            requirement: requirement
        ) {
            selectedSession.withLock { $0 = session }
        }
        await task?.value

        #expect(store.importedSummary == result.summary)
        #expect(store.errorMessage == nil)
        #expect(store.isPresented == false)
        #expect(await recorder.requestCount == 1)
        #expect(await recorder.lastAuthorizationHeader == "DPoP \(session.accessToken.rawValue)")
    }

    @Test
    func emptyRefDefaultsToHEAD() async throws {
        let recorder = ImportRecorder()

        let store = withDependencies {
            $0.context = .test
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
    func failedImportParsesSSHSessionError() async throws {
        let latestError = await reportedSourceImportError(
            throwing: #"operationFailed("failed to start SSH session: Unable to exchange encryption keys")"#
        )

        #expect(latestError?.kind == .sourceImportSSHSessionFailed)
        #expect(latestError?.message.fallback == "Unable to connect to Tangled over SSH.")
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func failedImportParsesSSHHostKeyError() async throws {
        let latestError = await reportedSourceImportError(
            throwing: #"operationFailed("invalid or unknown remote ssh hostkey")"#
        )

        #expect(latestError?.kind == .sourceImportSSHHostKeyFailed)
        #expect(latestError?.message.fallback == "Unable to verify Tangled's SSH host key.")
        #expect(latestError?.operation == .sourceImport)
    }

    @Test
    func liveImportReplacesExistingStoredRepositoryAfterSuccessfulImport() async throws {
        let database = try makePreparedDatabase()

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

        #expect(sourceReferenceBaselineCount == 1)
    }

    @Test
    func liveImportPreservesTangledRepositoryATURIAsSourceReference() async throws {
        let database = try makePreparedDatabase()

        let targetURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-repository-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: targetURL) }

        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let expectedTemporaryURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid)
        defer { try? FileManager.default.removeItem(at: expectedTemporaryURL) }

        let sourceReference = "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/ome-workspace"
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: sourceReference,
            ref: "HEAD"
        )

        let result = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.uuid = .constant(uuid)
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                expectNoDifference(
                    request.repository,
                    TangledRepositoryReference(
                        host: "tangled.org",
                        owner: "did:plc:5df2u7ief6m6tn77jznicxob",
                        repository: "ome-workspace"
                    )
                )
                #expect(request.ref == "HEAD")
                #expect(request.outputURL == expectedTemporaryURL)
                try writeMinimalSourceRepository(at: request.outputURL)
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                repositoryURL: { provenance in
                    #expect(provenance == sourceProvenance)
                    return targetURL
                },
                store: { repositoryURL, provenance in
                    #expect(repositoryURL == expectedTemporaryURL)
                    #expect(provenance == sourceProvenance)
                    try FileManager.default.moveItem(at: repositoryURL, to: targetURL)
                    return targetURL
                },
                remove: { _ in }
            )
        } operation: {
            try await TangledSourceImportClient.live.importSource(
                OpenMusicEventSourceValidationRequest(source: sourceReference)
            )
        }

        let sourceBaseline = try await database.read { db in
            try SourceBaselineRecord.fetchOne(db)
        }

        #expect(result.repositoryURL == targetURL)
        #expect(sourceBaseline?.sourceReference == sourceReference)
        #expect(sourceBaseline?.ref == "HEAD")
    }

    @Test
    func sourceEditModePreparationDoesNotRequestSSHForArchiveBackedTangledSource() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:owner123/wicked-woods-ome",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)

        let storedRepositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-edit-mode-source-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: storedRepositoryURL) }

        try writeMinimalSourceRepository(at: storedRepositoryURL)
        let referenceDirectoryURL = storedRepositoryURL
            .appending(path: ".ome", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: referenceDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("reference".utf8).write(
            to: referenceDirectoryURL.appending(path: "reference.sqlite")
        )

        try await database.write { db in
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "reference.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
        }

        try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                repositoryURL: { provenance in
                    #expect(provenance == sourceProvenance)
                    return storedRepositoryURL
                },
                store: { repositoryURL, provenance in
                    Issue.record(
                        "Preparing edit mode should not replace \(provenance) from \(repositoryURL)."
                    )
                    return repositoryURL
                },
                remove: { provenance in
                    Issue.record("Preparing edit mode should not remove \(provenance).")
                }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                Issue.record("Preparing edit mode should not request SSH credentials.")
                throw PublicTangledCheckoutRequestedSSHCredentials()
            }
        } operation: {
            try await SourceEditModePreparationClient.live.prepare(sourceBaselineID)
        }

        #expect(
            !FileManager.default.fileExists(atPath: storedRepositoryURL.appending(path: ".git").path)
        )
        #expect(
            FileManager.default.fileExists(
                atPath: storedRepositoryURL
                    .appending(path: ".ome", directoryHint: .isDirectory)
                    .appending(path: "reference.sqlite")
                    .path
            )
        )
        let gitignore = try String(
            contentsOf: storedRepositoryURL.appending(path: ".gitignore"),
            encoding: .utf8
        )
        #expect(gitignore.split(separator: "\n").contains(".ome/reference.sqlite"))
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
    func liveStorageResolvesTangledRefsToSameRepositoryURL() throws {
        let repository = "repository-\(UUID().uuidString)"
        let headProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:refless-storage-test/\(repository)",
            ref: "HEAD"
        )
        let mainProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/did:plc:refless-storage-test/\(repository)",
            ref: "main"
        )

        let headURL = try SourceRepositoryStorageClient.live.repositoryURL(headProvenance)
        let mainURL = try SourceRepositoryStorageClient.live.repositoryURL(mainProvenance)

        #expect(headURL == mainURL)
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
            $0.errorMessage = "Enter a source path or Tangled repository."
        }
    }

    private func reportedSourceImportError(
        throwing failureDescription: String
    ) async -> HandledError? {
        let store = withDependencies {
            $0.context = .test
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
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: localID("artist")
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
        try OMERecord.Performance.Contributors.insert {
            OMERecord.Performance.Contributors.Draft(
                performanceID: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: localID("opening")
                ),
                contributorID: localID("artist"),
                anonymousName: nil
            )
        }
        .execute(db)
    }
}

private func insertImportedEvent(
    _ eventID: OMERecord.Event.ID,
    name: String = "Imported Event",
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        } onConflict: {
            $0.id
        }
        .execute(db)
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: name,
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

private func insertCreatedEvent(
    _ eventID: OMERecord.Event.ID,
    name: String,
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        } onConflict: {
            $0.id
        }
        .execute(db)
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: name,
                startDate: nil,
                endDate: nil
            )
        }
        .execute(db)
    }
}

private func insertTeamWorkspace(
    eventID: OMERecord.Event.ID,
    sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance,
    into database: any DatabaseWriter
) async throws {
    try await insertImportedEvent(
        eventID,
        name: eventID.eventID.rawValue.rawValue,
        into: database
    )
    let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
    let sourceBaseline = SourceBaselineRecord(
        source: sourceProvenance,
        databaseFileName: "baseline.sqlite",
        importedAt: Date(timeIntervalSince1970: 0)
    )
    let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
    try await database.write { db in
        try SourceBaselineRecord.insert {
            sourceBaseline
        } onConflict: {
            $0.id
        }
        .execute(db)
        try EditingWorkspaceRecord.insert {
            workspace
        } onConflict: {
            $0.id
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
        try EventEditingWorkspaceRecord.insert {
            EventEditingWorkspaceRecord(
                id: eventID,
                workspaceID: workspace.id
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

private actor TangledWorkspaceBootstrapRequestRecorder {
    var requests: [TangledWorkspaceBootstrapRequest] = []

    func record(_ request: TangledWorkspaceBootstrapRequest) {
        requests.append(request)
    }
}

private actor SourceControlRequestRecorder {
    private(set) var cloneRequests: [CloneRequest] = []
    private(set) var openRequests: [URL] = []
    private(set) var stageRequests: [StageRequest] = []
    private(set) var commitRequests: [CommitRequest] = []
    private(set) var pushRequests: [PushRequest] = []

    func recordClone(_ request: CloneRequest) {
        cloneRequests.append(request)
    }

    func recordOpen(_ url: URL) {
        openRequests.append(url)
    }

    func recordStage(_ request: StageRequest) {
        stageRequests.append(request)
    }

    func recordCommit(_ request: CommitRequest) {
        commitRequests.append(request)
    }

    func recordPush(_ request: PushRequest) {
        pushRequests.append(request)
    }
}

private actor BootstrapHTTPRequestRecorder {
    struct Request: Sendable {
        var url: URL?
        var body: Data?
    }

    private(set) var requests: [Request] = []

    func record(_ request: HTTPRequest, _ body: Data?) {
        requests.append(Request(url: request.url, body: body))
    }
}

private final class SourceRepositoryStorageMapping: @unchecked Sendable {
    private let localURL: URL
    private let lock = NSLock()
    private let storedURL: URL
    private var storedProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance?

    init(localURL: URL, storedURL: URL) {
        self.localURL = localURL.standardizedFileURL
        self.storedURL = storedURL.standardizedFileURL
    }

    var client: SourceRepositoryStorageClient {
        SourceRepositoryStorageClient(
            repositoryURL: { [self] provenance in
                switch provenance.kind {
                case .local:
                    return localURL

                case .tangled:
                    return lock.withLock {
                        if storedProvenance == provenance {
                            return storedURL
                        }
                        return storedURL
                    }
                }
            },
            store: { [self] repositoryURL, provenance in
                if FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: storedURL)
                }
                try FileManager.default.moveItem(
                    at: repositoryURL.standardizedFileURL,
                    to: storedURL
                )
                lock.withLock {
                    storedProvenance = provenance
                }
                return storedURL
            },
            remove: { _ in }
        )
    }
}

private actor SourceDataRefreshImportRecorder {
    private var recordedRequests: [OpenMusicEventSourceValidationRequest] = []
    private var recordedSourceEditingSessionIsNilValues: [Bool] = []

    var requests: [OpenMusicEventSourceValidationRequest] {
        recordedRequests
    }

    var sourceEditingSessionIsNilValues: [Bool] {
        recordedSourceEditingSessionIsNilValues
    }

    func record(
        _ request: OpenMusicEventSourceValidationRequest,
        sourceEditingSessionIsNil: Bool
    ) {
        recordedRequests.append(request)
        recordedSourceEditingSessionIsNilValues.append(sourceEditingSessionIsNil)
    }
}

private actor ImportAuthorizationRecorder {
    private(set) var requestCount = 0
    private(set) var lastAuthorizationHeader: String?

    func record(_ request: HTTPRequest) {
        requestCount += 1
        lastAuthorizationHeader = request.headerFields[.authorization]
    }
}

private struct EmbeddedAuthorizationProbeOutput: Decodable {
    var ok: Bool
}

private struct EmbeddedAuthorizationProbeRequest: XRPC.Request {
    static let nsid = ATProto.NSID("app.openmusicevent.authProbe")
    static let type = XRPC.RequestType.query

    typealias Input = Never
    typealias Output = EmbeddedAuthorizationProbeOutput
    typealias Parameters = Never

    var requirement: OAuth.AuthRequirement

    var authorizationPolicy: XRPC.AuthorizationPolicy {
        .required(requirement)
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

private struct PublicTangledCheckoutRequestedSSHCredentials: Error {}

private struct BootstrapUnexpectedHTTPRequest: CustomStringConvertible, Error {
    var path: String?

    var description: String {
        "Unexpected bootstrap HTTP request: \(path ?? "nil")"
    }
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

@Feature
private struct SourceImportCompletionHost {
    struct State {
        var importedSource: ImportedSource?
        var sourceImport = Spawn(TangledSourceDownload.State())
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.sourceImport) {
                TangledSourceDownload()
            }
            .onEvent(SourceImportCompleted.self) { importedSource, state in
                state.importedSource = importedSource
            }
    }
}

@Feature
private struct TangledWorkspaceUploadCompletionHost {
    struct State {
        var result: TangledWorkspaceBootstrapResult?
        var upload: Spawn<TangledWorkspaceUpload>

        init(
            sourceBaselineID: SourceBaselineRecord.ID,
            repositoryName: String
        ) {
            upload = Spawn(
                TangledWorkspaceUpload.State(
                    sourceBaselineID: sourceBaselineID,
                    repositoryName: repositoryName
                )
            )
        }
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.upload) {
                TangledWorkspaceUpload()
            }
            .onEvent(TangledWorkspaceBootstrapCompleted.self) { result, state in
                state.result = result
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
            contributorCount: 0,
            channelCount: 0,
            posterCount: 0,
            performanceCount: 0,
            performanceContributorCount: 0
        )
    )
}

private func importedEventID(_ eventID: String = "imported-event") -> OMERecord.Event.ID {
    let organizerID = OMERecord.Organizer.ID("did:plc:imported")!
    return OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(.init(eventID))
    )
}

private func createdEventID(_ eventID: String = "created-event") -> OMERecord.Event.ID {
    let organizerID = OMERecord.Organizer.ID("did:web:local.openmusicevent")!
    return OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(.init(eventID))
    )
}

private func tangledSourceProvenance(
    _ repositoryName: String,
    ref: String? = nil
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
    OMERecord.SourceDatabaseInsertion.SourceProvenance(
        kind: .tangled,
        reference: "tangled.org/woody.fm/\(repositoryName)",
        ref: ref
    )
}

@MainActor
private func fulfillAuthorizationRequest(
    from authorizationCenter: AuthorizationRequestCenter,
    requirement: OAuth.AuthRequirement,
    beforeSucceed: () -> Void = {},
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let requests = await authorizationCenter.requests()
    for await request in requests {
        guard let request else { continue }
        #expect(request.requirement == requirement, sourceLocation: sourceLocation)
        beforeSucceed()
        await authorizationCenter.succeed()
        break
    }
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
