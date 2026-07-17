import ComposableArchitecture2
import Clocks
import CustomDump
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import FileTree
import Foundation
import HTTPClient
import HTTPTypes
import IssueReporting
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
@Suite(
    .tcaExhaustivity(.off),
    .serialized,
    .dependencies { $0.defaultPort = 443 }
)
struct EventWorkspaceSourcePatchInvalidationTests {
    @Test
    func generateSourcePatchButtonLoadsPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
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
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(
                    request == OpenMusicEventCalendarSourcePatchRequest(
                        calendarID: OME.Calendar.ID(
                            ownerID: eventID.organizerID,
                            calendarID: OME.Calendar.defaultID
                        ),
                        sourceBaselineID: expectedSourceBaselineID
                    )
                )
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
        }
        await task?.value

        #expect(store.state.sourceProposal == nil)
        #expect(store.state.sourceProposalStatus == .idle)
        await store.dismount()
    }

    @Test
    func proposeChangeReviewsChangesWhenPatchIsNotReady() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
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
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(
                    request == OpenMusicEventCalendarSourcePatchRequest(
                        calendarID: OME.Calendar.ID(
                            ownerID: eventID.organizerID,
                            calendarID: OME.Calendar.defaultID
                        ),
                        sourceBaselineID: expectedSourceBaselineID
                    )
                )
                return patch
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.proposeChangeButtonTapped) {
            $0.isPreparingSourceProposal = true
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.isPreparingSourceProposal = false
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
        try await seedEditingWorkspace(for: eventID, in: database)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)
        try await database.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Updated Source Event" }
                .execute(db)
        }
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: directoryURL.appending(path: "session.sqlite").path(),
            baselineDatabasePath: baselineDatabase.path
        )
        let expectedWorkspaceSummary = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
        #expect(expectedWorkspaceSummary.availability == .available)
        #expect(expectedWorkspaceSummary.totalCount == 1)
        let staleGroup = SourceChangeGroup(
            id: OME.Contributor.tableName,
            displayName: "Contributor",
            added: 1,
            modified: 0,
            deleted: 0
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
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposal = SourceProposalFlow.State(
                eventID: eventID,
                workspaceSummary: EventWorkspaceSummary(
                    eventID: eventID,
                    availability: .available,
                    groups: [staleGroup]
                ),
                patch: patch
            )
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.proposeChangeButtonTapped) {
            $0.sourceProposalStatus = .composing
        }
        #expect(store.state.sourceProposal?.eventID == eventID)
        #expect(store.state.sourceProposal?.patch == patch)
        expectNoDifference(
            store.state.sourceProposal?.sourceChangeGroups,
            expectedWorkspaceSummary.groups
        )

        await store.dismount()
    }

    @Test
    func sourceProposalFormTitleAndDescriptionCanBeEdited() async throws {
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
            $0.continuousClock = ImmediateClock()
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

        store.modify {
            $0.form.value.title = "Update the event name"
            $0.form.value.description = "Updated the event name."
        } changes: {
            $0.form.value.title = "Update the event name"
            $0.form.value.description = "Updated the event name."
        }

        await store.dismount()
    }

    @Test
    func createProposalRequiresTitleFormValidation() async throws {
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
        let publishRequests = Mutex([SourcePatchPublishRequest]())
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                publishRequests.withLock { $0.append(request) }
                return SourcePatchPublication()
            }
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

        await store.send(.createProposalButtonTapped)?.value

        expectNoDifference(store.state.status, .composing)
        expectNoDifference(publishRequests.withLock { $0 }, [])
        expectNoDifference(
            store.state.form.validation[AnyHashable(\SourceProposalFlow.FormValue.title)]?
                .errors.map(\.message),
            ["Enter a title."]
        )

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
            state.description = "Updated the event name."
            state.title = "Update the event name"
            return TestStore(initialState: state) {
                SourceProposalFlow()
            }
        }

        let task = store.send(.formSubmitted(store.state.form.value)) {
            $0.status = .proposing
        }
        await task?.value
        #expect(store.state.status == .created(publication))

        await store.dismount()
    }

    @Test
    func createdSourceProposalDismissesSheetAndReloadsTangledReviews() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
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
        let review = testTangledPullReview()
        let publication = SourcePatchPublication(
            sourceChangeID: review.uri,
            sourceChangeURL: URL(string: "https://tangled.org/woody.fm/wicked-woods/pulls")
        )
        let requests = Mutex([OpenMusicEventTangledPullReviewRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.actorIdentityLookup.resolve = { _ in
                throw URLError(.badServerResponse)
            }
            $0.tangledPullReviewClient = TangledPullReviewClient { request in
                requests.withLock { $0.append(request) }
                return [review]
            }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.sourceProposal?.status = .created(publication)
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.sourceProposal(.delegate(.created(publication)))) {
            $0.pendingCreatedTangledPullReviewID = review.uri
            $0.selectedTangledPullReview = .pending(id: review.uri)
            $0.sourceProposalStatus = .created(publication)
            $0.tangledPullReviewStatus = .loading
        }
        #expect(store.state.sourceProposal == nil)
        await store.receive(
            \.tangledPullReviewsResponse,
            .equals(.success([review])),
            timeout: .seconds(1)
        ) {
            $0.pendingCreatedTangledPullReviewID = nil
            $0.selectedTangledPullReview = .loaded(review)
            $0.tangledPullReviewStatus = .loaded([review])
        }

        expectNoDifference(
            requests.withLock { $0 },
            [
                OpenMusicEventTangledPullReviewRequest(eventID: eventID),
            ]
        )
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
            var state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.title = "Update the event name"
            return TestStore(
                initialState: SourceProposalErrorReportingHost.State(proposal: state)
            ) {
                SourceProposalErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.proposal(.formSubmitted(store.state.proposal.form.value))) {
                $0.proposal.status = .proposing
            }
            await task?.value
        }
        guard case let .failed(failure) = store.state.proposal.status else {
            #expect(Bool(false))
            return
        }
        expectNoDifference(failure.message, "Unable to create proposal.")
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.message.fallback,
            "Unable to create proposal."
        )
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.operation.rawValue,
            "source.proposal.publish"
        )

        await withIssueReporters([]) {
            let retryTask = store.send(.proposal(.formSubmitted(store.state.proposal.form.value))) {
                $0.proposal.status = .proposing
            }
            await retryTask?.value
        }
        guard case let .failed(retryFailure) = store.state.proposal.status else {
            #expect(Bool(false))
            return
        }
        expectNoDifference(retryFailure.message, "Unable to create proposal.")

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
            var state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.title = "Update the event name"
            return Store(initialState: state) {
                SourceProposalFlow()
            }
        }

        let task = store.send(.formSubmitted(store.form.value))
        await fulfillAuthorizationRequest(
            from: authorizationCenter,
            requirement: requirement
        )
        await task?.value
        #expect(store.status == .created(publication))
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
    func resetterAttachesSourceEditingBaselineToDefaultDatabase() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)

        try await database.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Updated Source Event" }
                .execute(db)
        }

        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: directoryURL.appending(path: "session.sqlite").path(),
            baselineDatabasePath: baselineDatabase.path
        )
        let changedSummary = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
        expectNoDifference(changedSummary.availability, .available)
        expectNoDifference(changedSummary.totalCount, 1)

        try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try EventWorkspaceResetter.openMusicEvent.reset(eventID)
        }

        let resetSummary = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
        let restoredEvent = try await database.read { db in
            try OME.Event.find(eventID).fetchOne(db)
        }
        expectNoDifference(restoredEvent?.name, "Source Event")
        expectNoDifference(resetSummary.availability, .available)
        expectNoDifference(resetSummary.totalCount, 0)
    }

    @Test
    func sourcePatchGenerationDoesNotCacheInlineProposal() async throws {
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
            state.sourceProposal?.title = "Update the event"
            state.sourceProposal?.description = "Describe the changes."
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        store.send(.sourcePatchGenerationResponse(.success(regeneratedPatch))) {
            $0.sourcePatchStatus = .generated(regeneratedPatch)
            $0.sourceProposalStatus = .idle
        }

        #expect(store.state.sourceProposal == nil)
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
        try await seedSourceBackedEvent(eventID, in: database)
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
    func marksSourcePatchNeedsGenerationWhenSourceWorkspaceEventInvalidates() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let sourceBaselineID = sourceBaselineID(for: eventID)
        let sourceWorkspaceEventID = testEventID("event-2")
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedAdditionalSourceBackedEvent(
            sourceWorkspaceEventID,
            sourceBaselineID: sourceBaselineID,
            in: database
        )
        let unrelatedEventInvalidation = SourcePatchInvalidation(
            eventID: testEventID("event-3"),
            operation: .update,
            tableName: OME.Contributor.tableName
        )
        let sourceWorkspaceEventInvalidation = SourcePatchInvalidation(
            eventID: sourceWorkspaceEventID,
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

        stream.continuation.yield(unrelatedEventInvalidation)
        stream.continuation.yield(sourceWorkspaceEventInvalidation)

        await store.receive(
            \.sourcePatchInvalidationReceived,
            .equals(sourceWorkspaceEventInvalidation),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .needsGeneration(sourceWorkspaceEventInvalidation)
        }

        stream.continuation.finish()
        await store.dismount()
    }

    @Test
    func workspaceAppearanceLoadsTangledPullReviewsForTangledSource() async throws {
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
            $0.actorIdentityLookup.resolve = { _ in
                throw URLError(.badServerResponse)
            }
            $0.tangledPullReviewClient = TangledPullReviewClient { request in
                requests.withLock { $0.append(request) }
                return [review]
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        #expect(store.state.tangledPullReviewStatus == .notLoaded)
        #expect(requests.withLock { $0 }.isEmpty)

        store.send(.onAppear) {
            $0.tangledPullReviewStatus = .loading
        }
        await store.receive(
            \.tangledPullReviewsResponse,
            .equals(.success([review])),
            timeout: .seconds(1)
        ) {
            $0.tangledPullReviewStatus = .loaded([review])
        }

        #expect(
            requests.withLock { $0 } == [
                OpenMusicEventTangledPullReviewRequest(eventID: eventID)
            ]
        )
        await store.dismount()
    }

    @Test
    func closeTangledPullReviewButtonRemovesReviewAfterStatusWrite() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let closedReviews = Mutex([TangledPullReview]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                close: { review in
                    closedReviews.withLock { $0.append(review) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded([review])
            initialState.tangledPullReviewSemanticDiffs[review.id] = .failed(
                EventWorkspace.TangledPullReviewSemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.closeTangledPullReviewButtonTapped(review)) {
            $0.closingTangledPullReviewIDs = [review.id]
        }
        await store.receive(
            \.tangledPullReviewCloseResponse,
            .matching { (
                response: (
                    review: TangledPullReview,
                    Result<Void, EventWorkspace.TangledPullReviewCloseFailure>
                )
            ) in
                guard response.review == review else { return false }
                guard case .success = response.1 else { return false }
                return true
            },
            timeout: .seconds(1)
        ) {
            $0.closingTangledPullReviewIDs = []
            $0.locallyRemovedTangledPullReviewIDs = [review.id]
            $0.tangledPullReviewCloseFailures = [:]
            $0.tangledPullReviewDeleteFailures = [:]
            $0.tangledPullReviewSemanticDiffs = [:]
            $0.tangledPullReviewStatus = .loaded([])
        }
        await task?.value

        expectNoDifference(closedReviews.withLock { $0 }, [review])
        await store.dismount()
    }

    @Test
    func mergeTangledPullReviewButtonRemovesReviewAfterMerge() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let mergedRequests = Mutex([OpenMusicEventTangledPullReviewMergeRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                merge: { request in
                    mergedRequests.withLock { $0.append(request) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded([review])
            initialState.tangledPullReviewMergeFailures[review.id] =
                EventWorkspace.TangledPullReviewMergeFailure(TestCloseFailure.mergeFailed)
            initialState.tangledPullReviewSemanticDiffs[review.id] = .failed(
                EventWorkspace.TangledPullReviewSemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.mergeTangledPullReviewButtonTapped(review)) {
            $0.mergingTangledPullReviewIDs = [review.id]
            $0.tangledPullReviewMergeFailures = [:]
        }
        await store.receive(
            \.tangledPullReviewMergeResponse,
            .matching { (
                response: (
                    review: TangledPullReview,
                    Result<Void, EventWorkspace.TangledPullReviewMergeFailure>
                )
            ) in
                guard response.review == review else { return false }
                guard case .success = response.1 else { return false }
                return true
            },
            timeout: .seconds(1)
        ) {
            $0.mergingTangledPullReviewIDs = []
            $0.locallyRemovedTangledPullReviewIDs = [review.id]
            $0.tangledPullReviewCloseFailures = [:]
            $0.tangledPullReviewDeleteFailures = [:]
            $0.tangledPullReviewMergeFailures = [:]
            $0.tangledPullReviewSemanticDiffs = [:]
            $0.tangledPullReviewStatus = .loaded([])
        }
        await task?.value

        expectNoDifference(
            mergedRequests.withLock { $0 },
            [
                OpenMusicEventTangledPullReviewMergeRequest(
                    eventID: eventID,
                    review: review
                )
            ]
        )
        await store.dismount()
    }

    @Test
    func mountKeepsLocallyRemovedTangledPullReviewHidden() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods",
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
        let review = testTangledPullReview()
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.actorIdentityLookup.resolve = { _ in
                throw URLError(.badServerResponse)
            }
            $0.tangledPullReviewClient = TangledPullReviewClient { _ in
                [review]
            }
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.locallyRemovedTangledPullReviewIDs = [review.id]
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        #expect(store.state.tangledPullReviewStatus == .notLoaded)

        store.send(.onAppear) {
            $0.tangledPullReviewStatus = .loading
        }
        await store.receive(
            \.tangledPullReviewsResponse,
            .equals(.success([review])),
            timeout: .seconds(1)
        ) {
            $0.tangledPullReviewStatus = .loaded([])
        }

        await store.dismount()
    }

    @Test
    func deleteTangledPullReviewForeverButtonRemovesReviewBeforeRecordDelete() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let deletedReviews = Mutex([TangledPullReview]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                delete: { review in
                    deletedReviews.withLock { $0.append(review) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded([review])
            initialState.tangledPullReviewCloseFailures[review.id] =
                EventWorkspace.TangledPullReviewCloseFailure(TestCloseFailure.closeFailed)
            initialState.tangledPullReviewSemanticDiffs[review.id] = .failed(
                EventWorkspace.TangledPullReviewSemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.deleteTangledPullReviewForeverButtonTapped(review)) {
            $0.deletingTangledPullReviewIDs = [review.id]
            $0.locallyRemovedTangledPullReviewIDs = [review.id]
            $0.pendingDeletedTangledPullReviews = [
                review.id: EventWorkspace.PendingDeletedTangledPullReview(
                    review: review,
                    index: 0
                )
            ]
            $0.tangledPullReviewCloseFailures = [:]
            $0.tangledPullReviewDeleteFailures = [:]
            $0.tangledPullReviewSemanticDiffs = [:]
            $0.tangledPullReviewStatus = .loaded([])
        }
        await store.receive(
            \.tangledPullReviewDeleteResponse,
            .matching { (
                response: (
                    review: TangledPullReview,
                    Result<Void, EventWorkspace.TangledPullReviewDeleteFailure>
                )
            ) in
                guard response.review == review else { return false }
                guard case .success = response.1 else { return false }
                return true
            },
            timeout: .seconds(1)
        ) {
            $0.deletingTangledPullReviewIDs = []
            $0.pendingDeletedTangledPullReviews = [:]
        }
        await task?.value

        expectNoDifference(deletedReviews.withLock { $0 }, [review])
        await store.dismount()
    }

    @Test
    func deleteTangledPullReviewForeverButtonRestoresReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        var earlierReview = testTangledPullReview()
        earlierReview.title = "Earlier update"
        earlierReview.uri = "at://did:plc:author123/sh.tangled.repo.pull/2pull"
        let reviews = [earlierReview, review]
        let failure = EventWorkspace.TangledPullReviewDeleteFailure(
            TestCloseFailure.deleteFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in reviews },
                delete: { _ in
                    throw TestCloseFailure.deleteFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded(reviews)
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.deleteTangledPullReviewForeverButtonTapped(review)) {
                $0.deletingTangledPullReviewIDs = [review.id]
                $0.locallyRemovedTangledPullReviewIDs = [review.id]
                $0.pendingDeletedTangledPullReviews = [
                    review.id: EventWorkspace.PendingDeletedTangledPullReview(
                        review: review,
                        index: 1
                    )
                ]
                $0.tangledPullReviewStatus = .loaded([earlierReview])
            }
            await store.receive(
                \.tangledPullReviewDeleteResponse,
                .matching { (
                    response: (
                        review: TangledPullReview,
                        Result<Void, EventWorkspace.TangledPullReviewDeleteFailure>
                    )
                ) in
                    guard response.review == review else { return false }
                    guard case .failure(failure) = response.1 else { return false }
                    return true
                },
                timeout: .seconds(1)
            ) {
                $0.deletingTangledPullReviewIDs = []
                $0.locallyRemovedTangledPullReviewIDs = []
                $0.pendingDeletedTangledPullReviews = [:]
                $0.tangledPullReviewDeleteFailures[review.id] = failure
                $0.tangledPullReviewStatus = .loaded([earlierReview, review])
            }
            await task?.value
        }

        await store.dismount()
    }

    @Test
    func closeTangledPullReviewButtonKeepsReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let failure = EventWorkspace.TangledPullReviewCloseFailure(
            TestCloseFailure.closeFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                close: { _ in
                    throw TestCloseFailure.closeFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded([review])
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.closeTangledPullReviewButtonTapped(review)) {
                $0.closingTangledPullReviewIDs = [review.id]
            }
            await store.receive(
                \.tangledPullReviewCloseResponse,
                .matching { (
                    response: (
                        review: TangledPullReview,
                        Result<Void, EventWorkspace.TangledPullReviewCloseFailure>
                    )
                ) in
                    guard response.review == review else { return false }
                    guard case .failure(failure) = response.1 else { return false }
                    return true
                },
                timeout: .seconds(1)
            ) {
                $0.closingTangledPullReviewIDs = []
                $0.tangledPullReviewCloseFailures[review.id] = failure
            }
            await task?.value
        }

        await store.dismount()
    }

    @Test
    func mergeTangledPullReviewButtonKeepsReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let failure = EventWorkspace.TangledPullReviewMergeFailure(
            TestCloseFailure.mergeFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in
                    throw TestCloseFailure.mergeFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.tangledPullReviewStatus = .loaded([review])
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.mergeTangledPullReviewButtonTapped(review)) {
                $0.mergingTangledPullReviewIDs = [review.id]
            }
            await store.receive(
                \.tangledPullReviewMergeResponse,
                .matching { (
                    response: (
                        review: TangledPullReview,
                        Result<Void, EventWorkspace.TangledPullReviewMergeFailure>
                    )
                ) in
                    guard response.review == review else { return false }
                    guard case .failure(failure) = response.1 else { return false }
                    return true
                },
                timeout: .seconds(1)
            ) {
                $0.mergingTangledPullReviewIDs = []
                $0.tangledPullReviewMergeFailures[review.id] = failure
            }
            await task?.value
        }

        await store.dismount()
    }

    @Test
    func tangledPullReviewMergeFailureIncludesHTTPResponseBody() throws {
        let body = Data(
            """
            {
              "error": "Auth",
              "message": "signature verification failed"
            }
            """.utf8
        )
        let failure = EventWorkspace.TangledPullReviewMergeFailure(
            HTTPError.httpError(403, body, HTTPFields())
        )

        #expect(failure.message == "HTTP 403: Auth: signature verification failed")
    }

    @Test
    func mergeTangledPullReviewButtonReportsFailureThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in
                    throw TestCloseFailure.mergeFailed
                }
            )
        } operation: {
            var workspace = EventWorkspace.State(eventID: eventID)
            workspace.tangledPullReviewStatus = .loaded([review])
            return Store(
                initialState: EventWorkspaceErrorReportingHost.State(workspace: workspace)
            ) {
                EventWorkspaceErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.workspace(.mergeTangledPullReviewButtonTapped(review)))
            await task?.value
        }

        expectNoDifference(
            store.errorNotifications.state.latestError?.message.fallback,
            "Unable to merge Tangled pull review."
        )
        expectNoDifference(
            store.errorNotifications.state.latestError?.operation.rawValue,
            "tangled.pull-review.merge"
        )
        expectNoDifference(
            store.workspace.tangledPullReviewMergeFailures[review.id]?.message,
            String(describing: TestCloseFailure.mergeFailed)
        )
    }

    @Test
    func mergeTangledPullReviewButtonReportsHTTPFailureBodyThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let body = Data(
            """
            {
              "error": "Auth",
              "message": "signature verification failed"
            }
            """.utf8
        )
        let error = HTTPError.httpError(403, body, HTTPFields())
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in throw error }
            )
        } operation: {
            var workspace = EventWorkspace.State(eventID: eventID)
            workspace.tangledPullReviewStatus = .loaded([review])
            return Store(
                initialState: EventWorkspaceErrorReportingHost.State(workspace: workspace)
            ) {
                EventWorkspaceErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.workspace(.mergeTangledPullReviewButtonTapped(review)))
            await task?.value
        }

        expectNoDifference(
            store.errorNotifications.state.latestError?.debugDescription,
            "HTTP 403: Auth: signature verification failed"
        )
        expectNoDifference(
            store.workspace.tangledPullReviewMergeFailures[review.id]?.message,
            "HTTP 403: Auth: signature verification failed"
        )
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

    private func seedTangledSourceBackedEvent(
        _ eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods",
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
    }

    private func seedSourceBackedEvent(
        _ eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceBaselineID = sourceBaselineID(for: eventID)
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

    private func seedAdditionalSourceBackedEvent(
        _ eventID: OME.Event.ID,
        sourceBaselineID: SourceBaselineRecord.ID,
        in database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
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

    private func seedEditingWorkspace(
        for eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceBaselineID = sourceBaselineID(for: eventID)
        try await database.write { db in
            let sourceBaseline = try #require(
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            )
            let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
            try EditingWorkspaceRecord.insert {
                workspace
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

    private func sourceBaselineID(
        for eventID: OME.Event.ID
    ) -> SourceBaselineRecord.ID {
        SourceBaselineRecord.ID(
            rawValue: "source.\(eventID.eventID.rawValue.rawValue)"
        )
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

private func testTangledPullReview() -> TangledPullReview {
    TangledPullReview(
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
}

private enum SourceProposalTestError: Equatable, Error {
    case failed
}

@Feature
private struct EventWorkspaceErrorReportingHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var workspace: EventWorkspace.State
    }

    enum Action {
        case workspace(EventWorkspace.Action)
    }

    var body: some Feature {
        Scope(\.workspace, action: \.workspace) {
            EventWorkspace()
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
private struct SourceProposalErrorReportingHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var proposal: SourceProposalFlow.State
    }

    enum Action {
        case proposal(SourceProposalFlow.Action)
    }

    var body: some Feature {
        Scope(\.proposal, action: \.proposal) {
            SourceProposalFlow()
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
        }
    }
}

private enum ResetEditsTestError: Equatable, Error {
    case failed
    case previousFailure
}

private enum TestCloseFailure: Equatable, Error {
    case closeFailed
    case deleteFailed
    case mergeFailed
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
