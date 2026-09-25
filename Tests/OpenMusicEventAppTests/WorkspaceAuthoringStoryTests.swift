import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import ComposableNotifications
import ComposableWorkspace
import CustomDump
import Crypto
import Dependencies
import FileTree
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import IssueReporting
import OpenMusicEventAuthentication
@testable import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SourceControlClient
import SQLiteData
import Sharing
import SourceEditing
import Synchronization
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@Suite
struct WorkspaceChangePresentationTests {
    struct Focus: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    struct Image: Equatable, Sendable {
        var role: String
        var focalPoint: Focus?
    }

    @Test
    func `equal collection counts show their generic structural difference`() throws {
        let baselineJSON = #"[{"role":"logo"},{"role":"hero","focalPoint":{"x":0.5,"y":0.5}}]"#
        let workingJSON = #"[{"role":"logo"},{"role":"hero","focalPoint":{"x":0.25,"y":0.75}}]"#
        let fieldChange = SourceFieldChange(
            columnName: "images",
            baselineValue: baselineJSON.databaseValue,
            workingValue: workingJSON.databaseValue
        )
        let comparison = AnySourceFieldComparison(
            SourceFieldComparison(
                change: fieldChange,
                baseline: [
                    Image(role: "logo", focalPoint: nil),
                    Image(role: "hero", focalPoint: Focus(x: 0.5, y: 0.5)),
                ],
                working: [
                    Image(role: "logo", focalPoint: nil),
                    Image(role: "hero", focalPoint: Focus(x: 0.25, y: 0.75)),
                ]
            )
        )
        let difference = try #require(comparison.difference)

        expectNoDifference(
            fieldChange.baselineValue.sourceDisplayValue(columnName: "images"),
            "2 items"
        )
        expectNoDifference(
            fieldChange.workingValue.sourceDisplayValue(columnName: "images"),
            "2 items"
        )
        expectNoDifference(
            fieldChange.sourcePresentation(kind: .modified, comparison: comparison),
            .structuralDifference(difference)
        )
        #expect(difference.contains("focalPoint"))
        #expect(difference.contains("0.25"))
        #expect(difference.contains("0.75"))
        expectNoDifference(
            fieldChange.sourcePresentation(kind: .modified, comparison: nil),
            .hidden
        )
    }

    @MainActor
    @Test
    func `Contributor uses the app style while Stage keeps the static type fallback`() {
        let record = SourceRecordChange(
            tableID: "records",
            kind: .modified,
            primaryKeyValues: [],
            fieldChanges: []
        )
        let group = SourceChangeGroup(
            id: "records",
            displayName: "Records",
            added: 0,
            modified: 1,
            deleted: 0,
            records: [record]
        )
        let contributor = AnySourceRecordComparison(
            SourceRecordComparison<OMERecord.Contributor>(
                change: record,
                left: nil,
                right: nil
            )
        )
        let stage = AnySourceRecordComparison(
            SourceRecordComparison<OMERecord.Stage>(
                change: record,
                left: nil,
                right: nil
            )
        )
        let style = SourceRecordComparisonStyle.openMusicEvent

        #expect(
            style.row(
                group: group,
                record: record,
                fieldComparisons: .empty,
                comparison: contributor
            ) != nil
        )
        #expect(
            style.row(
                group: group,
                record: record,
                fieldComparisons: .empty,
                comparison: stage
            ) == nil
        )
        expectNoDifference(
            SourceRecordChangeRow(
                group: group,
                record: record,
                fieldComparisons: .empty,
                comparison: stage
            ).fallbackTitle,
            "Stage"
        )
    }
}

