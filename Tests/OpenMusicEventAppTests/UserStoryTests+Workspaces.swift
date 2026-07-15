import Clocks
@preconcurrency import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import FileTree
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SourceEditing
import SnapshotTesting
import SnapshotTestingCustomDump
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

extension UserStoryTests {
    @Suite
    struct Workspaces {
        @Test
        func firstLaunchEditsAStageProposesMergesAndRefreshesSource() async throws {
            if #available(macOS 26, *) {
                try await firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor()
            }
        }

        @available(macOS 26, *)
        private func firstLaunchEditsAStageProposesMergesAndRefreshesSourceUsingTestStoreActor() async throws {
            let database = try UserStory.makePreparedStoryDatabase()
            let backend = try TestivalPullRequestBackend(database: database)

            let eventID = UserStory.eventID
            let stageID = UserStory.meadowStageID
            let stageURL = try #require(URL(
                string: "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/testival-2026/stages/meadow"
            ))

            try await withDependencies {
                $0.authoringPolicy = backend.authoringPolicy
                $0.context = .test
                $0.continuousClock = ImmediateClock()
                $0.defaultDatabase = database
                $0.defaultEventID = eventID
                $0.sourceDataRefresh = backend.sourceDataRefresh
                $0.sourceReferenceDatabase = backend.sourceReferenceDatabase
                $0.sourceReferenceDatabaseMigrator = .openMusicEvent
                $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                    SourcePatchGenerator { request in
                        #expect(
                            request == OpenMusicEventCalendarSourcePatchRequest(
                                calendarID: OMERecord.Calendar.ID(
                                    ownerID: eventID.organizerID,
                                    calendarID: OMERecord.Calendar.defaultID
                                ),
                                sourceBaselineID: backend.sourceBaselineID
                            )
                        )
                        return backend.expectedStagePatch
                    }
                $0.sourcePatchPublisher = backend.sourcePatchPublisher
                $0.tangledPullReviewClient = backend.tangledPullReviewClient
                $0.tangledPullReviewSourceSnapshot = backend.tangledPullReviewSourceSnapshot
                $0.whiteLabelSourceImport = backend.whiteLabelSourceImport
                $0.whiteLabelSourceRegistry = backend.whiteLabelSourceRegistry
            } operation: {
                let store: TestStoreActor<OpenMusicEventAppRoot> = await TestStoreActor(
                    initialState: OpenMusicEventAppRoot.State(
                        variant: .whiteLabel(backend.appConfiguration)
                    )
                ) {
                    OpenMusicEventAppRoot()
                } changes: {
                    $0.whiteLabelRoot?.isLoading = true
                    $0.whiteLabelRoot?.loadingPhase = .locatingSource
                }

            // The user launches the Testival app for the first time, and the
            // mounted root asks the source registry where Testival lives.
            await backend.firstLaunch.waitForSourceRegistryLookup()
            #expect(
                await store[dynamicMember: \.whiteLabelRoot?.loadingPhase]
                == .locatingSource
            )

            // The registry resolves Testival to its Tangled source.
            await backend.firstLaunch.releaseSourceRegistryLookup()

            // The app begins importing the configured source into the local database.
            await backend.firstLaunch.waitForSourceImport()
            await store.expect {
                $0.whiteLabelRoot?.loadingPhase = .importingSource
            }

            // Source import writes the downloaded event rows.
            await backend.firstLaunch.releaseSourceImport()

            // The app opens the imported source and mounts its team workspace.
            await store.receive(
                from: \.whiteLabelRoot,
                \.loadDataSucceeded,
                .equals(WhiteLabelRoot.LoadedRoot(
                    organizerID: UserStory.organizerID,
                    sourceBaselineIDs: [backend.sourceBaselineID]
                )),
                timeout: .seconds(1)
            ) {
                $0.whiteLabelRoot?.authoringSubject =
                    .sourceBaseline(backend.sourceBaselineID)
                $0.whiteLabelRoot?.isLoading = false
                $0.whiteLabelRoot?.loadingPhase = .idle
                $0.whiteLabelRoot?.organizerID = UserStory.organizerID
                $0.whiteLabelRoot?.teamWorkspaceDetail?.sourceBaselineID =
                    backend.sourceBaselineID
            }
            #expect(
                await store[dynamicMember: \.whiteLabelRoot?.authoringSubject]
                == .sourceBaseline(backend.sourceBaselineID)
            )
            #expect(
                await store[dynamicMember: \.whiteLabelRoot?.teamWorkspaceDetail?.sourceBaselineID]
                == backend.sourceBaselineID
            )

            // The downloaded team workspace is hydrated from the imported source.
            let teamWorkspace = try #require(
                await store[dynamicMember: \.whiteLabelRoot?.teamWorkspaceDetail?.state]
            )
            assertSnapshot(
                of: teamWorkspace,
                as: .customDump,
                named: "downloaded-team-workspace"
            )

            // The user enters authoring mode for the downloaded source workspace.
            let enterAuthoringTask = await store.send(
                to: \.whiteLabelRoot!,
                .enterAuthoringButtonTapped
            ) {
                $0.whiteLabelRoot?.isAuthoringAuthorizationInFlight = true
            }

            // The white-label root receives the authorization result and shows editing controls.
            await enterAuthoringTask?.value
            await store.expect {
                $0.whiteLabelRoot?.authoringMode = .authoring(.all)
                $0.whiteLabelRoot?.isAuthoringAuthorizationInFlight = false
            }

            // The user opens Meadow from a Testival stage link.
            await store.send(.openURL(stageURL))

            // The app routes into Meadow with authoring controls available.
            await store.receive(
                \.openRoute,
                .equals(.event(eventID, .stage(stageID))),
                timeout: .seconds(1)
            )

            #expect(
                await store[dynamicMember: \.eventViewer?.authoringMode]
                == .authoring(.all)
            )
            #expect(await store[dynamicMember: \.eventViewer?.selectedFeature] == .stages)
            #expect(
                await store[dynamicMember: \.eventViewer?.stagesViewer?.destination?.stageDetail?.stageID]
                == stageID
            )

            // The user edits Meadow through the mounted stage detail.
            let editTask = await store.send(
                to: \.eventViewer!.stagesViewer!.destination!.stageDetail!,
                .editButtonTapped
            )
            await editTask?.value

            // Meadow's form opens with the source-backed draft.
            let stageForm = try #require(
                await store[dynamicMember: \.eventViewer?.destination?.stageForm?.state]
            )
            #expect(stageForm.hasLoadedDraft)
            assertSnapshot(
                of: stageForm,
                as: .customDump,
                named: "stage-form-before-workspace-proposal"
            )

            // The user changes public stage data that should become the pull request.
            await store.modify {
                $0.eventViewer?.destination.modify(\.stageForm) {
                    $0.form.value.name = "Meadow Workshop"
                    $0.form.value.category = "workshop"
                    $0.form.value.sortIndex = "7"
                    $0.heroImageURL = "https://cdn.example.com/stages/meadow-workshop-hero.png"
                }
            }

            // The user saves the edit into the local workspace database.
            await store.send(
                to: \.eventViewer!.destination!.stageForm!,
                .saveButtonTapped
            )?.value

            // The saved row is immediately visible from the working database.
            let savedStage = try await backend.stage(stageID)
            expectNoDifference(savedStage.name, "Meadow Workshop")
            expectNoDifference(savedStage.category, OMERecord.Stage.Category("workshop"))
            expectNoDifference(savedStage.imageURL?.absoluteString, "https://cdn.example.com/stages/meadow-workshop-hero.png")

            // The user switches to the Workspace tab to inspect unpublished changes.
            await store.send(to: \.eventViewer!, .selectedFeatureChanged(.workspace))

            // The Workspace query is the seam: it shows exactly what the local edit changed.
            let workspace = try #require(
                await store[dynamicMember: \.eventViewer?.eventWorkspace?.state]
            )
            assertSnapshot(
                of: workspace.sourceWorkspaceSummary,
                as: .customDump,
                named: "workspace-diff-before-proposal"
            )

            // The user checks the generated source patch before proposing it.
            let generateSourcePatchTask = await store.send(
                to: \.eventViewer!.eventWorkspace!,
                .generateSourcePatchButtonTapped
            ) {
                $0.eventViewer?.eventWorkspace?.sourcePatchStatus = .generating
            }

            await generateSourcePatchTask?.value
            await flushNestedSpawnEffects()

            // The generated patch is the source-level view of the same workspace diff.
            let sourcePatchStatus = await store[
                dynamicMember: \.eventViewer?.eventWorkspace?.sourcePatchStatus
            ]
            #expect(sourcePatchStatus == .generated(backend.expectedStagePatch))
            assertSnapshot(
                of: sourcePatchStatus,
                as: .customDump,
                named: "generated-stage-patch"
            )

            // The user starts a proposal from the generated patch.
            await store.send(to: \.eventViewer!.eventWorkspace!, .proposeChangeButtonTapped) {
                $0.eventViewer?.eventWorkspace?.sourceProposalStatus = .composing
            }

            // The proposal composer carries the current workspace diff, not a hand-built proposal.
            let proposal = try #require(
                await store[dynamicMember: \.eventViewer?.eventWorkspace?.sourceProposal]
            )
            assertSnapshot(
                of: proposal,
                as: .customDump,
                named: "proposal-composer-before-publish"
            )

            // The user writes a clear PR title and description.
            await store.modify {
                $0.eventViewer?.eventWorkspace?.sourceProposal?.form.value.title =
                    "Update Meadow stage details"
                $0.eventViewer?.eventWorkspace?.sourceProposal?.form.value.description =
                    "Renames Meadow and updates the stage image."
            }

            let proposalFormValue = try #require(
                await store[
                    dynamicMember: \.eventViewer?.eventWorkspace?.sourceProposal?.form.value
                ]
            )

            // The user publishes the proposal.
            let publishProposalTask = await store.send(
                to: \.eventViewer!.eventWorkspace!,
                .sourceProposal(.formSubmitted(proposalFormValue))
            ) {
                $0.eventViewer?.eventWorkspace?.sourceProposalStatus = .proposing
            }

            // Tangled creates a pull request from the generated source patch.
            await publishProposalTask?.value
            await flushNestedSpawnEffects()

            // The Workspace reloads reviews with the newly created pull request.
            #expect(
                await store[dynamicMember: \.eventViewer?.eventWorkspace?.tangledPullReviewStatus]
                == .loaded([backend.createdReview])
            )

            // The user opens the semantic review diff for the created pull request.
            let reviewSemanticDiffTask = await store.send(
                to: \.eventViewer!.eventWorkspace!,
                .reviewSemanticDiffButtonTapped(backend.createdReview)
            ) {
                $0.eventViewer?.eventWorkspace?
                    .tangledPullReviewSemanticDiffs[backend.createdReview.id] = .loading
            }

            await reviewSemanticDiffTask?.value
            await flushNestedSpawnEffects()

            // The review diff shows the same stage change that came from the local edit.
            let semanticDiffStatus = await store[
                dynamicMember: \.eventViewer?.eventWorkspace?
                    .tangledPullReviewSemanticDiffs[backend.createdReview.id]
            ]
            guard case let .loaded(semanticDiff) = try #require(semanticDiffStatus) else {
                Issue.record("Expected the created review semantic diff to load.")
                return
            }
            #expect(semanticDiff.totalCount == 1)
            assertSnapshot(
                of: semanticDiffStatus,
                as: .customDump,
                named: "created-review-semantic-diff"
            )

            // The user merges the pull request.
            let mergePullReviewTask = await store.send(
                to: \.eventViewer!.eventWorkspace!,
                .mergeTangledPullReviewButtonTapped(backend.createdReview)
            ) {
                $0.eventViewer?.eventWorkspace?.mergingTangledPullReviewIDs =
                    [backend.createdReview.id]
            }

            // The merged review is removed from the review list.
            await mergePullReviewTask?.value
            await flushNestedSpawnEffects()
            #expect(
                await store[dynamicMember: \.eventViewer?.eventWorkspace?.mergingTangledPullReviewIDs]
                == []
            )

            // The refreshed source contains the merged stage edit.
            let refreshedStage = try await backend.stage(stageID)
            expectNoDifference(refreshedStage.name, "Meadow Workshop")
            expectNoDifference(refreshedStage.imageURL?.absoluteString, "https://cdn.example.com/stages/meadow-workshop-hero.png")

            // The Workspace no longer has unpublished local changes after the source refresh.
            let refreshedWorkspace = try #require(
                await store[dynamicMember: \.eventViewer?.eventWorkspace?.state]
            )
            assertSnapshot(
                of: refreshedWorkspace.sourceWorkspaceSummary,
                as: .customDump,
                named: "workspace-after-merge-refresh"
            )

            await store.dismount()
            }
        }
    }
}

