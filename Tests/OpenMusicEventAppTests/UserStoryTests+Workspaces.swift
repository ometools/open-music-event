import Clocks
import ATProto
import ATProtoOAuth
@preconcurrency import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import FileTree
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SourceControlClient
import SourceEditing
import SnapshotTesting
import SnapshotTestingCustomDump
import SQLiteData
import Synchronization
import SwiftUI
import TangledLexicon
import Testing
import XRPCClient

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

extension UserStoryTests {
    @Suite
    struct Workspaces {
        @MainActor
        @Test
        func wickedWoodsLoadsAdd2026ReviewFromCanonicalSource() async throws {
            let database = try UserStory.makePreparedStoryDatabase()
            let baselineDatabase = try defaultBaselineDatabase()
            let organizerID = try #require(
                OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
            )
            let calendarID = OMERecord.Calendar.ID(
                ownerID: organizerID,
                calendarID: OMERecord.Calendar.defaultID
            )
            let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
                kind: .tangled,
                reference: "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/ome-workspace",
                ref: "HEAD"
            )
            let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
            let baselineSource = try wickedWoodsSourceRepository(
                organizerID: organizerID,
                includes2026: false
            )
            let reviewSource = try wickedWoodsSourceRepository(
                organizerID: organizerID,
                includes2026: true
            )

            try await withDependencies {
                $0.context = .test
                $0.sourceReferenceDatabase = .test(database: baselineDatabase)
                $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            } operation: {
                let insertion = try OMERecord.SourceDatabaseInsertion(
                    OMERecord.SourceDatabaseInsertion.Configuration(
                        source: baselineSource,
                        organizerID: organizerID,
                        sourceProvenance: sourceProvenance
                    )
                )
                try await insertion.migrateAndInsert(into: database)
            }

