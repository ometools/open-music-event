import ComposableArchitecture2
import Dependencies
import DependenciesTestSupport
import FileTree
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import Synchronization
import Testing

@testable import ATProtoOAuth
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite(.tcaExhaustivity(.off), .serialized, .dependencies { $0.defaultPort = 443 })
struct EventWorkspaceSourcePatchInvalidationTests {
    @Test
    func generateSourcePatchButtonLoadsPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return patch
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.generateSourcePatchButtonTapped) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
            $0.sourceProposalStatus = .composing
        }
        await task?.value

        #expect(store.state.sourceProposal?.eventID == eventID)
        #expect(store.state.sourceProposal?.patch == patch)
        await store.dismount()
    }

    @Test
    func proposeChangeReviewsChangesWhenPatchIsNotReady() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return patch
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.proposeChangeButtonTapped) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
            $0.sourceProposalStatus = .composing
        }
        await task?.value

        #expect(store.state.sourceProposal?.eventID == eventID)
        #expect(store.state.sourceProposal?.patch == patch)
        await store.dismount()
    }

    @Test
    func proposeChangeButtonPreparesInlineProposalForGeneratedPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.proposeChangeButtonTapped) {
            $0.sourceProposalStatus = .composing
        }
        #expect(store.state.sourceProposal?.eventID == eventID)
        #expect(store.state.sourceProposal?.patch == patch)

        await store.dismount()
    }

    @Test
    func sourceProposalTitleAndDescriptionCanBeUpdated() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SourceProposalFlow.State(
                    eventID: eventID,
                    patch: patch
                )
            ) {
                SourceProposalFlow()
            }
        }

        store.send(.sourceProposalTitleChanged("Update the event name")) {
            $0.sourceProposalTitle = "Update the event name"
        }

        store.send(.sourceProposalDescriptionChanged("Updated the event name.")) {
            $0.sourceProposalDescription = "Updated the event name."
        }

        await store.dismount()
    }

    @Test
    func createProposalPublishesGeneratedPatchWithResolvedSourceLocation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let repositoryURL = URL(fileURLWithPath: "/tmp/source-repository")
        let location = SourcePatchLocation(
            repositoryURL: repositoryURL,
            relativePath: "events/event-1"
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let sourceChangeURL = try #require(URL(string: "https://source.woody.fm/events/event-1/proposals/1"))
        let publication = SourcePatchPublication(sourceChangeURL: sourceChangeURL)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                #expect(
                    request == SourcePatchPublishRequest(
                        description: "Updated the event name.",
                        location: location,
                        patch: patch,
                        title: "Update the event name"
                    )
                )
                return publication
            }
        } operation: {
            var state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.sourceProposalDescription = "Updated the event name."
            state.sourceProposalTitle = "Update the event name"
            return TestStore(initialState: state) {
                SourceProposalFlow()
            }
        }

        let task = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.success(publication)),
            timeout: .seconds(5)
        ) {
            $0.sourceProposalStatus = .created(publication)
        }
        await task?.value
        #expect(store.state.sourceProposalStatus == .created(publication))

        await store.dismount()
    }

    @Test
    func failedProposalCanBeRetried() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let location = SourcePatchLocation(
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
            relativePath: "events/event-1"
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                throw SourceProposalTestError.failed
            }
        } operation: {
            let state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            return TestStore(initialState: state) {
                SourceProposalFlow()
            }
        }
        let failure = EventWorkspace.SourceProposalFailure(SourceProposalTestError.failed)

        let task = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.failure(failure)),
            timeout: .seconds(5)
        ) {
            $0.sourceProposalStatus = .failed(failure)
        }
        await task?.value
        #expect(store.state.sourceProposalStatus == .failed(failure))

        let retryTask = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.failure(failure)),
            timeout: .seconds(5)
        ) {
            $0.sourceProposalStatus = .failed(failure)
        }
        await retryTask?.value
        #expect(store.state.sourceProposalStatus == .failed(failure))

        await store.dismount()
    }

    @Test
    func sourceProposalPublishResumesAfterAuthorizationRequestSuccess() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let location = SourcePatchLocation(
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
            relativePath: "events/event-1"
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let publication = SourcePatchPublication(
            sourceChangeURL: URL(string: "https://source.woody.fm/events/event-1/proposals/1")
        )
        let requirement = OpenMusicEventOAuth.proposalAuthRequirement
        let authorizationCenter = AuthorizationRequestCenter()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.oauthAuthorizationBroker = authorizationCenter.broker
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(requirement)
                return publication
            }
        } operation: {
            Store(initialState: SourceProposalFlow.State(eventID: eventID, patch: patch)) {
                SourceProposalFlow()
            }
        }

        let task = store.send(.createProposalButtonTapped)
        await fulfillAuthorizationRequest(
            from: authorizationCenter,
            requirement: requirement
        )
        await task?.value
        #expect(store.sourceProposalStatus == .created(publication))
    }

    @Test
    func resetEditsButtonResetsDraftAndClearsProposalState() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let resetRequests = Mutex([OME.Event.ID]())
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let proposalFailure = EventWorkspace.SourceProposalFailure(SourceProposalTestError.failed)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.eventWorkspaceResetter = EventWorkspaceResetter { eventID in
                resetRequests.withLock { $0.append(eventID) }
            }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.sourceProposalStatus = .failed(proposalFailure)
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.resetEditsButtonTapped) {
            $0.isResettingEdits = true
        }
        await store.receive(
            \.resetEditsResponse,
            .equals(
                Result<EventWorkspace.ResetEditsSuccess, EventWorkspace.ResetEditsFailure>
                    .success(EventWorkspace.ResetEditsSuccess())
            ),
            timeout: .seconds(1)
        ) {
            $0.isResettingEdits = false
            $0.sourcePatchStatus = .generated(SourcePatch())
            $0.sourceProposalStatus = .idle
        }
        await task?.value

        #expect(store.state.sourceProposal == nil)
        #expect(resetRequests.withLock { $0 } == [eventID])
        await store.dismount()
    }

    @Test
    func resetEditsButtonShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let failure = EventWorkspace.ResetEditsFailure(ResetEditsTestError.failed)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.eventWorkspaceResetter = EventWorkspaceResetter { _ in
                throw ResetEditsTestError.failed
            }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.resetEditsFailure = EventWorkspace.ResetEditsFailure(
                ResetEditsTestError.previousFailure
            )
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.resetEditsButtonTapped) {
            $0.isResettingEdits = true
            $0.resetEditsFailure = nil
        }
        await store.receive(
            \.resetEditsResponse,
            .equals(
                Result<EventWorkspace.ResetEditsSuccess, EventWorkspace.ResetEditsFailure>
                    .failure(failure)
            ),
            timeout: .seconds(1)
        ) {
            $0.isResettingEdits = false
            $0.resetEditsFailure = failure
        }
        await task?.value

        await store.dismount()
    }

    @Test
    func sourcePatchRegenerationPreservesInlineProposalTitleAndDescription() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let originalPatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let regeneratedPatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/contributors/artist.md",
                    kind: .modified,
                    oldContents: Data("Old bio.\n".utf8),
                    newContents: Data("New bio.\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(originalPatch)
            state.sourceProposal = SourceProposalFlow.State(
                eventID: eventID,
                patch: originalPatch
            )
            state.sourceProposal?.sourceProposalTitle = "Update the event"
            state.sourceProposal?.sourceProposalDescription = "Describe the changes."
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.sourcePatchGenerationResponse(.success(regeneratedPatch))) {
            $0.sourcePatchStatus = .generated(regeneratedPatch)
            $0.sourceProposalStatus = .composing
        }

        #expect(store.state.sourceProposal?.patch == regeneratedPatch)
        #expect(store.state.sourceProposal?.sourceProposalTitle == "Update the event")
        #expect(store.state.sourceProposal?.sourceProposalDescription == "Describe the changes.")
        await store.dismount()
    }

    @Test
    func emptySourcePatchClearsInlineProposal() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.sourcePatchGenerationResponse(.success(SourcePatch()))) {
            $0.sourcePatchStatus = .generated(SourcePatch())
            $0.sourceProposalStatus = .idle
        }

        #expect(store.state.sourceProposal == nil)
        await store.dismount()
    }

    @Test
    func sourceInvalidationClearsInlineProposalAndMarksPatchNeedsGeneration() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let invalidation = SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Contributor.tableName
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/contributors/artist.md",
                    kind: .modified,
                    oldContents: Data("Old bio.\n".utf8),
                    newContents: Data("New bio.\n".utf8)
                )
            ]
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        stream.continuation.yield(invalidation)
        await store.receive(
            \.sourcePatchInvalidationReceived,
            .equals(invalidation),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .needsGeneration(invalidation)
            $0.sourceProposalStatus = .idle
        }

        #expect(store.state.sourceProposal == nil)
        stream.continuation.finish()
        await store.dismount()
    }

    @Test
    func marksSourcePatchNeedsGenerationWhenCurrentEventInvalidates() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let invalidation = SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Contributor.tableName
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        stream.continuation.yield(invalidation)
        await store.receive(
            \.sourcePatchInvalidationReceived,
            .equals(invalidation),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .needsGeneration(invalidation)
        }

        stream.continuation.finish()
        await store.dismount()
    }

    @Test
    func ignoresSourcePatchInvalidationsForOtherEvents() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let otherEventInvalidation = SourcePatchInvalidation(
            eventID: testEventID("event-2"),
            operation: .update,
            tableName: OME.Contributor.tableName
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        stream.continuation.yield(otherEventInvalidation)
        await Task.yield()

        #expect(store.state.sourcePatchStatus == .notGenerated)

        stream.continuation.finish()
        await store.dismount()
    }

    @Test
    func refreshTangledPullReviewsButtonLoadsReviewsForTangledSource() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/shambhala-ome",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
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
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
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
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "event-1"
                )
            }
            .execute(db)
        }
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Move one performance later.",
            commentCount: 2,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [
                TangledPullReview.PatchBlob(
                    cid: "bafkreipatch",
                    createdAt: "2026-07-03T12:00:00Z",
                    index: 1,
                    mimeType: "application/gzip",
                    size: 123
                )
            ],
            sourceBranch: "ome/proposal-schedule",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([OpenMusicEventTangledPullReviewRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient { request in
                requests.withLock { $0.append(request) }
                return [review]
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.refreshTangledPullReviewsButtonTapped) {
            $0.tangledPullReviewStatus = .loading
        }
        await store.receive(
            \.tangledPullReviewsResponse,
            .equals(.success([review])),
            timeout: .seconds(1)
        ) {
            $0.tangledPullReviewStatus = .loaded([review])
        }
        await task?.value

        #expect(
            requests.withLock { $0 } == [
                OpenMusicEventTangledPullReviewRequest(eventID: eventID)
            ]
        )
        await store.dismount()
    }

    @Test
    func reviewSemanticDiffLoadsFromReviewBranchSnapshot() async throws {
        let database = try makePreparedDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "main"
        )
        let baselineSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2025"
        )
        let reviewSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2026"
        )
        try await withDependencies {
            $0.context = .test
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
        } operation: {
            let insertion = try OME.SourceDatabaseInsertion(
                OME.SourceDatabaseInsertion.Configuration(
                    source: baselineSource,
                    organizerID: eventID.organizerID,
                    sourceProvenance: sourceProvenance
                )
            )
            try await insertion.migrateAndInsert(into: database)
        }
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Hydrate the 2026 event.",
            commentCount: 0,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-2026",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Hydrate 2026",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let snapshotRequests = Mutex([TangledPullReviewSourceSnapshotRequest]())
        let receivedDiff = Mutex<EventWorkspace.TangledPullReviewSemanticDiff?>(nil)
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            $0.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient { request in
                snapshotRequests.withLock { $0.append(request) }
                return try OME.SourceDatabaseInsertion(
                    OME.SourceDatabaseInsertion.Configuration(
                        source: reviewSource,
                        organizerID: request.organizerID,
                        sourceProvenance: request.sourceProvenance
                    )
                )
            }
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.reviewSemanticDiffButtonTapped(review)) {
            $0.tangledPullReviewSemanticDiffs[review.id] = .loading
        }
        await store.receive(
            \.tangledPullReviewSemanticDiffResponse,
            .matching { (
                response: (
                    reviewID: String,
                    Result<
                        EventWorkspace.TangledPullReviewSemanticDiff,
                        EventWorkspace.TangledPullReviewSemanticDiffFailure
                    >
                )
            ) in
                guard response.reviewID == review.id,
                      case let .success(diff) = response.1
                else { return false }
                receivedDiff.withLock { $0 = diff }
                return diff.totalCount == 1
                    && diff.groups.contains { group in
                        group.id == "events" && group.modified == 1
                    }
            },
            timeout: .seconds(5)
        ) {
            guard let diff = receivedDiff.withLock({ $0 }) else {
                Issue.record("Expected semantic diff response.")
                return
            }
            $0.tangledPullReviewSemanticDiffs[review.id] = .loaded(diff)
        }
        await task?.value

        #expect(
            snapshotRequests.withLock { $0 } == [
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: eventID.organizerID,
                    review: review,
                    sourceProvenance: sourceProvenance
                )
            ]
        )
        let loadedDiff = try #require(
            receivedDiff.withLock { $0 }
        )
        let eventGroup = try #require(
            loadedDiff.groups.first { $0.id == "events" }
        )
        let eventChange = try #require(eventGroup.records.first)
        let nameChange = try #require(
            eventChange.fieldChanges.first { $0.columnName == "name" }
        )
        #expect(nameChange.baselineValue == "Wicked Woods 2025".databaseValue)
        #expect(nameChange.workingValue == "Wicked Woods 2026".databaseValue)
        #expect(loadedDiff.recordComparisons[eventChange]?.as(OME.Event.self) != nil)

        await store.dismount()
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

    private func seedSourceBackedEvent(
        _ eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceBaselineID = SourceBaselineRecord.ID(
            rawValue: "source.\(eventID.eventID.rawValue.rawValue)"
        )
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Source Event",
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
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    id: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: "/tmp/source-repository",
                    ref: nil,
                    databaseFileName: "reference.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: "/tmp/source-repository",
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: eventID.eventID.rawValue.rawValue
                )
            }
            .execute(db)
        }
    }

    private func makeReviewSourceRepository(
        eventID: OME.Event.ID,
        eventName: String
    ) throws -> OpenMusicEventSourceRepository {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        return OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: eventID.eventID.rawValue.rawValue,
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: eventID,
                            name: eventName,
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
                    )
                )
            ]
        )
    }
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:web:example.com")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private enum SourceProposalTestError: Equatable, Error {
    case failed
}

private enum ResetEditsTestError: Equatable, Error {
    case failed
    case previousFailure
}

private extension SourceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _ in URL(fileURLWithPath: database.path) },
            prepareForImport: { _ in database },
            existing: { _ in database }
        )
    }
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