@MainActor
@Suite(.serialized)
struct WorkspaceAuthoringStoryTests {
    @Test
    func `proposal details survive transparent reconciliation and close for conflict recovery`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:proposalreconciliation")
        )
        let actorID = try #require(DID(organizerID.description))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/proposalreconciliation/ome-workspace",
            branch: "main"
        )
        let eventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "proposal-reconciliation"
        )
        let baseline = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "baseline")
        )
        let upstream = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "upstream")
        )
        let workspaceState = Shared(
            value: WorkspaceState<SourceWorkspaceResource>(
                id: WorkspaceID(rawValue: workspace.id.rawValue),
                reconciliation: .current
            )
        )

        await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.defaultEventID = eventID
            $0.workspaceProposalClient = .noop
        } operation: {
            let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            authoringGrant.withLock {
                $0 = AuthoringGrant(
                    principal: AuthoringPrincipal(actorID: actorID),
                    role: .owner,
                    workspaceID: workspace.id
                )
            }
            var initialState = EventWorkspace.State(
                workspace: workspace,
                eventID: eventID,
                workspaceState: SharedReader(workspaceState)
            )
            initialState.changes.proposalDraft = WorkspaceProposalDraft.State(
                targetBranch: "main",
                canPropose: true,
                canPublish: true,
                groups: [],
                fieldComparisons: .empty,
                recordComparisons: .empty
            )
            initialState.changes.proposalDraft?.form.value = WorkspaceProposalDraft.FormValue(
                title: "Preserve this title",
                description: "Preserve this description"
            )
            let store = Store(initialState: initialState) {
                EventWorkspace()
            }

            workspaceState.withLock { $0.reconciliation = .reconciling }
            await store.send(.proposalsRowTapped)?.value
            expectNoDifference(
                store.changes.proposalDraft?.form.value,
                WorkspaceProposalDraft.FormValue(
                    title: "Preserve this title",
                    description: "Preserve this description"
                )
            )

            workspaceState.withLock { $0.reconciliation = .current }
            await store.send(.proposalsRowTapped)?.value
            #expect(store.changes.proposalDraft != nil)

            workspaceState.withLock {
                $0.reconciliation = .conflicted(
                    WorkspaceReconciliationConflict(
                        baseline: baseline,
                        upstream: upstream,
                        conflictingPaths: [
                            WorkspaceConflictPath(rawValue: "events/2026/event.yml")
                        ]
                    )
                )
            }
            await store.send(.proposalsRowTapped)?.value
            #expect(store.changes.proposalDraft == nil)
        }
    }

    @Test
    func `OME prepared database survives nested live Store tasks and child mounting`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let recorder = WorkspaceStoryDependencyPropagationRecorder(database: database)

        await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
        } operation: {
            @Dependency(\.defaultDatabase) var preparedDatabase
            recorder.record(.preparedScope, database: preparedDatabase)

            let store = Store(
                initialState: WorkspaceStoryDependencyPropagationProbe.State()
            ) {
                WorkspaceStoryDependencyPropagationProbe(recorder: recorder)
            }

            await store.send(.open)?.value

            expectNoDifference(
                recorder.snapshot,
                WorkspaceStoryDependencyPropagationBoundary.allCases.map {
                    WorkspaceStoryDependencyPropagationObservation(
                        boundary: $0,
                        matchesPreparedDatabase: true
                    )
                }
            )
        }
    }

    @Test
    func `live event installation resolves the database prepared in the same dependency update`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let eventID = try await insertUnrelatedWorkspaceStoryEvent(into: database)

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
        } operation: {
            @Dependency(\.omeEventInstallation) var eventInstallation

            let installedEventID = try await eventInstallation.ensureInstalled(
                OMERecord.Event.reference(id: eventID).uri
            )
            expectNoDifference(installedEventID, eventID)
        }
    }

    @Test
    func `foregrounding reconciles the active workspace and skips its attendee refresh`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:foregroundauthor")
        )
        let actorID = try #require(DID(organizerID.description))
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/foregroundauthor/ome-workspace",
            branch: "main"
        )
        let baseline = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "mounted-revision")
        )
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let source = OpenMusicEventSourceRepository(
            events: [
                workspaceStorySourceEvent(
                    id: selectedEventID,
                    directoryName: "2026",
                    name: "Foreground Festival",
                    timeZone: timeZone
                )
            ]
        )
        let insertion = try OMERecord.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: workspace.sourceProvenance
            )
        )
        let referenceDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: referenceDatabase.path) }
        try await insertion.migrateAndInsert(into: referenceDatabase.database)
        let repositoryURL = FileManager.default.temporaryDirectory.appending(
            path: "OME-ForegroundReconciliation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        _ = try OpenMusicEventSourceRepositoryFileTree().write(source, to: repositoryURL)
        let resource = SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: repositoryURL,
            mainDatabase: database,
            referenceDatabase: referenceDatabase
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: baseline.branch.rawValue,
            revision: baseline.revision.rawValue,
            in: database
        )
        let unrelatedEventID = try await insertUnrelatedWorkspaceStoryEvent(into: database)
        try await database.write { db in
            for eventID in [selectedEventID, unrelatedEventID] {
                try InstalledEventRecord.insert {
                    InstalledEventRecord(id: eventID)
                }
                .execute(db)
            }
            try WorkspaceAuthoringActivationRecord.insert {
                WorkspaceAuthoringActivationRecord(
                    id: workspace.id,
                    principal: AuthoringPrincipal(actorID: actorID),
                    role: .owner,
                    activatedAt: Date(timeIntervalSince1970: 1_786_000_000)
                )
            }
            .execute(db)
        }

        let reconciledBaselines = Mutex<[WorkspaceBranchReference]>([])
        let attendeeRefreshes = Mutex<[OMERecord.Event.ID]>([])
        let session = workspaceStoryOAuthSession(actorID: actorID)
        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.defaultEventID = selectedEventID
            $0.getOptionalDefaultSession = { session }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in }
            $0.tangledRepositoryMembership = TangledRepositoryMembershipClient { _, _ in .owner }
            $0[SourceWorkspacePreparationClient.self] = SourceWorkspacePreparationClient { _ in
                WorkspaceSession(source: resource, baseline: baseline)
            }
            $0.workspaceProposalClient = .noop
            $0.uuid = .incrementing
            $0[WorkspaceReferenceUpdateClient.self] = WorkspaceReferenceUpdateClient(
                preparePublishedUpdate: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                },
                reconcile: { source, _, current in
                    reconciledBaselines.withLock { $0.append(current) }
                    return .current(WorkspaceSession(source: source, baseline: current))
                },
                discardChangesAndUpdate: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                },
                select: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
            )
            $0.omeEventInstallation = OMEEventInstallationClient(
                ensureInstalled: { _ in selectedEventID },
                synchronizeInstalledEvent: { eventID in
                    attendeeRefreshes.withLock { $0.append(eventID) }
                }
            )
        } operation: {
            var initialState = OpenMusicEventAppRoot.State(
                variant: .whiteLabel(
                    WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Foreground Festival"),
                        organizerID: organizerID
                    )
                ),
                selectedEventIDAtLaunch: selectedEventID
            )
            initialState.whiteLabelRoot = nil
            let store = Store(initialState: initialState) {
                OpenMusicEventAppRoot()
            }
            try await workspaceStoryWaitUntil {
                guard case .active = store.destination?.eventViewer?.authoring.phase,
                      case .ready = store.destination?.eventViewer?.authoring.content.availability,
                      reconciledBaselines.withLock({ $0.count }) == 1
                else { return false }
                return true
            }

            let resume = try store.state.appDelegateEvent(.resumed)
            await resume?.value

            expectNoDifference(reconciledBaselines.withLock { $0 }, [baseline, baseline])
            expectNoDifference(attendeeRefreshes.withLock { $0 }, [unrelatedEventID])
            #expect(store.destination?.eventViewer?.authoring.content.reconciliation == .current)

            let notification = try store.state.notificationEvent(
                NotificationEvent(
                    json: """
                    {
                      "aps": {
                        "content-available": 1
                      },
                      "kind": "source_available",
                      "source": "\(OME.Event.reference(id: selectedEventID).uri.description)",
                      "version": "foreground-story-notification"
                    }
                    """,
                    delivery: .contentAvailable
                )
            )
            await notification?.value

            expectNoDifference(
                reconciledBaselines.withLock { $0 },
                [baseline, baseline, baseline]
            )
            expectNoDifference(attendeeRefreshes.withLock { $0 }, [unrelatedEventID])
            #expect(store.destination?.eventViewer?.authoring.content.reconciliation == .current)
        }
    }

    @Test
    func `a Tangled repository member can propose and merge`() async throws {
        let ownerID = try #require(DID("did:plc:owner"))
        let memberID = try #require(DID("did:plc:member"))
        let repository = TangledRepositoryReference(
            host: "tangled.org",
            owner: ownerID.description,
            repository: "ome-workspace"
        )

        let role = try await withDependencies {
            $0.context = .test
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(actorID: ownerID)
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, _ in
                let path = request.url?.path ?? ""
                let body: Data
                if path.hasSuffix("/com.atproto.repo.listRecords") {
                    body = Data(
                        """
                        {
                          "records": [
                            {
                              "uri": "at://did:plc:owner/sh.tangled.repo/ome-workspace",
                              "cid": "bafyreifakerepo",
                              "value": {
                                "$type": "sh.tangled.repo",
                                "name": "ome-workspace",
                                "repoDid": "did:plc:workspace-source-repository",
                                "knot": "tangled.org",
                                "createdAt": "2026-08-05T00:00:00Z"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                } else if path.hasSuffix("/sh.tangled.repo.listCollaborators") {
                    body = Data(
                        """
                        {
                          "items": [
                            {
                              "subject": "did:plc:member",
                              "addedBy": "did:plc:owner",
                              "createdAt": "2026-08-05T00:01:00Z"
                            }
                          ]
                        }
                        """.utf8
                    )
                } else {
                    throw WorkspaceStoryUnexpectedNetworkRequest(url: request.url)
                }
                return (body, HTTPResponse(status: .ok))
            }
        } operation: {
            try await TangledRepositoryMembershipClient.liveValue.role(repository, memberID)
        }

        expectNoDifference(role, .collaborator([.propose, .merge]))
    }

    @Test(
        .disabled(
            "A later branch picker must supply an exact immutable reference before this story is restored."
        ),
        .tcaExhaustivity(.off)
    )
    func `a branch picker selects exact immutable references`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let repositoryOwnerID = try #require(
            DID("did:plc:cqqtuv75m7e5s4uj6nw4czyu")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-WorkspaceBranchStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let git = try WorkspaceStoryGitFixture(
            organizerID: organizerID,
            rootURL: storageRoot.appending(path: "git", directoryHint: .isDirectory)
        )
        let operations = WorkspaceStorySourceControlRecorder()
        let authenticationStorage = workspaceStoryOAuthStorage(actorID: repositoryOwnerID)
        let route = AppRoute.event(selectedEventID, .settings)
        let routeURL = try #require(URL(string: "ome://workspace-branch-story\(route.path)"))

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.defaultEventID = selectedEventID
            $0.uuid = .incrementing
            $0.sourceWorkspaceStorage = .fileBacked(
                rootURL: storageRoot.appending(path: "workspaces")
            )
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                actorID: repositoryOwnerID
            )
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                repositoryOwnerID: repositoryOwnerID,
                eventID: selectedEventID,
                archive: git.archive,
                revision: git.mainRevision
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations
            )
        } operation: {
            let store = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: authenticationStorage) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(store, route: route, url: routeURL)
            await store.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .enterAuthoringButtonTapped
            )?.value

            let preparedAuthoring = try #require(
                store.state.content.destination?.eventViewer?.authoring
            )
            let workspace = preparedAuthoring.context
            let preparedSession = try #require(preparedAuthoring.content.session)
            let resource = preparedSession.source
            let initialBranch = preparedSession.baseline
            expectNoDifference(initialBranch.branch.rawValue, workspace.defaultBranch)
            expectNoDifference(initialBranch.revision.rawValue, git.mainRevision)
            expectNoDifference(
                try workspaceStoryGitRevision(at: resource.repositoryURL),
                git.mainRevision
            )

            store.modify {
                guard var eventViewer = $0.content.destination?.eventViewer else { return }
                eventViewer.authoring.content.content.eventWorkspace?.requestedBranch =
                    WorkspaceStoryGitFixture.alternateBranch
                $0.content.destination = .eventViewer(eventViewer)
            }
            await store.send(
                workspaceStoryWorkspaceAction(.switchBranchButtonTapped)
            )?.value

            let selectedAlternate = WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: WorkspaceStoryGitFixture.alternateBranch),
                revision: WorkspaceRevision(rawValue: git.alternateRevision)
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.baseline,
                selectedAlternate
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026 - Preview Branch"
            )
            expectNoDifference(
                try workspaceStoryGitRevision(at: resource.repositoryURL),
                git.alternateRevision
            )
            expectNoDifference(
                String(
                    decoding: try workspaceStoryRunGit(
                        ["status", "--porcelain"],
                        at: resource.repositoryURL
                    ),
                    as: UTF8.self
                ),
                ""
            )
            let selectedState = try await database.read { db in
                (
                    installation: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db),
                    selection: try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)
                )
            }
            expectNoDifference(selectedState.installation?.revision, git.alternateRevision)
            expectNoDifference(
                selectedState.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: WorkspaceStoryGitFixture.alternateBranch,
                    revision: git.alternateRevision
                )
            )
            expectNoDifference(
                try resource.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
                },
                Optional(git.alternateRevision)
            )

            await store.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026"
            )

            await store.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .enterAuthoringButtonTapped
            )?.value
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.baseline,
                selectedAlternate
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026 - Preview Branch"
            )
            // Preparation mounts the restored session, then verifies it against the selected
            // branch. Both clean checkouts are initialized before the workspace becomes current.
            expectNoDifference(operations.count(of: "initialize"), 2)
            expectNoDifference(
                try workspaceStoryGitRevision(at: resource.repositoryURL),
                git.alternateRevision
            )

            await store.send(
                workspaceStoryWorkspaceAction(.switchToMainButtonTapped)
            )?.value
            let selectedMain = WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: workspace.defaultBranch),
                revision: WorkspaceRevision(rawValue: git.mainRevision)
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.baseline,
                selectedMain
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026"
            )
            expectNoDifference(
                try workspaceStoryGitRevision(at: resource.repositoryURL),
                git.mainRevision
            )

            let checkoutCountBeforeFailure = operations.count(of: "checkout")
            store.modify {
                guard var eventViewer = $0.content.destination?.eventViewer else { return }
                eventViewer.authoring.content.content.eventWorkspace?.requestedBranch =
                    WorkspaceStoryGitFixture.malformedBranch
                $0.content.destination = .eventViewer(eventViewer)
            }
            await withExpectedIssue {
                await store.send(
                    workspaceStoryWorkspaceAction(.switchBranchButtonTapped)
                )?.value
            }
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.baseline,
                selectedMain
            )
            expectNoDifference(
                try workspaceStoryGitRevision(at: resource.repositoryURL),
                git.mainRevision
            )
            expectNoDifference(
                store.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026"
            )
            expectNoDifference(
                operations.count(of: "checkout"),
                checkoutCountBeforeFailure + 2
            )
            let stateAfterFailedSwitch = try await database.read { db in
                (
                    installation: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db),
                    selection: try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)
                )
            }
            expectNoDifference(stateAfterFailedSwitch.installation?.revision, git.mainRevision)
            expectNoDifference(
                stateAfterFailedSwitch.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: workspace.defaultBranch,
                    revision: git.mainRevision
                )
            )
            expectNoDifference(
                try resource.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
                },
                Optional(git.mainRevision)
            )
            await store.dismount(timeout: .seconds(1))
        }
    }

    @Test(.tcaExhaustivity(.off))
    func `saved authoring access is available in settings while the source opens`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-SavedAuthoringAccessStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let git = try WorkspaceStoryGitFixture(
            organizerID: organizerID,
            rootURL: storageRoot.appending(path: "git", directoryHint: .isDirectory)
        )
        let operations = WorkspaceStorySourceControlRecorder()
        let preparation = WorkspaceStoryPreparationPause()
        let authenticationStorage = workspaceStoryOAuthStorage(actorID: organizerID)
        let route = AppRoute.event(selectedEventID, .settings)
        let routeURL = try #require(URL(string: "ome://saved-authoring-access\(route.path)"))

        try await withDependencies {
            $0.context = .test
            // Keep app launch, event installation, persisted activation, and restoration live.
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            let livePreparation = $0[SourceWorkspacePreparationClient.self]
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.defaultEventID = selectedEventID
            $0.uuid = .incrementing
            // Restoration must reopen the same durable source location after authorization succeeds.
            $0.sourceWorkspaceStorage = .fileBacked(
                rootURL: storageRoot.appending(path: "workspaces")
            )
            // The selected account remains the organizer who owns the restored grant.
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                actorID: organizerID
            )
            // Exercise the live OME admission and restoration clients against fixture transport.
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                repositoryOwnerID: organizerID,
                eventID: selectedEventID,
                archive: git.archive,
                revision: git.mainRevision
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations
            )
            // Hold only source preparation so Settings can be observed after grant restoration.
            $0[SourceWorkspacePreparationClient.self] = SourceWorkspacePreparationClient {
                workspace in
                try await preparation.prepare(workspace, live: livePreparation)
            }
        } operation: {
            let installedEventID = try await OMEEventInstallationClient.liveValue
                .ensureInstalled(OMERecord.Event.reference(id: selectedEventID).uri)
            let restorableState = OpenMusicEventAppRoot.State(
                selectedEventIDAtLaunch: installedEventID
            )
            let workspaceID = try #require(
                restorableState.destination?.eventViewer?.authoring.context.id
            )
            @Dependency(WorkspaceAuthoringActivationClient.self) var activations
            try await activations.activate(
                workspaceID,
                AuthoringPrincipal(actorID: organizerID),
                .owner
            )

            let store = Store(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: authenticationStorage) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }

            // The user opens Settings after relaunching with saved authoring access.
            let opening = store.send(.content(.openURL(routeURL)))
            await preparation.waitUntilStarted()

            // The restored grant drives Settings immediately; source preparation has its own phase.
            let authoring = try #require(store.content.destination?.eventViewer?.authoring)
            let grant = try #require(authoring.grant)
            expectNoDifference(authoring.phase, .active(grant))
            #expect(workspaceIsPreparing(authoring.content.availability))
            expectNoDifference(authoring.content.content.selectedFeature, .settings)
            #expect(authoring.content.content.eventSettings != nil)

            // Source preparation can finish without changing or replacing the restored grant.
            await preparation.continuePreparation()
            await opening?.value
            // Ready content is exposed before automatic reconciliation finishes. Await the
            // owning task so both immutable checkouts have completed before inspecting Git work.
            try await authoring.content.preparation()
            #expect(!authoring.content.preparation.isRunning)
            #expect(store.content.destination?.eventViewer?.authoring.content.session != nil)
            #expect(store.content.destination?.eventViewer?.authoring.content.reconciliation == .current)
            expectNoDifference(store.content.destination?.eventViewer?.authoring.grant, grant)
            expectNoDifference(operations.count(of: "initialize"), 2)
            expectNoDifference(operations.count(of: "clone"), 0)
            expectNoDifference(operations.count(of: "fetch"), 0)
        }
    }

    @Test(.tcaExhaustivity(.off))
    func `an organizer retries failed source preparation without losing authoring access`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-WorkspaceAccessStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let git = try WorkspaceStoryGitFixture(
            organizerID: organizerID,
            rootURL: storageRoot.appending(path: "git", directoryHint: .isDirectory)
        )
        let operations = WorkspaceStorySourceControlRecorder()
        let preparationGate = WorkspaceStoryPreparationGate()
        let authenticationStorage = workspaceStoryOAuthStorage(actorID: organizerID)
        let route = AppRoute.event(selectedEventID, .settings)
        let routeURL = try #require(URL(string: "ome://workspace-access-story\(route.path)"))

        try await withDependencies {
            $0.context = .test
            // Keep the full OME authoring stack live; only source preparation is controlled below.
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            let livePreparation = $0[SourceWorkspacePreparationClient.self]
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.defaultEventID = selectedEventID
            $0.uuid = .incrementing
            // Retry must reuse the same persisted checkout after the controlled first failure.
            $0.sourceWorkspaceStorage = .fileBacked(
                rootURL: storageRoot.appending(path: "workspaces")
            )
            // The selected OAuth account resolves to owner eligibility through the live client.
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                actorID: organizerID
            )
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                repositoryOwnerID: organizerID,
                eventID: selectedEventID,
                archive: git.archive,
                revision: git.mainRevision
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations
            )
            // Suspend and fail only the external preparation attempt, leaving authorization live.
            $0[SourceWorkspacePreparationClient.self] = SourceWorkspacePreparationClient {
                workspace in
                try await preparationGate.prepare(
                    workspace,
                    live: livePreparation
                )
            }
        } operation: {
            let opened = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: authenticationStorage) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(opened, route: route, url: routeURL)
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.phase,
                .inactive(
                    .eligible(
                        AuthoringEligibility(
                            principal: AuthoringPrincipal(actorID: organizerID),
                            role: .owner
                        )
                    )
                )
            )

            // The Settings action activates authoring. Workspace availability follows the grant,
            // while source preparation remains independently suspended at its external boundary.
            try await expectReportedIssue(containing: "WorkspaceStoryFirstPreparationFailure") {
                let entry = opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                    .enterAuthoringButtonTapped
                )
                await preparationGate.waitUntilFirstAttemptStarts()

                let preparingAuthoring = try #require(
                    opened.state.content.destination?.eventViewer?.authoring
                )
                let preparingGrant = try #require(preparingAuthoring.grant)
                expectNoDifference(
                    preparingGrant.principal,
                    AuthoringPrincipal(actorID: organizerID)
                )
                expectNoDifference(preparingGrant.role, .owner)
                #expect(workspaceIsPreparing(preparingAuthoring.content.availability))
                expectNoDifference(
                    preparingAuthoring.content.content.authoringAccess,
                    .authoring(.owner)
                )
                #expect(
                    preparingAuthoring.content.content.installedFeatures.contains(.workspace)
                )
                let preparingWorkspace = try #require(
                    preparingAuthoring.content.content.eventWorkspace
                )
                expectNoDifference(preparingWorkspace.workspace.id, preparingGrant.workspaceID)
                #expect(workspaceIsPreparing(preparingWorkspace.workspaceState.availability))
                expectNoDifference(
                    preparingWorkspace.changes.summary.availability,
                    .workspaceNeedsPreparation
                )

                // Failure is presented by the same mounted Workspace; it does not revoke authoring.
                await preparationGate.failFirstAttempt()
                await entry?.value
            }
            let failedAuthoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            guard case .preparationFailed = failedAuthoring.content.availability else {
                Issue.record("The controlled first preparation must fail in Workspace.")
                return
            }
            #expect(failedAuthoring.grant != nil)
            #expect(failedAuthoring.content.session?.source == nil)
            #expect(failedAuthoring.content.content.eventWorkspace != nil)
            #expect(failedAuthoring.content.content.installedFeatures.contains(.workspace))
            #expect(failedAuthoring.content.content.authoringAccess.canEditContent)
            guard case let .preparationFailed(failure) = failedAuthoring.content.availability else {
                Issue.record("The controlled first preparation must retain its failure details.")
                return
            }
            expectNoDifference(
                failedAuthoring.content.content.eventWorkspace?.workspaceState.preparationFailure,
                failure
            )

            // Workspace loads its proposal count before navigation, even while source preparation
            // is unavailable, so its badge can include every known source.
            try await workspaceStoryWaitUntil {
                opened.state.content.destination?.eventViewer?.authoring.content.content
                    .eventWorkspace?.reviews.status == .loaded([])
            }
            let failedWorkspace = try #require(
                opened.state.content.destination?.eventViewer?.authoring.content.content
                    .eventWorkspace
            )
            expectNoDifference(failedWorkspace.openProposalCount, 0)

            // Opening Proposals presents that already-loaded list rather than creating a second one.
            await opened.send(
                workspaceStoryWorkspaceAction(.proposalsRowTapped)
            )?.value
            let failedWorkspaceWithProposals = try #require(
                opened.state.content.destination?.eventViewer?.authoring.content.content
                    .eventWorkspace
            )
            expectNoDifference(
                failedWorkspaceWithProposals.navigationDestination,
                .proposals
            )
            expectNoDifference(failedWorkspaceWithProposals.reviews.status, .loaded([]))

            // Retry starts at EventWorkspace, crosses the app event bridge, and reaches the shared
            // Workspace state machine before executing the real source preparation implementation.
            await opened.send(
                workspaceStoryWorkspaceAction(.sourcePreparationRetryButtonTapped)
            )?.value
            let readyAuthoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            guard let readySession = readyAuthoring.content.session else {
                Issue.record("Workspace retry must establish the selected branch.")
                return
            }
            let selectedBranch = readySession.baseline
            #expect(readyAuthoring.content.session?.source != nil)
            #expect(readyAuthoring.content.content.eventWorkspace != nil)
            #expect(readyAuthoring.content.content.installedFeatures.contains(.workspace))
            expectNoDifference(
                readyAuthoring.content.content.eventWorkspace?.baseline,
                selectedBranch
            )
            expectNoDifference(
                readyAuthoring.content.content.eventWorkspace?.reviews.status,
                .loaded([])
            )
            // Retry mounts the persisted checkout, then reconciliation checks out the selected
            // branch again to verify the baseline before publication is allowed.
            expectNoDifference(operations.count(of: "initialize"), 2)
            expectNoDifference(operations.count(of: "clone"), 0)
            expectNoDifference(operations.count(of: "fetch"), 0)

            // A clean exit still restores published attendee content and resets only the generic
            // Workspace layer. The mounted EventViewer remains alive in attendee mode.
            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            let exited = try #require(opened.state.content.destination?.eventViewer?.authoring)
            #expect(exited.grant == nil)
            expectNoDifference(exited.content.content.authoringAccess, .attendee)
            #expect(!exited.content.content.installedFeatures.contains(.workspace))
            #expect(exited.content.content.eventWorkspace != nil)
            #expect(workspaceIsInactive(exited.content.availability))
            #expect(exited.content.session?.source == nil)
            let exitedWorkspaceID = exited.context.id
            let retainedSelection = try await database.read { db in
                try SourceWorkspaceSelectionRecord.find(exitedWorkspaceID).fetchOne(db)
            }
            expectNoDifference(retainedSelection?.branch, selectedBranch.branch.rawValue)
            expectNoDifference(retainedSelection?.revision, selectedBranch.revision.rawValue)
            await opened.dismount(timeout: .seconds(1))
        }
    }

    @Test(.tcaExhaustivity(.off))
    func `confirmed exit waits for public attendee restoration before clearing authoring`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:authoringexitstory")
        )
        let actorID = try #require(DID(organizerID.description))
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let authoringOnlyEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2025"
        )
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/wickedwoods.ca/ome-workspace",
            branch: "main"
        )
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let source = OpenMusicEventSourceRepository(
            events: [
                workspaceStorySourceEvent(
                    id: authoringOnlyEventID,
                    directoryName: "2025",
                    name: "Wicked Woods 2025",
                    timeZone: timeZone
                ),
                workspaceStorySourceEvent(
                    id: selectedEventID,
                    directoryName: "2026",
                    name: "Wicked Woods 2026",
                    timeZone: timeZone
                ),
            ]
        )
        let insertion = try OMERecord.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: workspace.sourceProvenance
            )
        )
        let referenceDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: referenceDatabase.path) }
        try await insertion.migrateAndInsert(into: referenceDatabase.database)
        let resourceDirectory = FileManager.default.temporaryDirectory.appending(
            path: "OME-AuthoringExitResource-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: resourceDirectory) }
        try FileManager.default.createDirectory(
            at: resourceDirectory,
            withIntermediateDirectories: true
        )
        let resource = SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: resourceDirectory,
            mainDatabase: database,
            referenceDatabase: referenceDatabase
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: workspace.defaultBranch,
            revision: "authoring-revision",
            in: database
        )
        let principal = AuthoringPrincipal(actorID: actorID)
        try await database.write { db in
            try InstalledEventRecord.insert {
                InstalledEventRecord(
                    id: selectedEventID,
                    sourceProvenance: workspace.sourceProvenance
                )
            }
            .execute(db)
            try OMERecord.Event.find(selectedEventID).update {
                $0.name = "Unpublished Wicked Woods"
            }
            .execute(db)
            try WorkspaceAuthoringActivationRecord.insert {
                WorkspaceAuthoringActivationRecord(
                    id: workspace.id,
                    principal: principal,
                    role: .owner,
                    activatedAt: Date(timeIntervalSince1970: 1_786_000_000)
                )
            }
            .execute(db)
        }
        let storedActivation = try await database.read { db in
            try WorkspaceAuthoringActivationRecord.find(workspace.id).fetchOne(db)
        }
        #expect(storedActivation != nil)

        let authoringGrant = withDependencies {
            $0.context = .test
            $0.defaultEventID = selectedEventID
        } operation: {
            Shared<AuthoringGrant?>(.defaultAuthoringGrant)
        }
        defer { authoringGrant.withLock { $0 = nil } }

        let checkoutPause = WorkspaceStoryCheckoutPause()
        let authenticationStorage = workspaceStoryOAuthStorage(actorID: actorID)
        let route = AppRoute.event(selectedEventID, .settings)
        let routeURL = try #require(URL(string: "ome://authoring-exit\(route.path)"))
        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.defaultEventID = selectedEventID
            $0.uuid = .incrementing
            // Public restoration resolves the event through the real typed XRPC client before
            // checking out its published source. Mock only that client's raw transport so this
            // story still exercises catalog decoding, checkout, and the database transaction.
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                repositoryOwnerID: actorID,
                eventID: selectedEventID,
                archive: Data()
            )
            $0.tangledRepositoryMembership = TangledRepositoryMembershipClient {
                _, requestedActorID in
                #expect(requestedActorID == actorID)
                return .owner
            }
            $0[SourceWorkspacePreparationClient.self] = SourceWorkspacePreparationClient {
                requestedWorkspace in
                #expect(requestedWorkspace == workspace)
                return WorkspaceSession(
                    source: resource,
                    baseline: WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: workspace.defaultBranch),
                        revision: WorkspaceRevision(rawValue: "authoring-revision")
                    )
                )
            }
            $0[WorkspaceReferenceUpdateClient.self] = WorkspaceReferenceUpdateClient(
                preparePublishedUpdate: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                },
                reconcile: { source, _, current in
                    .current(WorkspaceSession(source: source, baseline: current))
                },
                discardChangesAndUpdate: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                },
                select: { _, _, _ in
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
            )
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                await checkoutPause.pause()
                try FileManager.default.createDirectory(
                    at: request.outputURL,
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    source,
                    to: request.outputURL
                )
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
        } operation: {
            let store = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: authenticationStorage) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(store, route: route, url: routeURL)
            try await workspaceStoryWaitUntil {
                guard case .active = store.content.destination?.eventViewer?.authoring.phase,
                      case .ready = store.content.destination?.eventViewer?
                        .authoring.content.availability
                else { return false }
                return true
            }
            #expect(
                store.content.destination?.eventViewer?.authoring.content.content.eventSettings != nil
            )

            await store.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            #expect(
                store.content.destination?.eventViewer?.authoring.content.content.eventSettings?
                    .destination?.exitAuthoringConfirmation != nil
            )

            let confirmedExit = store.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .destination(.exitAuthoringConfirmation(.exitAndDeleteButtonTapped))
            )
            await checkoutPause.waitUntilStarted()

            // The destructive prompt has been accepted, but the download is still paused.
            // Authoring and the unpublished content remain intact until public-route validation and
            // the one database transaction have both succeeded.
            #expect(authoringGrant.wrappedValue != nil)
            let pausedEventName = try await database.read { db in
                try OMERecord.Event.find(selectedEventID).fetchOne(db)?.name
            }
            expectNoDifference(
                pausedEventName,
                "Unpublished Wicked Woods"
            )

            await checkoutPause.continueCheckout()
            await confirmedExit?.value

            try await workspaceStoryWaitUntil {
                guard let authoring = store.content.destination?.eventViewer?.authoring else {
                    return false
                }
                return authoring.grant == nil
                    && workspaceIsInactive(authoring.content.availability)
                    && authoring.content.content.event?.name == "Wicked Woods 2026"
            }
            #expect(authoringGrant.wrappedValue == nil)
            #expect(store.content.destination?.eventViewer?.authoring.grant == nil)
            try await database.read { db in
                expectNoDifference(
                    try OMERecord.Event.find(selectedEventID).fetchOne(db)?.name,
                    "Wicked Woods 2026"
                )
                #expect(try OMERecord.Event.find(authoringOnlyEventID).fetchOne(db) == nil)
                expectNoDifference(
                    try InstalledEventRecord.fetchAll(db).map(\.id),
                    [selectedEventID]
                )
                #expect(
                    try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db) == nil
                )
                #expect(
                    try WorkspaceAuthoringActivationRecord.find(workspace.id).fetchOne(db) == nil
                )
                expectNoDifference(
                    try SourceWorkspaceSelectionRecord.find(workspace.id).fetchOne(db),
                    SourceWorkspaceSelectionRecord(
                        id: workspace.id,
                        branch: workspace.defaultBranch,
                        revision: "authoring-revision"
                    )
                )
            }
        }
    }

    @Test(
        .tcaExhaustivity(.off),
        arguments: [EventTarget.settings, .workspace]
    )
    func `signed-out app never offers or enters authoring from settings or an editor route`(
        _ target: EventTarget
    ) async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-SignedOutAuthoringStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let git = try WorkspaceStoryGitFixture(
            organizerID: organizerID,
            rootURL: storageRoot.appending(path: "git", directoryHint: .isDirectory)
        )
        let operations = WorkspaceStorySourceControlRecorder()
        let authenticationStorage = workspaceStorySignedOutOAuthStorage()
        let route = AppRoute.event(selectedEventID, target)
        let routeURL = try #require(URL(string: "ome://signed-out-authoring\(route.path)"))

        try await withDependencies {
            $0.context = .test
            // Keep event installation and the app lifecycle real while authentication is absent.
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.uuid = .incrementing
            $0.sourceWorkspaceStorage = .fileBacked(
                rootURL: storageRoot.appending(path: "workspaces")
            )
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                actorID: organizerID
            )
            // A signed-out app must stop before membership policy or source work is consulted.
            $0.tangledRepositoryMembership = TangledRepositoryMembershipClient {
                _, _ in
                operations.record("membership")
                return nil
            }
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                repositoryOwnerID: organizerID,
                eventID: selectedEventID,
                archive: git.archive,
                revision: git.mainRevision
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            // Record every Git operation so the denial story proves that none begins.
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations
            )
        } operation: {
            let opened = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: authenticationStorage) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(opened, route: route, url: routeURL)

            // Event Settings receives the application's one authoring phase. With no selected
            // account it is unavailable, so the view has no Enter Authoring branch to render.
            let authoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.phase,
                .inactive(.unavailable)
            )
            #expect(authoring.grant == nil)
            #expect(workspaceIsInactive(authoring.content.availability))
            if target == .workspace {
                expectNoDifference(
                    authoring.content.content.pendingAuthoringEntry,
                    .target(.workspace)
                )
            } else {
                #expect(authoring.content.content.pendingAuthoringEntry == nil)
            }
            #expect(operations.snapshot.isEmpty)

            // A stale presentation action is still rejected at the full application boundary.
            try await expectReportedIssue(containing: "admissionUnavailable") {
                await opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                    .enterAuthoringButtonTapped
                )?.value
            }
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.phase,
                .inactive(.unavailable)
            )
            #expect(opened.state.content.destination?.eventViewer?.authoring.grant == nil)
            #expect(workspaceIsInactive(
                opened.state.content.destination?.eventViewer?.authoring.content.availability
            ))
            #expect(operations.snapshot.isEmpty)
            await opened.dismount(timeout: .seconds(1))
        }
    }

    @Test
    func `an authenticated attendee cannot enter authoring and never touches Git`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let operations = WorkspaceStorySourceControlRecorder()

        try await withWorkspaceStoryOAuthSession(actorID: organizerID) {
            try await withDependencies {
                $0.context = .test
                // Install the real event and launch the full app with an authenticated session.
                OME.prepareDependencies(&$0, database: database)
                $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
                $0.uuid = .incrementing
                // The selected account is valid, but repository membership denies authoring eligibility.
                $0.tangledRepositoryMembership = TangledRepositoryMembershipClient {
                    _, _ in nil
                }
                $0[XRPC.Client.self] = .liveValue
                $0.httpClient = .liveValue
                $0.requestInterceptors = []
                $0.responseInterceptors = []
                $0.errorInterceptors = []
                $0.dataForURL = workspaceStoryNetwork(
                    repositoryOwnerID: organizerID,
                    eventID: selectedEventID,
                    archive: Data()
                )
                $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                    try FileManager.default.createDirectory(
                        at: request.outputURL,
                        withIntermediateDirectories: true
                    )
                    try writeWorkspaceStorySource(
                        organizerID: organizerID,
                        to: request.outputURL
                    )
                    return TangledSourceCheckout(repositoryURL: request.outputURL)
                }

                var sourceControl = SourceControlClient.unimplemented
                // Any source-control call means the attendee crossed the authorization boundary.
                sourceControl.clone = { _ in
                    operations.record("clone")
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
                sourceControl.open = { _ in
                    operations.record("open")
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
                sourceControl.fetch = { _ in
                    operations.record("fetch")
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
                sourceControl.checkout = { _ in
                    operations.record("checkout")
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
                sourceControl.resolveRevision = { _ in
                    operations.record("resolve")
                    throw WorkspaceStoryUnexpectedSourceControlOperation()
                }
                $0.sourceControl = sourceControl
            } operation: {
                let installedEventID = try await OMEEventInstallationClient.liveValue
                    .ensureInstalled(OMERecord.Event.reference(id: selectedEventID).uri)
                expectNoDifference(installedEventID, selectedEventID)
                #expect(operations.snapshot.isEmpty)

                let store = Store(
                    initialState: OpenMusicEventApplication.State(
                        storage: OpenMusicEventOAuth.storage
                    ) {
                        OpenMusicEventAppRoot.State(
                            selectedEventIDAtLaunch: selectedEventID
                        )
                    }
                ) {
                    OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                        OpenMusicEventAppRoot()
                    }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
                }
                try await workspaceStoryWaitUntil {
                    store.content.destination?.eventViewer?.authoring.phase == .inactive(.unavailable)
                }

                expectNoDifference(
                    store.content.destination?.eventViewer?.authoring.phase,
                    .inactive(.unavailable)
                )
                #expect(store.content.destination?.eventViewer?.authoring.grant == nil)
                #expect(workspaceIsInactive(
                    store.content.destination?.eventViewer?.authoring.content.availability
                ))
                #expect(operations.snapshot.isEmpty)
            }
        }
    }
}

private func workspaceIsInactive<Source>(
    _ availability: WorkspaceAvailability<Source>?
) -> Bool {
    guard case .inactive? = availability else { return false }
    return true
}

private func workspaceIsPreparing<Source>(
    _ availability: WorkspaceAvailability<Source>?
) -> Bool {
    guard case .preparing? = availability else { return false }
    return true
}

private struct WorkspaceStoryGitFixture {
    static let alternateBranch = "festival-preview"
    static let malformedBranch = "malformed-source"

    let archive: Data
    let bareRepositoryURL: URL
    let mainRevision: String
    let alternateRevision: String

    init(organizerID: OMERecord.Organizer.ID, rootURL: URL) throws {
        let sourceURL = rootURL.appending(path: "source", directoryHint: .isDirectory)
        bareRepositoryURL = rootURL.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try writeWorkspaceStorySource(organizerID: organizerID, to: sourceURL)

        try workspaceStoryRunGit(["init", "--initial-branch=main"], at: sourceURL)
        try workspaceStoryRunGit(["config", "user.name", "Workspace Story"], at: sourceURL)
        try workspaceStoryRunGit(
            ["config", "user.email", "workspace-story@openmusicevent.app"],
            at: sourceURL
        )
        try workspaceStoryRunGit(["add", "."], at: sourceURL)
        try workspaceStoryRunGit(["commit", "-m", "Initial organization source"], at: sourceURL)
        mainRevision = try workspaceStoryGitRevision(at: sourceURL)

        try workspaceStoryRunGit(
            ["checkout", "-b", Self.alternateBranch],
            at: sourceURL
        )
        try writeWorkspaceStorySource(
            organizerID: organizerID,
            selectedEventName: "Wicked Woods 2026 - Preview Branch",
            to: sourceURL
        )
        try workspaceStoryRunGit(["add", "."], at: sourceURL)
        try workspaceStoryRunGit(
            ["commit", "-m", "Preview the next festival revision"],
            at: sourceURL
        )
        alternateRevision = try workspaceStoryGitRevision(at: sourceURL)
        try workspaceStoryRunGit(["checkout", "main"], at: sourceURL)

        try workspaceStoryRunGit(
            ["checkout", "-b", Self.malformedBranch],
            at: sourceURL
        )
        try Data("name: [".utf8).write(
            to: sourceURL.appending(path: "events/2026/event.yml"),
            options: .atomic
        )
        try workspaceStoryRunGit(["add", "."], at: sourceURL)
        try workspaceStoryRunGit(
            ["commit", "-m", "Add a malformed source fixture"],
            at: sourceURL
        )
        try workspaceStoryRunGit(["checkout", "main"], at: sourceURL)

        try workspaceStoryRunGit(
            ["clone", "--bare", sourceURL.path, bareRepositoryURL.path],
            at: rootURL
        )
        archive = try workspaceStoryRunGit(
            ["archive", "--format=tar.gz", "main"],
            at: sourceURL
        )
    }
}

private func workspaceStoryGitRevision(at repositoryURL: URL) throws -> String {
    String(
        decoding: try workspaceStoryRunGit(["rev-parse", "HEAD"], at: repositoryURL),
        as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct WorkspaceStoryFixtureCommandFailure: Error, CustomStringConvertible {
    let arguments: [String]
    let status: Int32
    let stderr: String

    var description: String {
        "git \(arguments.joined(separator: " ")) failed with \(status): \(stderr)"
    }
}

@discardableResult
private func workspaceStoryRunGit(_ arguments: [String], at directory: URL) throws -> Data {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw WorkspaceStoryFixtureCommandFailure(
            arguments: arguments,
            status: process.terminationStatus,
            stderr: String(decoding: errorData, as: UTF8.self)
        )
    }
    return outputData
}

private func workspaceStoryOAuthStorage(actorID: DID) -> OAuthSessionStorage {
    let session = workspaceStoryOAuthSession(actorID: actorID)
    let sessionStore = Shared(
        value: OAuth.SessionStore(
            selectedAccountID: session.accountID,
            sessions: [actorID: session]
        )
    )
    return OAuthSessionStorage(
        sessionStore: sessionStore,
        authFailureMessage: Shared(value: nil),
        selectedSessionID: Shared(value: session.accountID)
    )
}

private func workspaceStorySignedOutOAuthStorage() -> OAuthSessionStorage {
    OAuthSessionStorage(
        sessionStore: Shared(value: OAuth.SessionStore()),
        authFailureMessage: Shared(value: nil),
        selectedSessionID: Shared(value: nil)
    )
}

private func workspaceStoryOAuthSession(actorID: DID) -> OAuth.Session {
    OAuth.Session(
        accountID: Atmosphere.Account.ID(actorID),
        pdsHost: "owner.pds.example",
        tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
            URL(string: "https://owner.pds.example/oauth/token")!
        ),
        scope: OAuth.Scope(
            rawValue: Set([OAuth.Permission.atproto])
                .union(OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions)
                .map(\.rawValue)
                .sorted()
                .joined(separator: " ")
        ),
        accessToken: OAuth.AccessToken(rawValue: "workspace-story-access-token"),
        refreshToken: OAuth.RefreshToken(rawValue: "workspace-story-refresh-token"),
        dpopKey: OAuth.DPOP.Key()
    )
}

private let workspaceStoryOAuthCallbackURL = OAuth.App.CallbackURI(
    URL(
        string: "app.openmusicevent:/oauth/callback?code=workspace-story-code&state=workspace-story-nonce&iss=https://owner.pds.example"
    )!
)

private func workspaceStoryOAuthClient(actorID: DID) -> OAuth.Client {
    var client = OAuth.Client()
    client.beginAuthorizationWithPermissions = { _, _ in
        (
            URL(string: "https://owner.pds.example/oauth/authorize")!,
            try workspaceStoryPendingOAuthSession(actorID: actorID)
        )
    }
    client.exchangeCode = { _, _, _, _ in
        workspaceStoryOAuthSession(actorID: actorID)
    }
    return client
}

private func workspaceStoryPendingOAuthSession(
    actorID: DID
) throws -> OAuth.Session.Pending {
    let metadata = try JSONDecoder().decode(
        OAuth.AuthorizationServer.Metadata.self,
        from: Data(
            """
            {
              "issuer": "https://owner.pds.example",
              "authorization_endpoint": "https://owner.pds.example/oauth/authorize",
              "token_endpoint": "https://owner.pds.example/oauth/token",
              "response_types_supported": ["code"],
              "grant_types_supported": ["authorization_code", "refresh_token"],
              "code_challenge_methods_supported": ["S256"],
              "token_endpoint_auth_methods_supported": ["none"],
              "token_endpoint_auth_signing_alg_values_supported": ["ES256"],
              "scopes_supported": ["atproto"],
              "authorization_response_iss_parameter_supported": true,
              "require_pushed_authorization_requests": true,
              "pushed_authorization_request_endpoint": "https://owner.pds.example/oauth/par",
              "dpop_signing_alg_values_supported": ["ES256"],
              "require_request_uri_registration": true,
              "client_id_metadata_document_supported": true
            }
            """.utf8
        )
    )
    let pkceChallenge = try withDependencies {
        $0.context = .live
    } operation: {
        try OAuth.PKCE.Challenge()
    }
    return OAuth.Session.Pending(
        pkceChallenge: pkceChallenge,
        state: OAuth.Nonce(rawValue: "workspace-story-nonce"),
        redirectURI: OpenMusicEventOAuth.appConfiguration.redirectURI,
        authServer: metadata,
        accountID: Atmosphere.Account.ID(actorID),
        pdsHost: "owner.pds.example",
        dpopKey: OAuth.DPOP.Key()
    )
}

private func workspaceStoryNetwork(
    repositoryOwnerID: DID,
    eventID: OME.Event.ID,
    archive: Data,
    revision: String = "unused-revision",
    failsProposalPublication: Bool = false,
    recorder: WorkspaceStorySourceControlRecorder? = nil
) -> RunHTTPRequest {
    let archiveChecksum = Data(SHA256.hash(data: archive)).base64EncodedString()
    return { request, _ in
        let path = request.url?.path ?? ""
        func ok(_ data: Data) -> (Data, HTTPResponse) {
            (data, HTTPResponse(status: .ok))
        }

        if path.contains("/archive/"), path.hasSuffix(".tar.gz") {
            return ok(archive)
        }
        if path.hasSuffix("/sh.tangled.git.listRefs") {
            return ok(Data(
                """
                {
                  "refs": [
                    {"ref": "refs/heads/main", "sha": "\(revision)"}
                  ],
                  "defaultBranch": {
                    "ref": "refs/heads/main",
                    "head": "\(revision)"
                  }
                }
                """.utf8
            ))
        }
        if path.hasSuffix("/sh.tangled.repo.mergeCheck") {
            return ok(Data(#"{"is_conflicted":false}"#.utf8))
        }
        if path.hasSuffix("/app.openmusicevent.calendar.getEvent") {
            return ok(Data(
                """
                {
                  "uri": "\(OME.Event.reference(id: eventID).uri)",
                  "name": "Wicked Woods 2026",
                  "locations": [],
                  "links": [],
                  "media": [],
                  "organizer": {
                    "id": "\(eventID.organizerID)"
                  },
                  "attendance": {
                    "going": 0,
                    "interested": 0,
                    "notGoing": 0
                  },
                  "source": {
                    "collection": "app.openmusicevent.event",
                    "appViewHost": "openmusicevent.app",
                    "sourceRecord": {
                      "$type": "app.openmusicevent.source",
                      "kind": "tangled",
                      "reference": "https://tangled.org/wickedwoods.ca/ome-workspace",
                      "ref": "main"
                    },
                    "resolvedArtifact": {
                      "url": "https://tangled.org/wickedwoods.ca/ome-workspace/archive/\(revision).tar.gz",
                      "revision": "\(revision)",
                      "checksumSHA256": "\(archiveChecksum)",
                      "byteCount": \(archive.count)
                    }
                  }
                }
                """.utf8
            ))
        }
        if path.hasSuffix("/app.openmusicevent.workspace.getProposals") {
            return ok(Data(#"{"proposals":[]}"#.utf8))
        }
        if path.hasSuffix("/app.openmusicevent.workspace.getProposal") {
            return ok(Data(
                """
                {
                  "uri": "at://\(repositoryOwnerID)/sh.tangled.repo.pull/workspace-story",
                  "canonicalSource": "at://\(eventID.organizerID)/sh.tangled.repo/ome-workspace",
                  "title": "Expand the 2026 event experience",
                  "authorDID": "\(repositoryOwnerID)",
                  "status": "sh.tangled.repo.pull.status.open",
                  "targetBranch": "main",
                  "recordAvailability": "app.openmusicevent.workspace.defs#awaitingRecord",
                  "renderStatus": "app.openmusicevent.workspace.defs#awaitingInput"
                }
                """.utf8
            ))
        }
        if path.hasSuffix("/com.atproto.repo.listRecords") {
            return ok(Data(
                """
                {
                  "records": [
                    {
                      "uri": "at://\(repositoryOwnerID)/sh.tangled.repo/ome-workspace",
                      "cid": "bafyreifakerepo",
                      "value": {
                        "$type": "sh.tangled.repo",
                        "name": "ome-workspace",
                        "repoDid": "did:plc:workspace-source-repository",
                        "knot": "tangled.org",
                        "createdAt": "2026-05-26T17:30:42Z"
                      }
                    }
                  ]
                }
                """.utf8
            ))
        }
        if path.hasSuffix("/com.atproto.repo.uploadBlob") {
            return ok(Data(
                """
                {
                  "blob": {
                    "$type": "blob",
                    "ref": {"$link": "bafkreipatch"},
                    "mimeType": "application/gzip",
                    "size": 123
                  }
                }
                """.utf8
            ))
        }
        if path.hasSuffix("/com.atproto.repo.putRecord") {
            recorder?.record("putRecord")
            if failsProposalPublication {
                throw WorkspaceStoryPatchPublicationFailure()
            }
            return ok(Data(
                """
                {
                  "uri": "at://\(repositoryOwnerID)/sh.tangled.repo.pull/workspace-story",
                  "cid": "bafyreipull"
                }
                """.utf8
            ))
        }

        throw WorkspaceStoryUnexpectedNetworkRequest(url: request.url)
    }
}

private struct WorkspaceStoryUnexpectedNetworkRequest: Error {
    let url: URL?
}

private func workspaceStorySourceControl(
    live: SourceControlClient,
    remoteURL: URL,
    recorder: WorkspaceStorySourceControlRecorder
) -> SourceControlClient {
    var sourceControl = live
    sourceControl.initialize = { url in
        recorder.record("initialize")
        return try await live.initialize(url)
    }
    sourceControl.clone = { request in
        recorder.record("clone")
        var request = request
        request.remote.url = RemoteURL(rawValue: remoteURL.path)
        request.credentials = nil
        return try await live.clone(request)
    }
    sourceControl.open = { url in
        recorder.record("open")
        return try await live.open(url)
    }
    sourceControl.fetch = { request in
        recorder.record("fetch")
        var request = request
        request.credentials = nil
        try await live.fetch(request)
    }
    sourceControl.checkout = { request in
        recorder.record("checkout")
        try await live.checkout(request)
    }
    sourceControl.createBranch = { request in
        recorder.record("createBranch")
        return try await live.createBranch(request)
    }
    sourceControl.status = { repository in
        recorder.record("status")
        return try await live.status(repository)
    }
    sourceControl.stage = { request in
        recorder.record("stage")
        try await live.stage(request)
    }
    sourceControl.commit = { request in
        recorder.record("commit")
        return try await live.commit(request)
    }
    sourceControl.resolveRevision = { request in
        recorder.record("resolve:\(request.ref.rawValue)")
        return try await live.resolveRevision(request)
    }
    sourceControl.formatPatch = { request in
        recorder.record("formatPatch")
        return try await live.formatPatch(request)
    }
    sourceControl.emailPatch = { request in
        recorder.record("emailPatch")
        return try await live.emailPatch(request)
    }
    sourceControl.push = { request in
        recorder.record("push")
        var request = request
        request.credentials = nil
        try await live.push(request)
    }
    return sourceControl
}

struct WorkspaceStoryProposalScenario: CustomStringConvertible, Sendable {
    var target: EventTarget
    var failsPublication = false
    var failsReferenceApplication = false
    var signsIn = false

    var description: String {
        if failsPublication { return "\(target)-patch-publication-failure" }
        if failsReferenceApplication { return "\(target)-reference-application-failure" }
        if signsIn { return "\(target)-sign-in-success" }
        return "\(target)-success"
    }
}

private struct WorkspaceStoryPatchPublicationFailure: Error {}

private struct WorkspaceStoryContextSelectionFailure: Error {}

@Feature
private struct WorkspaceStoryLiveApplicationHarness {
    struct State {
        var application: OpenMusicEventApplication.State?
    }

    enum Action {
        case application(OpenMusicEventApplication.Action)
        case dismount
    }

    let requestCenter: AuthorizationRequestCenter
    let storage: OAuthSessionStorage

    var body: some Feature {
        Update { state, action in
            switch action {
            case .application:
                break

            case .dismount:
                state.application = nil
            }
        }
        .ifLet(\.application, action: \.application) {
            OpenMusicEventApplication(
                storage: storage,
                requestCenter: requestCenter
            ) {
                OpenMusicEventAppRoot()
            }
                .presentAuthorizationFailures()
                .deliverAuthoringAuthorizationChanges()
        }
    }
}

@MainActor
private final class WorkspaceStoryLiveStore {
    private let store: Store<
        WorkspaceStoryLiveApplicationHarness.State,
        WorkspaceStoryLiveApplicationHarness.Action
    >

    init(
        initialState: OpenMusicEventApplication.State,
        storage: OAuthSessionStorage,
        requestCenter: AuthorizationRequestCenter
    ) {
        store = Store(
            initialState: WorkspaceStoryLiveApplicationHarness.State(
                application: initialState
            )
        ) {
            WorkspaceStoryLiveApplicationHarness(
                requestCenter: requestCenter,
                storage: storage
            )
        }
    }

    var state: OpenMusicEventApplication.State {
        applicationStore.state
    }

    @discardableResult
    func send(
        _ action: OpenMusicEventApplication.Action
    ) -> Task<Void, Never>? {
        applicationStore.send(action)
    }

    @discardableResult
    func send<Child: FeatureProtocol>(
        to stateKeyPath: KeyPath<OpenMusicEventApplication.State, Spawn<Child>>,
        _ action: Child.Action
    ) -> Task<Void, Never>? {
        applicationStore.spawn(stateKeyPath).send(action)
    }

    @discardableResult
    func send<Child: FeatureProtocol>(
        to stateKeyPath: KeyPath<OpenMusicEventApplication.State, Spawn<Child>?>,
        _ action: Child.Action
    ) -> Task<Void, Never>? {
        applicationStore.spawn(stateKeyPath)?.send(action)
    }

    func modify(
        _ update: (inout OpenMusicEventApplication.State) -> Void
    ) {
        @Bindable var applicationStore = applicationStore
        var state = applicationStore.state
        update(&state)
        $applicationStore[dynamicMember: \.self].wrappedValue = state
    }

    func dismount(timeout: Duration) async {
        _ = timeout
        await store.send(.dismount)?.value
    }

    private var applicationStore: Store<
        OpenMusicEventApplication.State,
        OpenMusicEventApplication.Action
    > {
        guard let applicationStore = store.scope(\.application, action: \.application) else {
            preconditionFailure("The workspace story application is not mounted.")
        }
        return applicationStore
    }
}

private enum WorkspaceStoryDependencyPropagationBoundary: CaseIterable, Equatable, Sendable {
    case preparedScope
    case openingTask
    case installationUpdate
    case installationTask
    case childState
    case childMount
}

private struct WorkspaceStoryDependencyPropagationObservation: Equatable, Sendable {
    var boundary: WorkspaceStoryDependencyPropagationBoundary
    var matchesPreparedDatabase: Bool
}

private final class WorkspaceStoryDependencyPropagationRecorder: Sendable {
    let observations = Mutex<[WorkspaceStoryDependencyPropagationObservation]>([])
    let preparedDatabaseID: ObjectIdentifier

    init(database: any DatabaseWriter) {
        preparedDatabaseID = ObjectIdentifier(database)
    }

    var snapshot: [WorkspaceStoryDependencyPropagationObservation] {
        observations.withLock { $0 }
    }

    func record(
        _ boundary: WorkspaceStoryDependencyPropagationBoundary,
        database: any DatabaseWriter
    ) {
        observations.withLock {
            $0.append(
                WorkspaceStoryDependencyPropagationObservation(
                    boundary: boundary,
                    matchesPreparedDatabase: ObjectIdentifier(database) == preparedDatabaseID
                )
            )
        }
    }
}

@Feature
private struct WorkspaceStoryDependencyPropagationProbe {
    struct State {
        var child: Child.State?
    }

    enum Action {
        case child(Child.Action)
        case install
        case open
    }

    @Feature
    struct Child {
        struct State {
            init(recorder: WorkspaceStoryDependencyPropagationRecorder) {
                @Dependency(\.defaultDatabase) var database
                recorder.record(.childState, database: database)
            }

            var isMounted = false
        }

        enum Action {
            case mounted
        }

        @Dependency(\.defaultDatabase) var database
        let recorder: WorkspaceStoryDependencyPropagationRecorder

        var body: some Feature {
            Update { _, _ in }
                .onMount { state in
                    recorder.record(.childMount, database: database)
                    state.isMounted = true
                }
        }
    }

    @Dependency(\.defaultDatabase) var database
    let recorder: WorkspaceStoryDependencyPropagationRecorder

    var body: some Feature {
        Update { _, action in
            switch action {
            case .child:
                break

            case .install:
                recorder.record(.installationUpdate, database: database)
                store.addTask {
                    let installation = AsyncStream<Void> { continuation in
                        continuation.yield()
                        continuation.finish()
                    }
                    for await _ in installation {}

                    @Dependency(\.defaultDatabase) var taskDatabase
                    recorder.record(.installationTask, database: taskDatabase)
                    let child = Child.State(recorder: recorder)
                    let mount = try store.modify { $0.child = child }
                    await mount?.value
                }

            case .open:
                store.addTask {
                    await Task.yield()
                    @Dependency(\.defaultDatabase) var taskDatabase
                    recorder.record(.openingTask, database: taskDatabase)
                    let install = try store.send(.install)
                    await install?.value
                }
            }
        }
        .ifLet(\.child, action: \.child) {
            Child(recorder: recorder)
        }
    }
}

@MainActor
private func workspaceStoryOpenEvent(
    _ store: WorkspaceStoryLiveStore,
    route _: AppRoute,
    url: URL
) async throws {
    await store.send(.content(.openURL(url)))?.value
    try await workspaceStoryWaitUntil {
        guard let phase = store.state.content.destination?.eventViewer?.authoring.phase else {
            return false
        }
        return phase != .restoring
    }
}

@MainActor
private func workspaceStoryOpenEvent<Subject: FeatureProtocol>(
    _ store: TestStore<Subject>,
    route: AppRoute,
    url: URL
) async where
    Subject.State == OpenMusicEventApplication.State,
    Subject.Action == OpenMusicEventApplication.Action
{
    await store.send(.content(.openURL(url)))?.value
    let open = await store.receive(
        \.content,
        .matching { action in
            guard case let .openRoute(receivedRoute) = action else { return false }
            return receivedRoute == route
        },
        timeout: .seconds(1)
    )
    await open?.value
    let restore = await store.receive(
        \.content,
        .matching { action in
            guard case .destination(
                .eventViewer(.authoring(.restoreAuthorization))
            ) = action
            else { return false }
            return true
        },
        timeout: .seconds(1)
    )
    await restore?.value
}

private func workspaceStoryProposalAction(
    _ action: WorkspaceChanges.Action
) -> OpenMusicEventApplication.Action {
    workspaceStoryWorkspaceAction(.changes(action))
}

private func workspaceStoryWorkspaceAction(
    _ action: EventWorkspace.Action
) -> OpenMusicEventApplication.Action {
    .content(
        .destination(
            .eventViewer(
                .authoring(
                    .content(
                        .content(
                            .eventWorkspace(action)
                        )
                    )
                )
            )
        )
    )
}

private func workspaceStoryEventViewerAction(
    _ action: EventViewer.Action
) -> OpenMusicEventApplication.Action {
    .content(
        .destination(
            .eventViewer(
                .authoring(
                    .content(
                        .content(action)
                    )
                )
            )
        )
    )
}

private struct WorkspaceStoryUnexpectedSourceControlOperation: Error {}

private struct WorkspaceStoryFirstPreparationFailure: Error {}

private actor WorkspaceStoryPreparationPause {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func continuePreparation() {
        precondition(started, "Source preparation has not started.")
        continuation?.resume()
        continuation = nil
    }

    func prepare(
        _ workspace: SourceWorkspace,
        live: SourceWorkspacePreparationClient
    ) async throws -> WorkspaceSession<SourceWorkspaceResource> {
        precondition(!started, "Source preparation unexpectedly started more than once.")
        await withCheckedContinuation {
            continuation = $0
            started = true
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
        return try await live.prepare(workspace)
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private actor WorkspaceStoryPreparationGate {
    private var attempt = 0
    private var firstAttemptStarted = false
    private var firstAttemptStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstAttemptFailure: CheckedContinuation<Void, Never>?

    func prepare(
        _ workspace: SourceWorkspace,
        live: SourceWorkspacePreparationClient
    ) async throws -> WorkspaceSession<SourceWorkspaceResource> {
        attempt += 1
        guard attempt == 1 else {
            return try await live.prepare(workspace)
        }

        firstAttemptStarted = true
        for waiter in firstAttemptStartWaiters {
            waiter.resume()
        }
        firstAttemptStartWaiters.removeAll()
        await withCheckedContinuation { continuation in
            firstAttemptFailure = continuation
        }
        throw WorkspaceStoryFirstPreparationFailure()
    }

    func waitUntilFirstAttemptStarts() async {
        guard !firstAttemptStarted else { return }
        await withCheckedContinuation { continuation in
            firstAttemptStartWaiters.append(continuation)
        }
    }

    func failFirstAttempt() {
        precondition(firstAttemptStarted, "The first preparation attempt has not started.")
        firstAttemptFailure?.resume()
        firstAttemptFailure = nil
    }
}

private actor WorkspaceStoryCheckoutPause {
    private var checkoutContinuation: CheckedContinuation<Void, Never>?
    private var isStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        precondition(!isStarted, "Published-source checkout unexpectedly started more than once.")
        isStarted = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            checkoutContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func continueCheckout() {
        precondition(isStarted, "Published-source checkout has not started.")
        checkoutContinuation?.resume()
        checkoutContinuation = nil
    }
}

private final class WorkspaceStorySourceControlRecorder: Sendable {
    private let failsNextCheckout = Mutex(false)
    private let operations = Mutex<[String]>([])

    var snapshot: [String] { operations.withLock { $0 } }

    func record(_ operation: String) {
        operations.withLock { $0.append(operation) }
    }

    func count(of operation: String) -> Int {
        operations.withLock { $0.count(where: { $0 == operation }) }
    }

    func count(prefix: String) -> Int {
        operations.withLock { $0.count(where: { $0.hasPrefix(prefix) }) }
    }

    func failNextCheckout() {
        failsNextCheckout.withLock { $0 = true }
    }

    func takeCheckoutFailure() -> Bool {
        failsNextCheckout.withLock { failure in
            defer { failure = false }
            return failure
        }
    }
}

private func makeWorkspaceStoryDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OMERecord.DatabaseMigrations.register(into: &migrator)
    OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func workspaceStoryEventID(
    organizerID: OMERecord.Organizer.ID,
    localID: String
) -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(.init(localID))
    )
}

private func insertUnrelatedWorkspaceStoryEvent(
    into database: any DatabaseWriter
) async throws -> OMERecord.Event.ID {
    let organizerID = try #require(OMERecord.Organizer.ID("did:plc:otherfestival"))
    let eventID = workspaceStoryEventID(organizerID: organizerID, localID: "other-festival")
    let timeZone = try #require(TimeZone(identifier: "America/Denver"))
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
        try OMERecord.Event.insert {
            OMERecord.Event.Draft(
                id: eventID,
                name: "Other Festival",
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
        try EventSourceProvenanceRecord.insert {
            EventSourceProvenanceRecord(
                id: eventID,
                sourceKind: .tangled,
                sourceReference: "tangled.org/other/other-festival",
                ref: "main",
                eventIDOrigin: .explicit,
                sourceEventDirectory: "other"
            )
        }
        .execute(db)
    }
    return eventID
}

private func workspaceStoryEventNames(
    in database: any DatabaseReader
) async throws -> [String] {
    try await database.read { db in
        try OMERecord.Event.fetchAll(db).map(\.name).sorted()
    }
}

private func writeWorkspaceStorySource(
    organizerID: OMERecord.Organizer.ID,
    selectedEventName: String = "Wicked Woods 2026",
    to repositoryURL: URL
) throws {
    let timeZone = try #require(TimeZone(identifier: "America/Denver"))
    let source = OpenMusicEventSourceRepository(
        events: [
            workspaceStorySourceEvent(
                id: workspaceStoryEventID(
                    organizerID: organizerID,
                    localID: "ome-workspace-2025"
                ),
                directoryName: "2025",
                name: "Wicked Woods 2025",
                timeZone: timeZone
            ),
            workspaceStorySourceEvent(
                id: workspaceStoryEventID(
                    organizerID: organizerID,
                    localID: "ome-workspace-2026"
                ),
                directoryName: "2026",
                name: selectedEventName,
                timeZone: timeZone
            ),
        ]
    )
    _ = try OpenMusicEventSourceRepositoryFileTree().write(source, to: repositoryURL)
}

private func workspaceStorySourceEvent(
    id: OMERecord.Event.ID,
    directoryName: String,
    name: String,
    timeZone: TimeZone
) -> DirectoryContent<OpenMusicEventSourceEvent> {
    DirectoryContent(
        directoryName: directoryName,
        components: OpenMusicEventSourceEvent(
            event: EventDTO(
                id: id,
                name: name,
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
}

private func workspaceStoryAccountClient(
    actorID: DID
) -> Atmosphere.Account.Client {
    let account = Atmosphere.Account(
        id: .init(actorID),
        handle: Atmosphere.Account.Handle("woody.fm")
    )
    return Atmosphere.Account.Client(
        resolveHandle: { _ in
            (account, try workspaceStoryDIDDocument(did: actorID))
        },
        resolveDID: { _ in
            (account, try workspaceStoryDIDDocument(did: actorID))
        }
    )
}

private func workspaceStoryTangledRecordsHTTPClient() -> HTTPClient {
    HTTPClient { request, _ in
        #expect(request.url?.path == "/xrpc/com.atproto.repo.listRecords")
        return Data(
            """
            {
              "records": [
                {
                  "uri": "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/3repo",
                  "cid": "bafyreifakerepo",
                  "value": {
                    "$type": "sh.tangled.repo",
                    "name": "ome-workspace",
                    "repoDid": "did:plc:workspace-source-repository",
                    "knot": "tangled.org",
                    "createdAt": "2026-05-26T17:30:42Z"
                  }
                }
              ]
            }
            """.utf8
        )
    }
}

private func workspaceStoryDIDDocument(did: DID) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://woody.fm"],
              "verificationMethod": [],
              "service": [
                {
                  "id": "#atproto_pds",
                  "type": "AtprotoPersonalDataServer",
                  "serviceEndpoint": "https://owner.pds.example"
                }
              ]
            }
            """.utf8
        )
    )
}

@MainActor
private func withWorkspaceStoryOAuthSession<Result>(
    actorID: DID,
    operation: @MainActor () async throws -> Result
) async rethrows -> Result {
    let originalStore = OpenMusicEventOAuth.sessionStore.wrappedValue
    let originalSelection = OpenMusicEventOAuth.selectedSessionID.wrappedValue
    let session = OAuth.Session(
        accountID: Atmosphere.Account.ID(actorID),
        pdsHost: "owner.pds.example",
        tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
            URL(string: "https://owner.pds.example/oauth/token")!
        ),
        scope: OAuth.Scope(
            rawValue: Set([OAuth.Permission.atproto])
                .union(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions
                )
                .map(\.rawValue)
                .sorted()
                .joined(separator: " ")
        ),
        accessToken: OAuth.AccessToken(rawValue: "workspace-story-access-token"),
        refreshToken: OAuth.RefreshToken(rawValue: "workspace-story-refresh-token"),
        dpopKey: OAuth.DPOP.Key()
    )
    OpenMusicEventOAuth.sessionStore.withLock {
        $0 = OAuth.SessionStore(
            selectedAccountID: session.accountID,
            sessions: [actorID: session]
        )
    }
    OpenMusicEventOAuth.selectedSessionID.withLock { $0 = session.accountID }
    defer {
        OpenMusicEventOAuth.sessionStore.withLock { $0 = originalStore }
        OpenMusicEventOAuth.selectedSessionID.withLock { $0 = originalSelection }
    }
    return try await operation()
}

@MainActor
private func workspaceStoryWaitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while clock.now < deadline {
        if condition() { return }
        try await clock.sleep(for: .milliseconds(1))
    }
    Issue.record(
        "Condition was not satisfied within one second.",
        sourceLocation: sourceLocation
    )
    try #require(condition())
}