private func flushNestedSpawnEffects() async {
    await Task.yield()
    await Task.yield()
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
    let appConfiguration: WhiteLabelAppConfiguration
    let authoringPolicy: AuthoringPolicyClient
    let createdPublication: SourcePatchPublication
    let createdReview: TangledPullReview
    let database: any DatabaseWriter
    let expectedStagePatch: SourcePatch
    let firstLaunch: TestivalFirstLaunch
    let sourceBaselineID: SourceBaselineRecord.ID
    let sourceDataRefresh: SourceDataRefreshClient
    let sourcePatchPublisher: SourcePatchPublisher
    let sourceReferenceDatabase: SourceReferenceDatabaseClient
    let tangledPullReviewClient: TangledPullReviewClient
    let tangledPullReviewSourceSnapshot: TangledPullReviewSourceSnapshotClient
    let whiteLabelSourceImport: WhiteLabelSourceImportClient
    let whiteLabelSourceRegistry: WhiteLabelSourceRegistryClient

    init(database: any DatabaseWriter) throws {
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/testival/source",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let expectedStagePatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/testival-2026/stages/meadow.yml",
                    kind: .modified,
                    oldContents: Data("name: Meadow\n".utf8),
                    newContents: Data("name: Meadow Workshop\n".utf8)
                )
            ]
        )
        let createdReview = TangledPullReview(
            author: "did:plc:contributor",
            body: "Renames Meadow and updates the stage image.",
            commentCount: 0,
            createdAt: "2026-07-16T12:00:00Z",
            patchBlobs: [],
            sourceBranch: "update-meadow",
            sourceRepositoryDID: "did:plc:contributor-source",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:testival",
            title: "Update Meadow stage details",
            uri: "at://did:plc:testival/app.tangled.pull.review/update-meadow",
        )
        let createdPublication = SourcePatchPublication(
            sourceChangeURL: URL(string: "https://tangled.org/testival/source/pulls/update-meadow")
        )
        let baselineDatabaseURL = FileManager.default.temporaryDirectory
            .appending(path: "testival-source-baseline.sqlite")
        try? FileManager.default.removeItem(at: baselineDatabaseURL)
        let baselineDatabase = try defaultBaselineDatabase(path: baselineDatabaseURL.path)
        let importedAt = Date(timeIntervalSince1970: 1_784_169_600)
        try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(baselineDatabase)
        let firstLaunch = TestivalFirstLaunch()
        let reviews = LockIsolated<[TangledPullReview]>([])

        self.appConfiguration = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Testival"),
            organizerID: UserStory.organizerID
        )
        self.authoringPolicy = AuthoringPolicyClient(
            authenticate: { _ in OpenMusicEventOAuth.baseAuthRequirement },
            authorize: { _ in .all },
            mode: { _ in .attendee }
        )
        self.createdPublication = createdPublication
        self.createdReview = createdReview
        self.database = database
        self.expectedStagePatch = expectedStagePatch
        self.firstLaunch = firstLaunch
        self.sourceBaselineID = sourceBaselineID
        self.sourceDataRefresh = SourceDataRefreshClient { _ in
            try await Self.applyMergedStage(to: database)
            try await Self.applyMergedStage(to: baselineDatabase.database)
        }
        self.sourceReferenceDatabase = .test(database: baselineDatabase)
        self.sourcePatchPublisher = SourcePatchPublisher { _ in
            reviews.withValue { $0 = [createdReview] }
            return createdPublication
        }
        self.tangledPullReviewClient = TangledPullReviewClient(
            list: { _ in reviews.value },
            merge: { _ in
                reviews.withValue { $0 = [] }
            }
        )
        self.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient { _ in
            return try OMERecord.SourceDatabaseInsertion(
                OMERecord.SourceDatabaseInsertion.Configuration(
                    source: try Self.sourceRepository(
                        meadowName: "Meadow Workshop",
                        meadowCategory: OMERecord.Stage.Category("workshop"),
                        meadowSortIndex: 7,
                        meadowHeroURLString: "https://cdn.example.com/stages/meadow-workshop-hero.png"
                    ),
                    organizerID: UserStory.organizerID,
                    sourceProvenance: sourceProvenance
                )
            )
        }
        self.whiteLabelSourceImport = WhiteLabelSourceImportClient { _, _ in
            await firstLaunch.reachSourceImport()
            let insertion = try OMERecord.SourceDatabaseInsertion(
                OMERecord.SourceDatabaseInsertion.Configuration(
                    source: try Self.sourceRepository(
                        meadowName: "Meadow",
                        meadowCategory: OMERecord.Stage.Category("main"),
                        meadowSortIndex: 1,
                        meadowHeroURLString: "https://cdn.example.com/stages/meadow-hero.png"
                    ),
                    organizerID: UserStory.organizerID,
                    sourceProvenance: sourceProvenance
                )
            )
            try await withDependencies {
                $0.sourceReferenceDatabase = .test(database: baselineDatabase)
                $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            } operation: {
                try await insertion.migrateAndInsert(into: database)
            }
            try await Self.stabilizeSourceImportMetadata(
                in: database,
                sourceBaselineID: sourceBaselineID,
                databaseFileName: baselineDatabaseURL.lastPathComponent,
                importedAt: importedAt
            )
            try await Self.stabilizeSourceImportMetadata(
                in: baselineDatabase.database,
                sourceBaselineID: sourceBaselineID,
                databaseFileName: baselineDatabaseURL.lastPathComponent,
                importedAt: importedAt
            )
            await firstLaunch.finishSourceImport()
            return [UserStory.eventID]
        }
        self.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { _ in
            await firstLaunch.reachSourceRegistryLookup()
            return WhiteLabelSourceDescriptor(
                reference: .source("https://tangled.org/testival/source"),
                version: "main"
            )
        }
    }

    private static func applyMergedStage(to database: any DatabaseWriter) async throws {
        let mergedHeroURL = try #require(URL(
            string: "https://cdn.example.com/stages/meadow-workshop-hero.png"
        ))
        try await database.write { db in
            var stage = try #require(
                try OMERecord.Stage
                    .find(OMERecord.Stage.ID(
                        organizerID: UserStory.eventID.organizerID,
                        eventID: UserStory.eventID.eventID,
                        stageID: UserStory.meadowStageID
                    ))
                    .fetchOne(db)
            )
            stage.name = "Meadow Workshop"
            stage.category = OMERecord.Stage.Category("workshop")
            stage.sortIndex = 7
            stage.images = (stage.images ?? [])
                .filter { $0.role != .hero }
                + [.stageHero(url: mergedHeroURL)]
            try OMERecord.Stage.update(stage).execute(db)
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

    private static func stabilizeSourceImportMetadata(
        in database: any DatabaseWriter,
        sourceBaselineID: SourceBaselineRecord.ID,
        databaseFileName: String,
        importedAt: Date
    ) async throws {
        try await database.write { db in
            try #sql("""
                UPDATE "sourceBaselines"
                SET
                  "databaseFileName" = \(bind: databaseFileName),
                  "importedAt" = \(bind: importedAt)
                WHERE "id" = \(bind: sourceBaselineID.rawValue)
                """)
                .execute(db)
            try #sql("""
                UPDATE "editingWorkspaces"
                SET
                  "databaseFileName" = \(bind: databaseFileName),
                  "createdAt" = \(bind: importedAt),
                  "updatedAt" = \(bind: importedAt)
                WHERE "sourceBaselineID" = \(bind: sourceBaselineID.rawValue)
                """)
                .execute(db)
            try #sql("""
                UPDATE "calendarEntries"
                SET "createdAt" = \(bind: importedAt)
                """)
                .execute(db)
        }
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

private extension SourceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _ in URL(fileURLWithPath: database.path) },
            prepareForImport: { _ in database },
            existing: { _ in database }
        )
    }
}