            let review = TangledPullReview(
                author: "did:plc:cqqtuv75m7e5s4uj6nw4czyu",
                body: nil,
                commentCount: 0,
                createdAt: "2026-07-21T04:38:21Z",
                patchBlobs: [
                    TangledPullReview.PatchBlob(
                        cid: "bafkreidc6g4goorlyfjuhghxzjjjrzsjnmtcgtwvuco72l27snmkc2kip4",
                        createdAt: "2026-07-21T04:38:21Z",
                        index: 1,
                        mimeType: "application/gzip",
                        size: 2_404
                    )
                ],
                sourceBranch: "ome/proposal-9ada21bf-9319-4997-824b-8de5e16d9d42",
                state: "open",
                targetBranch: "main",
                targetRepositoryDID: "did:plc:7kigfdsk33g7pctdgkyldhwc",
                title: "Add 2026",
                uri: "at://did:plc:cqqtuv75m7e5s4uj6nw4czyu/sh.tangled.repo.pull/3mr4yfvvfhb2p"
            )
            let checkoutRequests = Mutex([TangledSourceCheckoutRequest]())
            let receivedDiff = Mutex<WorkspaceReviews.SemanticDiff?>(nil)
            let store: TestStore<EventWorkspace> = withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
                $0.sourceReferenceDatabase = .test(database: baselineDatabase)
                $0.sourceReferenceDatabaseMigrator = .openMusicEvent
                $0.tangledPullReviewSourceSnapshot = .openMusicEvent
                $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                    checkoutRequests.withLock { $0.append(request) }
                    try FileManager.default.createDirectory(
                        at: request.outputURL,
                        withIntermediateDirectories: true
                    )
                    let source = request.ref == review.targetBranch
                        ? baselineSource
                        : reviewSource
                    _ = try OpenMusicEventSourceRepositoryFileTree()
                        .write(source, to: request.outputURL)
                    return TangledSourceCheckout(repositoryURL: request.outputURL)
                }
            } operation: {
                TestStore(
                    initialState: EventWorkspace.State(
                        sourceBaselineID: sourceBaselineID,
                        calendarID: calendarID
                    )
                ) {
                    EventWorkspace()
                }
            }

            // The Wicked Woods workspace opens the concrete Tangled review seen in the app.
            let task = store.send(.reviews(.showChangesButtonTapped(review))) {
                $0.reviews.semanticDiffs[review.id] = .loading
            }
            await task?.value

            // The real snapshot client checks out the review branch and compares it to HEAD.
            guard case let .loaded(diff) = store.state.reviews.semanticDiffs[review.id] else {
                Issue.record(
                    "Expected Wicked Woods semantic diff response, got \(String(reflecting: store.state.reviews.semanticDiffs[review.id]))."
                )
                return
            }
            receivedDiff.withLock { $0 = diff }
            #expect(diff.totalCount == 2)
            #expect(diff.groups.contains { $0.id == "events" && $0.added == 1 })
            #expect(diff.groups.contains { $0.id == "stages" && $0.added == 1 })

            let requests = checkoutRequests.withLock { $0 }
            #expect(requests.count == 2)
            for request in requests {
                expectNoDifference(
                    request.repository,
                    TangledRepositoryReference(
                        host: "tangled.org",
                        owner: "did:plc:5df2u7ief6m6tn77jznicxob",
                        repository: "ome-workspace"
                    )
                )
                #expect(request.outputURL.lastPathComponent.hasPrefix("ome-source-clone-"))
            }
            expectNoDifference(requests.map(\.ref), ["main", review.sourceBranch!])
            let semanticDiff = try #require(receivedDiff.withLock { $0 })
            let eventGroup = try #require(
                semanticDiff.groups.first { $0.id == "events" }
            )
            let stageGroup = try #require(
                semanticDiff.groups.first { $0.id == "stages" }
            )
            let eventChange = try #require(eventGroup.records.first)
            let stageChange = try #require(stageGroup.records.first)
            #expect(
                semanticDiff.recordComparisons[eventChange]?.as(OMERecord.Event.self) != nil
            )
            #expect(
                semanticDiff.recordComparisons[stageChange]?.as(OMERecord.Stage.self) != nil
            )
            expectNoDifference(
                semanticDiff.sourceFileAttributions,
                [
                    SourceFileAttribution(
                        filePath: "events/2026/event.yml",
                        recordChangeIDs: [eventChange.id]
                    ),
                    SourceFileAttribution(
                        filePath: "events/2026/stages/stage.yml",
                        recordChangeIDs: [stageChange.id]
                    )
                ]
            )

            await store.dismount()
        }

        @available(macOS 26, *)
        @MainActor
        @Test
        func firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingLiveStore() async throws {
            let defaultDatabaseURL = FileManager.default.temporaryDirectory
                .appending(path: "testival-default.sqlite")
            try? FileManager.default.removeItem(at: defaultDatabaseURL)
            let database = try UserStory.makePreparedStoryDatabase(at: defaultDatabaseURL)
            let backend = try TestivalPullRequestBackend(database: database)
            let session = try testivalOwnerSession()
            let originalSessionStore = OpenMusicEventOAuth.sessionStore.wrappedValue
            let originalSelectedSessionID = OpenMusicEventOAuth.selectedSessionID.wrappedValue
            defer {
                OpenMusicEventOAuth.sessionStore.withLock { $0 = originalSessionStore }
                OpenMusicEventOAuth.selectedSessionID.withLock {
                    $0 = originalSelectedSessionID
                }
            }
            var sessionStore = OAuth.SessionStore()
            sessionStore.upsert(session)
            OpenMusicEventOAuth.sessionStore.withLock { $0 = sessionStore }
            OpenMusicEventOAuth.selectedSessionID.withLock { $0 = session.accountID }

            let eventID = UserStory.eventID
            let stageID = UserStory.meadowStageID
            let stageURL = try #require(URL(
                string: "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/testival-2026/stages/meadow"
            ))

            try await withDependencies {
                $0.context = .test
                $0.sourceRepositoryStorageRoot = backend.sourceRepositoryStorageRoot
                OME.prepareDependencies(&$0, database: database)
                $0.continuousClock = ImmediateClock()
                $0.date = .constant(Date(timeIntervalSince1970: 1_784_169_600))
                $0.defaultEventID = eventID
                $0[Atmosphere.Account.Client.self] = backend.accountClient
                $0[XRPC.Client.self] = .liveValue
                $0.httpClient = backend.httpClient
                $0.pdsHost = session.pdsHost
                $0.sourceControl = backend.sourceControl
                $0.tangledSSHCredentials = backend.tangledSSHCredentials
                $0.tangledRepositoryMembership = backend.tangledRepositoryMembership
                $0.tangledSourceCheckout = backend.tangledSourceCheckout
                $0.tangledPullReviewClient = backend.tangledPullReviewClient
                $0.whiteLabelSourceRegistry = backend.whiteLabelSourceRegistry
            } operation: {
                let store = Store(
                    initialState: OpenMusicEventAppRoot.State(
                        variant: .whiteLabel(backend.appConfiguration)
                    )
                ) {
                    OpenMusicEventAppRoot()
                }

                try await assertFirstLaunchAndEnterAuthoring(
                    store: store,
                    backend: backend
                )
                let editedStage = try await editStageAndGeneratePatch(
                    store: store,
                    backend: backend,
                    eventID: eventID,
                    stageID: stageID,
                    stageURL: stageURL
                )
                try await proposeMergeAndRefresh(
                    mounted: editedStage.mounted,
                    backend: backend,
                    stageID: stageID,
                    expectedGeneratedStageStatus: editedStage.sourcePatchStatus
                )
            }
        }

        @available(macOS 26, *)
        @MainActor
        private func assertFirstLaunchAndEnterAuthoring(
            store: StoreOf<OpenMusicEventAppRoot>,
            backend: TestivalPullRequestBackend
        ) async throws {
            // The user launches the Testival app for the first time, and the
            // mounted root asks the source registry where Testival lives.
            await backend.firstLaunch.waitForSourceRegistryLookup()
            #expect(store.whiteLabelRoot?.loadingPhase == .locatingSource)

            // The registry resolves Testival to its Tangled source.
            await backend.firstLaunch.releaseSourceRegistryLookup()

            // The app begins importing the configured source into the local database.
            await backend.firstLaunch.waitForSourceImport()
            await waitUntil {
                store.whiteLabelRoot?.loadingPhase == .importingSource
            }
            #expect(store.whiteLabelRoot?.loadingPhase == .importingSource)

            // Source import writes the downloaded event rows.
            await backend.firstLaunch.releaseSourceImport()

            // The app opens the imported source and mounts its team workspace.
            await waitUntil {
                store.whiteLabelRoot?.loadingPhase == .idle
                    && store.storyTeamWorkspaceDetail?.sourceBaselineID
                        == backend.sourceBaselineID
            }
            #expect(store.storyTeamWorkspaceDetail?.sourceBaselineID == backend.sourceBaselineID)

            // The downloaded team workspace is hydrated from the imported source.
            let teamWorkspace = try #require(store.storyTeamWorkspaceDetail)
            expectNoDifference(teamWorkspace.sourceBaselineID, backend.sourceBaselineID)
            expectNoDifference(teamWorkspace.organizer?.id, UserStory.organizerID)
            expectNoDifference(teamWorkspace.events.map(\.id), [UserStory.eventID])
            expectNoDifference(
                teamWorkspace.calendar?.id,
                OMERecord.Calendar.ID(
                    ownerID: UserStory.organizerID,
                    calendarID: OMERecord.Calendar.defaultID
                )
            )
            expectNoDifference(
                teamWorkspace.sourceBaseline?.sourceReference,
                "tangled.org/testival/source"
            )
            expectNoDifference(teamWorkspace.sourceBaseline?.ref, "main")

        }

        @available(macOS 26, *)
        @MainActor
        private func editStageAndGeneratePatch(
            store: StoreOf<OpenMusicEventAppRoot>,
            backend: TestivalPullRequestBackend,
            eventID: OMERecord.Event.ID,
            stageID: OMERecord.ID<OMERecord.Stage>,
            stageURL: URL
        ) async throws -> StageEditStoryResult {
            // The user opens Meadow from a Testival stage link.
            await store.send(.openURL(stageURL))?.value

            // The app routes into Meadow with authoring controls available.
            await waitUntil {
                store.storyEventViewer?.stagesViewer?.destination?.stageDetail?.stageID
                    == stageID
            }
            let mounted = try mountedEventViewerStores(from: store)
            @Bindable var eventViewerStore = mounted.eventViewer

            // The mounted Authoring feature evaluates live workspace policy before entry.
            await waitUntil {
                store.storyEventAuthoring?.admission == .available
            }
            let enterAuthoringTask = store.send(
                .destination(
                    .eventViewer(
                        .content(.authoring(.enterButtonTapped))
                    )
                )
            )
            await enterAuthoringTask?.value

            // A validated grant prepares the existing source exactly once and leaves the
            // package Workspace on its canonical editing line.
            let authoringGrant = try #require(store.storyEventAuthoring?.grant)
            expectNoDifference(
                authoringGrant.principal,
                .actor(UserStory.organizerID)
            )
            expectNoDifference(authoringGrant.role, .owner)
            await waitUntil {
                guard let phase = store.storyEventWorkspace?.phase else { return false }
                if case .ready = phase { return true }
                return false
            }
            let workspacePhase = try #require(store.storyEventWorkspace?.phase)
            guard case .ready(.canonical) = workspacePhase else {
                throw WorkspaceStoryError.unexpectedWorkspacePhase(
                    String(customDumping: workspacePhase)
                )
            }
            #expect(backend.sourceCheckoutRequests.withValue { $0.count } == 1)
            let workspaceSource = try #require(mounted.workspace.source)
            expectNoDifference(workspaceSource.database.path, backend.database.path)
            let attachedSchemas = try await workspaceSource.database.read { db in
                try Set(
                    Row.fetchAll(db, sql: "PRAGMA database_list")
                        .map { $0["name"] as String }
                )
            }
            #expect(attachedSchemas.contains("main"))
            #expect(attachedSchemas.contains(SourceEditingSession.baselineSchemaName))

            #expect(store.storyEventAuthoring?.grant?.access == .authoring(.owner))
            #expect(store.storyEventViewer?.selectedFeature == .stages)
            #expect(
                store.storyEventViewer?.stagesViewer?.destination?.stageDetail?.stageID
                == stageID
            )

            // The user edits Meadow through the mounted stage detail.
            @Bindable var stagesStore = try #require(
                eventViewerStore.spawn(\.stagesViewer)
            )
            let stageDetailStore = try #require(
                $stagesStore
                    .scope(\.destination, action: \.destination)
                    .stageDetail
                    .wrappedValue
            )
            let editTask = stageDetailStore.send(.editButtonTapped)
            await editTask?.value

            // Mount the presented child exactly as EventViewerView does. Its on-mount query then
            // loads Meadow from the workspace-provided database.
            @Bindable var stageForm = try #require(
                $eventViewerStore
                    .scope(\.destination, action: \.destination)
                    .stageForm
                    .wrappedValue
            )
            await waitUntil { stageForm.hasLoadedDraft }
            try #require(
                stageForm.hasLoadedDraft,
                "The mounted stage form did not load: \(stageForm.errorMessage ?? "no error reported")"
            )
            expectNoDifference(stageForm.form.value.name, "Meadow")
            expectNoDifference(stageForm.form.value.category, "main")
            expectNoDifference(stageForm.form.value.sortIndex, "1")
            expectNoDifference(
                stageForm.heroImageURL,
                "https://cdn.example.com/stages/meadow-hero.png"
            )
            expectNoDifference(
                stageForm.logoURL,
                "https://cdn.example.com/stages/meadow-logo.png"
            )

            // The user changes public stage data that should become the pull request.
            $stageForm.form.value.name.wrappedValue = "Meadow Workshop"
            $stageForm.form.value.category.wrappedValue = "workshop"
            $stageForm.form.value.sortIndex.wrappedValue = "7"
            $stageForm.heroImageURL.wrappedValue =
                "https://cdn.example.com/stages/meadow-workshop-hero.png"

            // The user saves the edit into the local workspace database.
            await stageForm.send(.saveButtonTapped)?.value

            // The saved row is immediately visible from the application default database.
            let savedStage = try await backend.stage(stageID)
            expectNoDifference(savedStage.name, "Meadow Workshop")
            expectNoDifference(savedStage.category, OMERecord.Stage.Category("workshop"))
            expectNoDifference(savedStage.imageURL?.absoluteString, "https://cdn.example.com/stages/meadow-workshop-hero.png")

            // The user switches to the Workspace tab to inspect unpublished changes.
            $eventViewerStore.selectedFeature.wrappedValue = .workspace

            // The Workspace query is the seam: it shows exactly what the local edit changed.
            let workspace = try #require(eventViewerStore.eventWorkspace)
            assertSnapshot(
                of: workspace.changes.sourceWorkspaceSummary,
                as: .customDump,
                named: "workspace-diff-before-proposal",
                testName: "firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor"
            )

            // The user checks the generated source patch before proposing it.
            let generateSourcePatchTask = eventViewerStore.send(
                .eventWorkspace(.changes(.checkChangesButtonTapped))
            )

            await generateSourcePatchTask?.value
            await flushNestedSpawnEffects()

            // The generated patch is the source-level view of the same workspace diff.
            let sourcePatchStatus = try #require(
                eventViewerStore.eventWorkspace?.changes.sourcePatchStatus
            )
            guard case .generated = sourcePatchStatus else {
                Issue.record("Expected the stage source patch to be generated.")
                return StageEditStoryResult(
                    mounted: mounted,
                    sourcePatchStatus: .notGenerated
                )
            }
            let expectedGeneratedStageStatus = sourcePatchStatus
            #expect(sourcePatchStatus == expectedGeneratedStageStatus)
            assertSnapshot(
                of: sourcePatchStatus,
                as: .customDump,
                named: "generated-stage-patch",
                testName: "firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor"
            )

            return StageEditStoryResult(
                mounted: mounted,
                sourcePatchStatus: expectedGeneratedStageStatus
            )

        }

        @available(macOS 26, *)
        @MainActor
        private func proposeMergeAndRefresh(
            mounted: MountedEventViewerStores,
            backend: TestivalPullRequestBackend,
            stageID: OMERecord.ID<OMERecord.Stage>,
            expectedGeneratedStageStatus: WorkspaceChanges.SourcePatchStatus
        ) async throws {
            @Bindable var eventViewerStore = mounted.eventViewer

            // The user starts a proposal from the generated patch.
            let proposeChangeTask = eventViewerStore.send(
                .eventWorkspace(.changes(.proposeChangesButtonTapped))
            )

            await proposeChangeTask?.value
            await flushNestedSpawnEffects()
            #expect(
                eventViewerStore.eventWorkspace?.changes.sourcePatchStatus
                    == expectedGeneratedStageStatus
            )
            #expect(eventViewerStore.eventWorkspace?.changes.proposalDraft != nil)

            // The draft carries the current workspace diff and only presentation input.
            let proposalDraft = try #require(
                eventViewerStore.eventWorkspace?.changes.proposalDraft
            )
            let currentSummary = try #require(
                eventViewerStore.eventWorkspace?.changes.sourceWorkspaceSummary
            )
            expectNoDifference(
                proposalDraft.groups,
                currentSummary.groups
            )
            expectNoDifference(
                proposalDraft.recordComparisons,
                currentSummary.recordComparisons
            )

            // The user writes a clear PR title and description.
            await eventViewerStore.send(
                .eventWorkspace(
                    .changes(
                        .proposalDraft(.titleChanged("Update Meadow stage details"))
                    )
                )
            )?.value
            await eventViewerStore.send(
                .eventWorkspace(
                    .changes(
                        .proposalDraft(
                            .descriptionChanged(
                                "Renames Meadow and updates the stage image."
                            )
                        )
                    )
                )
            )?.value
            expectNoDifference(
                eventViewerStore.eventWorkspace?.changes.proposalDraft?.title,
                "Update Meadow stage details"
            )

            // The user publishes the proposal.
            let publishProposalTask = eventViewerStore.send(
                .eventWorkspace(
                    .changes(
                        .proposalDraft(.createProposalButtonTapped)
                    )
                )
            )

            // Tangled creates a pull request from the generated source patch.
            await publishProposalTask?.value
            await flushNestedSpawnEffects()
            await waitUntil {
                guard case .ready(.proposal) = mounted.workspace.phase else { return false }
                return true
            }
            #expect(eventViewerStore.eventWorkspace?.changes.proposalDraft == nil)

            // The Workspace reloads reviews and lands on the newly created pull request.
            #expect(eventViewerStore.eventWorkspace?.reviews.pendingCreatedReviewID == nil)
            #expect(
                eventViewerStore.eventWorkspace?.reviews.selectedReview
                    == .loaded(backend.createdReview)
            )
            #expect(
                eventViewerStore.eventWorkspace?.reviews.reviewsStatus
                    == .loaded([backend.createdReview])
            )
            expectNoDifference(
                backend.publicationOperations.value,
                [
                    "resolve target repository",
                    "clone canonical source",
                    "open proposal checkout",
                    "stage captured changes",
                    "commit captured changes",
                    "create proposal branch",
                    "open proposal checkout",
                    "push proposal branch",
                    "resolve target repository",
                    "format committed patch",
                    "upload proposal patch",
                    "record proposal",
                ]
            )

            // The user opens the semantic review diff for the created pull request.
            let reviewSemanticDiffTask = eventViewerStore.send(
                .eventWorkspace(
                    .reviews(
                        .showChangesButtonTapped(backend.createdReview)
                    )
                )
            )

            await reviewSemanticDiffTask?.value
            await flushNestedSpawnEffects()

            // The review diff shows the same stage change that came from the local edit.
            let semanticDiffStatus = eventViewerStore.eventWorkspace?
                .reviews.semanticDiffs[backend.createdReview.id]
            guard case let .loaded(semanticDiff) = try #require(semanticDiffStatus) else {
                Issue.record("Expected the created review semantic diff to load.")
                return
            }
            #expect(semanticDiff.totalCount == 1)
            assertSnapshot(
                of: semanticDiffStatus,
                as: .customDump,
                named: "created-review-semantic-diff",
                testName: "firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor"
            )

            // The user merges the pull request.
            let mergePullReviewTask = eventViewerStore.send(
                .eventWorkspace(
                    .reviews(
                        .approveButtonTapped(backend.createdReview)
                    )
                )
            )

            // The merged review is removed from the review list.
            await mergePullReviewTask?.value
            await flushNestedSpawnEffects()
            await waitUntil {
                eventViewerStore.eventWorkspace?
                    .changes.sourceWorkspaceSummary.totalCount == 0
            }
            let directlyQueriedSummary = try SourceWorkspaceSummary.query(
                target: .event(UserStory.eventID),
                using: try #require(mounted.workspace.source).database
            )
            expectNoDifference(directlyQueriedSummary.totalCount, 0)
            expectNoDifference(
                eventViewerStore.eventWorkspace?.changes.sourceWorkspaceSummary,
                directlyQueriedSummary
            )
            let mergedWorkspacePhase = mounted.workspace.phase
            guard case .ready(.canonical) = mergedWorkspacePhase else {
                throw WorkspaceStoryError.unexpectedWorkspacePhase(
                    String(customDumping: mergedWorkspacePhase)
                )
            }
            #expect(
                eventViewerStore.eventWorkspace?
                    .reviews.reviewOperations[backend.createdReview.id] == nil
            )
            #expect(eventViewerStore.eventWorkspace?.reviews.selectedReview == nil)

            // The refreshed source contains the merged stage edit.
            let refreshedStage = try await backend.stage(stageID)
            expectNoDifference(refreshedStage.name, "Meadow Workshop")
            expectNoDifference(refreshedStage.imageURL?.absoluteString, "https://cdn.example.com/stages/meadow-workshop-hero.png")

            // The Workspace no longer has unpublished local changes after the source refresh.
            let refreshedWorkspace = try #require(eventViewerStore.eventWorkspace)
            assertSnapshot(
                of: refreshedWorkspace.changes.sourceWorkspaceSummary,
                as: .customDump,
                named: "workspace-after-merge-refresh",
                testName: "firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor"
            )

        }

    }
}

