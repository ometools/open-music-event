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

        store.send(.didTapImportSource)

        guard case .sourceImport = store.state.destination else {
            Issue.record("Expected My Events to present the Tangled source download feature.")
            return
        }
    }

    @Test
    func myEventsFetchesDownloadedSources() async throws {
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
        try await insertDownloadedSource(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertDownloadedSource(
            eventID: secondEventID,
            sourceProvenance: secondSourceProvenance,
            into: database
        )

        let downloadedSources = try await database.read { db in
            try MyEvents.downloadedSourcesQuery.fetchAll(db)
        }
        let events = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }

        expectNoDifference(
            downloadedSources.map(\.id),
            [
                SourceBaselineRecord.ID(source: secondSourceProvenance),
                SourceBaselineRecord.ID(source: firstSourceProvenance),
            ]
        )
        expectNoDifference(
            downloadedSources.map(\.organizer.id),
            [firstEventID.organizerID, firstEventID.organizerID]
        )
        expectNoDifference(downloadedSources.map(\.eventCount), [1, 1])
        #expect(events.isEmpty)
    }

    @Test
    func sourceDetailFetchesEventsForOneDownloadedSource() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = importedEventID("wicked-woods-2026")
        let secondEventID = importedEventID("atmosphere-conf-2026")
        let firstSourceProvenance = tangledSourceProvenance("wicked-woods-ome")
        let secondSourceProvenance = tangledSourceProvenance("atmosphere-conf-ome")
        try await insertDownloadedSource(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertDownloadedSource(
            eventID: secondEventID,
            sourceProvenance: secondSourceProvenance,
            into: database
        )

        let events = try await database.read { db in
            try SourceDetail
                .eventsQuery(
                    sourceBaselineID: SourceBaselineRecord.ID(source: secondSourceProvenance)
                )
                .fetchAll(db)
        }

        expectNoDifference(events.map(\.id), [secondEventID])
    }

    @Test
    func myEventsDeletesDownloadedSource() async throws {
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

        try await insertDownloadedSource(
            eventID: firstEventID,
            sourceProvenance: firstSourceProvenance,
            into: database
        )
        try await insertImportedEventData(firstEventID, into: database)
        try await insertDownloadedSource(
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
            initialState.sourceDetail = SourceDetail.State(
                sourceBaselineID: firstSourceBaselineID
            )
            return TestStore(initialState: initialState) {
                MyEvents()
            }
        }

        await store.send(.deleteDownloadedSources([firstSourceBaselineID]))?.value

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
        let downloadedSources = try await database.read { db in
            try MyEvents.downloadedSourcesQuery.fetchAll(db)
        }
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }

        #expect(store.state.errorMessage == nil)
        #expect(store.state.sourceDetail == nil)
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
        expectNoDifference(downloadedSources.map(\.id), [secondSourceBaselineID])
        #expect(appState?.selectedEventID == nil)
        expectNoDifference(sourceRepositoryRemovals.values, [firstSourceProvenance])
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
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: temporaryURL.appending(path: "working.sqlite").path(),
            baselineDatabasePath: temporaryURL.appending(path: "baseline.sqlite").path()
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
    func sourceEditModePreparationPromotesArchiveBackedTangledSourceToGit() async throws {
        let database = try makePreparedDatabase()
        let ownerDID = try #require(DID("did:plc:owner123"))
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
            $0.uuid = .constant(
                try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
            )
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                repositoryURL: { provenance in
                    #expect(provenance == sourceProvenance)
                    return storedRepositoryURL
                },
                store: { repositoryURL, provenance in
                    #expect(provenance == sourceProvenance)
                    if FileManager.default.fileExists(atPath: storedRepositoryURL.path) {
                        try FileManager.default.removeItem(at: storedRepositoryURL)
                    }
                    try FileManager.default.moveItem(at: repositoryURL, to: storedRepositoryURL)
                    return storedRepositoryURL
                },
                remove: { _ in }
            )
            $0[Atmosphere.Account.Client.self] = .sourceEditModeTestClient(
                did: ownerDID,
                handle: "owner.example",
                pdsHost: "owner.pds.example"
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                guard request.url?.host == "owner.pds.example" else {
                    throw SourceEditModePreparationTestError.unexpectedRequest
                }
                return Data(
                    """
                    {
                      "records": [
                        {
                          "uri": "at://did:plc:owner123/sh.tangled.repo/3repo",
                          "cid": "bafyreifakerepo",
                          "value": {
                            "$type": "sh.tangled.repo",
                            "name": "wicked-woods-ome",
                            "repoDid": "did:plc:targetrepo",
                            "knot": "tangled.org",
                            "createdAt": "2026-05-26T17:30:42Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
            $0.sourceControl = SourceControlClient(
                clone: { request in
                    try FileManager.default.createDirectory(
                        at: request.destinationURL.appending(path: ".git"),
                        withIntermediateDirectories: true
                    )
                    try writeMinimalSourceRepository(at: request.destinationURL)
                    return Repository(url: request.destinationURL)
                },
                open: { Repository(url: $0) },
                fetch: { _ in },
                checkout: { _ in },
                createBranch: { Branch(name: $0.name) },
                status: { _ in [] },
                stage: { _ in },
                commit: { _ in Commit(id: "unused") },
                formatPatch: { _ in Data() },
                push: { _ in }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                Credentials(
                    ssh: SSHCredentials(
                        publicKey: "ssh-ed25519 public-key Open Music Event",
                        privateKey: "private-key"
                    )
                )
            }
        } operation: {
            try await SourceEditModePreparationClient.live.prepare(sourceBaselineID)
        }

        #expect(
            FileManager.default.fileExists(
                atPath: storedRepositoryURL.appending(path: ".git").path
            )
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

private func insertDownloadedSource(
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
    try await database.write { db in
        try SourceBaselineRecord.insert {
            SourceBaselineRecord(
                source: sourceProvenance,
                databaseFileName: "baseline.sqlite",
                importedAt: Date(timeIntervalSince1970: 0)
            )
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
    }
}

private actor ImportRecorder {
    var requests: [OpenMusicEventSourceValidationRequest] = []

    func record(_ request: OpenMusicEventSourceValidationRequest) {
        requests.append(request)
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

private enum SourceEditModePreparationTestError: Error {
    case unexpectedRequest
}

private extension Atmosphere.Account.Client {
    static func sourceEditModeTestClient(
        did: DID,
        handle: Atmosphere.Account.Handle,
        pdsHost: String
    ) -> Self {
        Self(
            resolveHandle: { resolvedHandle in
                guard resolvedHandle == handle else {
                    throw SourceEditModePreparationTestError.unexpectedRequest
                }
                return (
                    Atmosphere.Account(id: .init(did), handle: handle),
                    try sourceEditModeDIDDocument(
                        did: did,
                        handle: handle,
                        pdsHost: pdsHost
                    )
                )
            },
            resolveDID: { resolvedDID in
                guard resolvedDID == did else {
                    throw SourceEditModePreparationTestError.unexpectedRequest
                }
                return (
                    Atmosphere.Account(id: .init(did), handle: handle),
                    try sourceEditModeDIDDocument(
                        did: did,
                        handle: handle,
                        pdsHost: pdsHost
                    )
                )
            }
        )
    }
}

private func sourceEditModeDIDDocument(
    did: DID,
    handle: Atmosphere.Account.Handle,
    pdsHost: String
) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://\(handle.rawValue)"],
              "verificationMethod": [],
              "service": [
                {
                  "id": "#atproto_pds",
                  "type": "AtprotoPersonalDataServer",
                  "serviceEndpoint": "https://\(pdsHost)"
                }
              ]
            }
            """
            .utf8
        )
    )
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