@available(macOS 26, *)
@MainActor
private func mountedEventViewerStores(
    from rootStore: StoreOf<OpenMusicEventAppRoot>
) throws -> MountedEventViewerStores {
    @Bindable var rootStore = rootStore
    let eventAuthoringStore = try #require(
        $rootStore
            .scope(\.destination, action: \.destination)
            .eventViewer
            .wrappedValue
    )
    let authoringWorkspaceStore = eventAuthoringStore.scope(
        \.content,
        action: \.content
    )
    let authoringStore = authoringWorkspaceStore.scope(
        \.authoring,
        action: \.authoring
    )
    let workspaceStore = authoringStore.scope(
        \.content,
        action: \.content
    )
    let eventViewerStore = workspaceStore.scope(
        \.content,
        action: \.content
    )
    return MountedEventViewerStores(
        authorization: eventAuthoringStore,
        authoringWorkspace: authoringWorkspaceStore,
        authoring: authoringStore,
        workspace: workspaceStore,
        eventViewer: eventViewerStore
    )
}

@available(macOS 26, *)
@MainActor
private struct MountedEventViewerStores {
    let authorization: StoreOf<OpenMusicEventEventAuthoring>
    let authoringWorkspace: StoreOf<OpenMusicEventAuthoringWorkspace<EventViewer>>
    let authoring: StoreOf<OpenMusicEventAuthoringWorkspace<EventViewer>.AuthoringFeature>
    let workspace: StoreOf<OpenMusicEventAuthoringWorkspace<EventViewer>.WorkspaceFeature>
    let eventViewer: StoreOf<EventViewer>
}

@available(macOS 26, *)
@MainActor
private struct StageEditStoryResult {
    let mounted: MountedEventViewerStores
    let sourcePatchStatus: WorkspaceChanges.SourcePatchStatus
}

private extension OpenMusicEventAppRoot.State {
    var storyTeamWorkspaceSpawn: Spawn<WhiteLabelRoot.TeamWorkspace>? {
        whiteLabelRoot?.state.teamWorkspaceDetail
    }

    var storyTeamWorkspaceDetail: TeamWorkspaceDetail.State? {
        get {
            whiteLabelRoot?.state.teamWorkspaceDetail?.state.content.authoring.content.content
        }
        set {
            guard let newValue else { return }
            whiteLabelRoot?.state.teamWorkspaceDetail?.state.content.authoring.content.content =
                newValue
        }
    }

    var storyEventAuthoring:
        OpenMusicEventAuthoringWorkspace<EventViewer>.AuthoringFeature.State?
    {
        eventViewer?.content.authoring
    }

    var storyEventWorkspace:
        OpenMusicEventAuthoringWorkspace<EventViewer>.WorkspaceFeature.State?
    {
        get {
            eventViewer?.content.authoring.content
        }
        set {
            guard let newValue else { return }
            eventViewer?.content.authoring.content = newValue
        }
    }

    var storyEventViewer: EventViewer.State? {
        get {
            eventViewer?.content.authoring.content.content
        }
        set {
            guard let newValue else { return }
            eventViewer?.content.authoring.content.content = newValue
        }
    }

    var storyStageDetailSpawn: Spawn<StageDetail>? {
        eventViewer?
            .content
            .authoring
            .content
            .content
            .stagesViewer?
            .state
            .destination?
            .stageDetail
    }

    var storyStageForm: EditStage.State? {
        eventViewer?
            .content
            .authoring
            .content
            .content
            .destination?
            .stageForm
    }

}

private func wickedWoodsSourceRepository(
    organizerID: OMERecord.Organizer.ID,
    includes2026: Bool
) throws -> OpenMusicEventSourceRepository {
    let timeZone = try #require(TimeZone(identifier: "America/Edmonton"))
    var events = [
        DirectoryContent(
            directoryName: "2025",
            components: OpenMusicEventSourceEvent(
                event: EventDTO(
                    id: OMERecord.Event.ID(
                        organizerID: organizerID,
                        eventID: OMERecord.ID("2025")
                    ),
                    name: "Wicked Woods 2025",
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
    if includes2026 {
        events.append(
            DirectoryContent(
                directoryName: "2026",
                components: OpenMusicEventSourceEvent(
                    event: EventDTO(
                        id: OMERecord.Event.ID(
                            organizerID: organizerID,
                            eventID: OMERecord.ID("2026")
                        ),
                        name: "Wicked Woods 2026",
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
        )
    }
    return OpenMusicEventSourceRepository(events: events)
}

private func flushNestedSpawnEffects() async {
    await Task.yield()
    await Task.yield()
}

private func testivalOwnerSession() throws -> OAuth.Session {
    let organizerID = UserStory.organizerID
    var grantedPermissions: Set<OAuth.Permission> = [.atproto]
    grantedPermissions.formUnion(
        OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions
    )
    return OAuth.Session(
        accountID: Atmosphere.Account.ID(organizerID),
        pdsHost: "publisher.pds.example",
        tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
            try #require(URL(string: "https://publisher.pds.example/oauth/token"))
        ),
        scope: OAuth.Scope(
            rawValue: grantedPermissions
                .map(\.rawValue)
                .sorted()
                .joined(separator: " ")
        ),
        accessToken: OAuth.AccessToken(rawValue: "testival-owner-access-token"),
        refreshToken: OAuth.RefreshToken(rawValue: "testival-owner-refresh-token"),
        dpopKey: OAuth.DPOP.Key()
    )
}

@MainActor
private func waitUntil(
    _ condition: @escaping () async -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<1_000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Condition was not satisfied", sourceLocation: sourceLocation)
}

private enum WorkspaceStoryError: Error {
    case unexpectedWorkspacePhase(String)
}

private actor TestivalFirstLaunch {
    private var sourceImportReached = false
    private var sourceImportReleased = false
    private var sourceImportCompleted = false
    private var sourceImportCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceImportReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceImportWaiters: [CheckedContinuation<Void, Never>] = []

    private var sourceRegistryLookupReached = false
    private var sourceRegistryLookupReleased = false
    private var sourceRegistryLookupReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceRegistryLookupWaiters: [CheckedContinuation<Void, Never>] = []

    func reachSourceImport() async {
        sourceImportReached = true
        sourceImportWaiters.forEach { $0.resume() }
        sourceImportWaiters.removeAll()
        await waitForSourceImportRelease()
    }

    func reachSourceRegistryLookup() async {
        sourceRegistryLookupReached = true
        sourceRegistryLookupWaiters.forEach { $0.resume() }
        sourceRegistryLookupWaiters.removeAll()
        await waitForSourceRegistryLookupRelease()
    }

    func finishSourceImport() {
        sourceImportCompleted = true
        sourceImportCompletionWaiters.forEach { $0.resume() }
        sourceImportCompletionWaiters.removeAll()
    }

    func releaseSourceImport() async {
        sourceImportReleased = true
        sourceImportReleaseWaiters.forEach { $0.resume() }
        sourceImportReleaseWaiters.removeAll()
        await waitForSourceImportCompletion()
        await Task.yield()
    }

    func releaseSourceRegistryLookup() {
        sourceRegistryLookupReleased = true
        sourceRegistryLookupReleaseWaiters.forEach { $0.resume() }
        sourceRegistryLookupReleaseWaiters.removeAll()
    }

    func waitForSourceImport() async {
        guard !sourceImportReached else { return }
        await withCheckedContinuation {
            sourceImportWaiters.append($0)
        }
    }

    func waitForSourceRegistryLookup() async {
        guard !sourceRegistryLookupReached else { return }
        await withCheckedContinuation {
            sourceRegistryLookupWaiters.append($0)
        }
    }

    private func waitForSourceImportRelease() async {
        guard !sourceImportReleased else { return }
        await withCheckedContinuation {
            sourceImportReleaseWaiters.append($0)
        }
    }

    private func waitForSourceImportCompletion() async {
        guard !sourceImportCompleted else { return }
        await withCheckedContinuation {
            sourceImportCompletionWaiters.append($0)
        }
    }

    private func waitForSourceRegistryLookupRelease() async {
        guard !sourceRegistryLookupReleased else { return }
        await withCheckedContinuation {
            sourceRegistryLookupReleaseWaiters.append($0)
        }
    }
}

private struct TestivalPullRequestBackend {
    let accountClient: Atmosphere.Account.Client
    let appConfiguration: WhiteLabelAppConfiguration
    let createdReview: TangledPullReview
    let database: any DatabaseWriter
    let firstLaunch: TestivalFirstLaunch
    let httpClient: HTTPClient
    let publicationOperations: LockIsolated<[String]>
    let sourceBaselineID: SourceBaselineRecord.ID
    let sourceCheckoutRequests: LockIsolated<[TangledSourceCheckoutRequest]>
    let sourceControl: SourceControlClient
    let sourceRepositoryStorageRoot: SourceRepositoryStorageRootClient
    let tangledRepositoryMembership: TangledRepositoryMembershipClient
    let tangledSSHCredentials: TangledSSHCredentialsClient
    let tangledSourceCheckout: TangledSourceCheckoutClient
    let tangledPullReviewClient: TangledPullReviewClient
    let whiteLabelSourceRegistry: WhiteLabelSourceRegistryClient

    init(database: any DatabaseWriter) throws {
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/testival/source",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let proposalBranch = "ome/proposal-00000000-0000-0000-0000-000000000001"
        let proposalURI =
            "at://did:web:example.com/sh.tangled.repo.pull/"
            + "ome-00000000000000000000000000000001"
        let createdReview = TangledPullReview(
            author: "did:web:example.com",
            body: "Renames Meadow and updates the stage image.",
            commentCount: 0,
            createdAt: "2026-07-16T12:00:00Z",
            patchBlobs: [],
            sourceBranch: proposalBranch,
            sourceRepositoryDID: nil,
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:testival-source",
            title: "Update Meadow stage details",
            uri: proposalURI,
        )
        let firstLaunch = TestivalFirstLaunch()
        let reviews = LockIsolated<[TangledPullReview]>([])
        let proposalSource = LockIsolated<OpenMusicEventSourceRepository?>(nil)
        let publicationOperations = LockIsolated<[String]>([])
        let sourceCheckoutRequests = LockIsolated<[TangledSourceCheckoutRequest]>([])
        let remoteMerged = LockIsolated(false)
        let sourceRepositoryStorageURL = FileManager.default.temporaryDirectory
            .appending(
                path: "testival-source-repositories-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let sourceRepositoryStorageRoot = SourceRepositoryStorageRootClient.rooted(
            at: sourceRepositoryStorageURL
        )

        self.appConfiguration = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Testival"),
            organizerID: UserStory.organizerID
        )
        self.accountClient = try .testival()
        self.createdReview = createdReview
        self.database = database
        self.firstLaunch = firstLaunch
        self.httpClient = HTTPClient { request, _ in
            switch request.url?.host {
            case "testival-owner.pds.example":
                publicationOperations.withValue { $0.append("resolve target repository") }
                return Data(
                    """
                    {
                      "records": [
                        {
                          "uri": "at://did:plc:testival-owner/sh.tangled.repo/source",
                          "cid": "bafyreitestivalsource",
                          "value": {
                            "$type": "sh.tangled.repo",
                            "name": "source",
                            "repoDid": "did:plc:testival-source",
                            "knot": "knot1.tangled.sh",
                            "createdAt": "2026-07-16T12:00:00Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )

            case "publisher.pds.example":
                if request.url?.path.hasSuffix("/com.atproto.repo.uploadBlob") == true {
                    publicationOperations.withValue { $0.append("upload proposal patch") }
                    return Data(
                        """
                        {
                          "blob": {
                            "$type": "blob",
                            "ref": {"$link": "bafkreitestivalpatch"},
                            "mimeType": "application/gzip",
                            "size": 321
                          }
                        }
                        """
                        .utf8
                    )
                }
                if request.url?.path.hasSuffix("/com.atproto.repo.putRecord") == true {
                    publicationOperations.withValue { $0.append("record proposal") }
                    reviews.withValue { $0 = [createdReview] }
                    return Data(
                        """
                        {
                          "uri": "\(proposalURI)",
                          "cid": "bafyreitestivalpull"
                        }
                        """
                        .utf8
                    )
                }
                throw WorkspaceStoryBackendError.unexpectedRequest(
                    request.url?.absoluteString ?? "missing URL"
                )

            default:
                throw WorkspaceStoryBackendError.unexpectedRequest(
                    request.url?.absoluteString ?? "missing URL"
                )
            }
        }
        self.publicationOperations = publicationOperations
        self.sourceBaselineID = sourceBaselineID
        self.sourceCheckoutRequests = sourceCheckoutRequests
        self.sourceControl = SourceControlClient(
            clone: { request in
                publicationOperations.withValue { $0.append("clone canonical source") }
                try FileManager.default.createDirectory(
                    at: request.destinationURL,
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    try Self.sourceRepository(
                        meadowName: "Meadow",
                        meadowCategory: OMERecord.Stage.Category("main"),
                        meadowSortIndex: 1,
                        meadowHeroURLString: "https://cdn.example.com/stages/meadow-hero.png"
                    ),
                    to: request.destinationURL
                )
                return Repository(url: request.destinationURL)
            },
            open: { url in
                publicationOperations.withValue { $0.append("open proposal checkout") }
                return Repository(url: url)
            },
            fetch: { _ in },
            checkout: { _ in },
            createBranch: { request in
                publicationOperations.withValue { $0.append("create proposal branch") }
                expectNoDifference(request.name.rawValue, proposalBranch)
                return Branch(name: request.name)
            },
            status: { _ in [] },
            stage: { request in
                publicationOperations.withValue { $0.append("stage captured changes") }
                #expect(!request.paths.isEmpty)
            },
            commit: { request in
                publicationOperations.withValue { $0.append("commit captured changes") }
                expectNoDifference(
                    request.message.rawValue,
                    "Update Meadow stage details"
                )
                return Commit(
                    id: CommitID(rawValue: "fedcbafedcbafedcbafedcbafedcbafedcbafedc")
                )
            },
            formatPatch: { _ in
                publicationOperations.withValue { $0.append("format committed patch") }
                return Data(
                    """
                    diff --git a/events/testival-2026/stages/meadow.yml b/events/testival-2026/stages/meadow.yml
                    --- a/events/testival-2026/stages/meadow.yml
                    +++ b/events/testival-2026/stages/meadow.yml
                    @@ -1 +1 @@
                    -name: Meadow
                    +name: Meadow Workshop

                    """.utf8
                )
            },
            push: { request in
                publicationOperations.withValue { $0.append("push proposal branch") }
                expectNoDifference(request.localBranch.rawValue, proposalBranch)
                expectNoDifference(request.remoteBranch.rawValue, proposalBranch)
                let source = try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: request.repository.url)
                    .output
                    .requiredValue
                proposalSource.withValue { $0 = source }
            }
        )
        self.sourceRepositoryStorageRoot = sourceRepositoryStorageRoot
        self.tangledRepositoryMembership = TangledRepositoryMembershipClient {
            _, expectedOwnerID, actorID in
                let organizerID = UserStory.organizerID
                return expectedOwnerID == organizerID && actorID == organizerID
        }
        self.tangledSSHCredentials = TangledSSHCredentialsClient {
            Credentials(
                ssh: SSHCredentials(
                    publicKey: "ssh-ed25519 testival-public-key Open Music Event",
                    privateKey: "testival-private-key"
                )
            )
        }
        self.tangledSourceCheckout = TangledSourceCheckoutClient { request in
            sourceCheckoutRequests.withValue { $0.append(request) }
            if request.ref == "main" {
                await firstLaunch.reachSourceImport()
            }
            try FileManager.default.createDirectory(
                at: request.outputURL,
                withIntermediateDirectories: true
            )
            let usesMergedSource = remoteMerged.value
                || request.ref == createdReview.sourceBranch
            let source = if usesMergedSource {
                try #require(proposalSource.value)
            } else {
                try Self.sourceRepository(
                    meadowName: "Meadow",
                    meadowCategory: OMERecord.Stage.Category("main"),
                    meadowSortIndex: 1,
                    meadowHeroURLString: "https://cdn.example.com/stages/meadow-hero.png"
                )
            }
            _ = try OpenMusicEventSourceRepositoryFileTree().write(
                source,
                to: request.outputURL
            )
            if request.ref == "main" {
                await firstLaunch.finishSourceImport()
            }
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
        self.tangledPullReviewClient = TangledPullReviewClient(
            list: { _ in reviews.value },
            merge: { _ in
                remoteMerged.withValue { $0 = true }
                reviews.withValue { $0 = [] }
            }
        )
        self.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { _ in
            await firstLaunch.reachSourceRegistryLookup()
            return WhiteLabelSourceDescriptor(
                reference: .source("https://tangled.org/testival/source"),
                version: "main"
            )
        }
    }

    private static func sourceRepository(
        meadowName: String,
        meadowCategory: OMERecord.Stage.Category,
        meadowSortIndex: Int,
        meadowHeroURLString: String
    ) throws -> OpenMusicEventSourceRepository {
        let meadowHeroURL = try #require(URL(string: meadowHeroURLString))
        let meadowLogoURL = try #require(URL(
            string: "https://cdn.example.com/stages/meadow-logo.png"
        ))
        let meadowPosterURL = try #require(URL(
            string: "https://cdn.example.com/stages/meadow-poster.png"
        ))
        let pavilionHeroURL = try #require(URL(
            string: "https://cdn.example.com/stages/pavilion-hero.png"
        ))

        return OpenMusicEventSourceRepository(
            calendar: .defaultCalendar,
            events: [
                DirectoryContent(
                    directoryName: "testival-2026",
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: UserStory.eventID,
                            name: "Testival 2026",
                            description: nil,
                            startDate: nil,
                            endDate: nil,
                            status: nil,
                            mode: nil,
                            locations: nil,
                            uris: nil,
                            timeZone: TimeZone(identifier: "America/Denver")!,
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        ),
                        stages: [
                            try FileContent(
                                fileName: "meadow",
                                fileType: nil,
                                data: StageDTO(
                                    name: meadowName,
                                    color: 0x44AA77,
                                    category: meadowCategory,
                                    sortIndex: meadowSortIndex,
                                    iconImageURL: meadowLogoURL,
                                    systemIconName: "sparkles",
                                    iconShortCode: "MD",
                                    imageURL: meadowHeroURL,
                                    posterImageURL: meadowPosterURL,
                                    lineup: nil
                                )
                            ),
                            try FileContent(
                                fileName: "pavilion",
                                fileType: nil,
                                data: StageDTO(
                                    name: "Pavilion",
                                    color: 0x336699,
                                    category: OMERecord.Stage.Category("workshop"),
                                    sortIndex: 2,
                                    iconImageURL: nil,
                                    systemIconName: "music.mic",
                                    iconShortCode: "PV",
                                    imageURL: pavilionHeroURL,
                                    posterImageURL: nil,
                                    lineup: nil
                                )
                            ),
                        ]
                    )
                )
            ]
        )
    }

    func stage(_ stageID: OMERecord.ID<OMERecord.Stage>) async throws -> OMERecord.Stage {
        return try await database.read { db in
            try #require(
                try StageDetail.stageQuery(stageID: stageID, eventID: UserStory.eventID)
                    .fetchOne(db)
            )
        }
    }
}

private enum WorkspaceStoryBackendError: Error {
    case unexpectedRequest(String)
    case unexpectedAccount(String)
}

private extension Atmosphere.Account.Client {
    static func testival() throws -> Self {
        let did = try #require(DID("did:plc:testival-owner"))
        let handle = Atmosphere.Account.Handle("testival")
        let account = Atmosphere.Account(id: .init(did), handle: handle)
        let document = try testivalDIDDocument(did: did, handle: handle)
        return Self(
            resolveHandle: { requestedHandle in
                guard requestedHandle == handle else {
                    throw WorkspaceStoryBackendError.unexpectedAccount(
                        requestedHandle.rawValue
                    )
                }
                return (account, document)
            },
            resolveDID: { requestedDID in
                guard requestedDID == did else {
                    throw WorkspaceStoryBackendError.unexpectedAccount(
                        requestedDID.description
                    )
                }
                return (account, document)
            }
        )
    }
}

private func testivalDIDDocument(
    did: DID,
    handle: Atmosphere.Account.Handle
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
                  "serviceEndpoint": "https://testival-owner.pds.example"
                }
              ]
            }
            """
            .utf8
        )
    )
}

private extension SourceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _ in URL(fileURLWithPath: database.path) },
            prepareForImport: { _ in
                StagedSourceReferenceDatabase(
                    database: database,
                    databaseFileName: URL(fileURLWithPath: database.path).lastPathComponent,
                    commit: {},
                    discard: {}
                )
            },
            existing: { _ in database }
        )
    }
}
