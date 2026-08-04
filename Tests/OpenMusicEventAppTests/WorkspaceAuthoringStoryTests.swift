import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import ComposableWorkspace
import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SQLiteData
import Sharing
import SourceEditing
import Synchronization
import Testing
import XRPCClient

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
    @Test(.tcaExhaustivity(.off))
    func `authorized entry prepares the organization workspace once and durable reentry only validates it`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2026"
        )
        let olderEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "ome-workspace-2025"
        )
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-WorkspaceAuthoringStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }
        let git = try WorkspaceStoryGitFixture(
            organizerID: organizerID,
            rootURL: storageRoot.appending(path: "git", directoryHint: .isDirectory)
        )
        let operations = WorkspaceStorySourceControlRecorder()
        let authenticationStorage = workspaceStoryOAuthStorage(actorID: organizerID)
        let route = AppRoute.event(selectedEventID, .settings)
        let routeURL = try #require(URL(string: "ome://workspace-story\(route.path)"))

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.omeEventInstallation = .liveValue
            $0.uuid = .incrementing
            $0.sourceWorkspaceStorage = .fileBacked(rootURL: storageRoot.appending(path: "workspaces"))
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                organizerID: organizerID
            )
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                organizerID: organizerID,
                archive: git.archive
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

            // Browsing is entered through the app URL and installs only the selected event.
            let browsedEventNames = try await workspaceStoryEventNames(in: database)
            expectNoDifference(
                browsedEventNames,
                ["Wicked Woods 2026"]
            )
            #expect(operations.snapshot.isEmpty)
            expectNoDifference(opened.state.content.eventViewer?.authoring.canEnter, true)

            // The visible Event Settings control owns authorization and workspace preparation.
            await opened.send(
                to: \.content.eventViewer!.authoring.content.content.eventSettings!,
                .enterAuthoringButtonTapped
            )?.value

            let authoring = try #require(opened.state.content.eventViewer?.authoring)
            let workspace = authoring.context
            let resource = try #require(authoring.content.source)
            expectNoDifference(authoring.grant?.principal, AuthoringPrincipal(actorID: organizerID))
            expectNoDifference(authoring.grant?.role, .owner)
            guard case .ready(.canonical(_)) = authoring.content.phase else {
                Issue.record("First preparation must establish the canonical editing line.")
                return
            }
            #expect(authoring.content.content.eventWorkspace != nil)
            expectNoDifference(operations.count(of: "clone"), 1)
            #expect(operations.count(prefix: "resolve:") > 0)
            let preparedEventNames = try await workspaceStoryEventNames(in: database)
            expectNoDifference(
                preparedEventNames,
                ["Wicked Woods 2025", "Wicked Woods 2026"]
            )
            let olderEventIsInstalled = try await database.read { db in
                try OMERecord.Event.find(olderEventID).fetchOne(db) != nil
            }
            #expect(olderEventIsInstalled)

            // A real editor action opens the live form. TestStore.modify is the same blessed
            // binding entry point used by SwiftUI, and save writes through Workspace's database.
            await opened.send(
                to: \.content.eventViewer!.authoring.content.content.eventInfoViewer!,
                .editButtonTapped
            )?.value
            opened.modify {
                guard var eventViewer = $0.content.eventViewer,
                      var form = eventViewer
                        .authoring.content.content.destination?
                        .eventInfoForm
                else { return }
                form.draft.name = "Wicked Woods 2026 - Local Edit"
                eventViewer.authoring.content.content.destination = .eventInfoForm(form)
                $0.content.eventViewer = eventViewer
            }
            await opened.send(
                .content(
                    .destination(
                        .eventViewer(
                            .authoring(
                                .content(
                                    .content(
                                        .destination(
                                            .eventInfoForm(.saveButtonTapped)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )?.value

            let editedEventNames = try await workspaceStoryEventNames(in: database)
            expectNoDifference(
                editedEventNames,
                ["Wicked Woods 2025", "Wicked Woods 2026 - Local Edit"]
            )
            let editedSummary = try await resource.database.read { db in
                try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
            }
            #expect(editedSummary.totalCount > 0)

            // Proposal creation is driven only through the mounted WorkspaceChanges surface.
            opened.send(workspaceStoryProposalAction(.proposalActionButtonTapped))
            opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(.titleChanged("Update the 2026 event"))
                )
            )
            opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(.descriptionChanged("Exercise the complete proposal stack."))
                )
            )
            await opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(.createProposalButtonTapped)
                )
            )?.value

            let proposal = try #require(
                opened.state.content.eventViewer?
                    .authoring.content.content.eventWorkspace?
                    .changes.openProposal
            )
            guard case let .ready(.proposal(recordedProposal)) = opened.state.content.eventViewer?
                .authoring.content.phase,
                recordedProposal == proposal
            else {
                Issue.record("Creating the proposal must advance Workspace to its proposal line.")
                return
            }
            #expect(operations.count(of: "createBranch") == 1)
            #expect(operations.count(of: "checkout") == 1)
            #expect(operations.count(of: "stage") == 1)
            #expect(operations.count(of: "commit") == 1)
            #expect(operations.count(of: "formatPatch") == 1)
            #expect(operations.count(of: "push") == 1)

            // Exiting revokes the grant, but the settled workspace and proposal survive by design.
            await opened.send(
                to: \.content.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            #expect(opened.state.content.eventViewer?.authoring.grant == nil)
            guard case let .ready(.proposal(settledProposal)) = opened.state.content.eventViewer?
                .authoring.content.phase,
                settledProposal == proposal
            else {
                Issue.record("Grant loss must not discard the settled proposal workspace.")
                return
            }

            let openedRepositoriesBeforeRemount = operations.count(of: "open")
            await opened.dismount(timeout: .seconds(1))

            // A fresh application mount enters through the same settings action. It must open and
            // validate the durable repository and proposal rather than cloning or reinstalling it.
            let remountedStore = TestStore(
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
            await workspaceStoryOpenEvent(remountedStore, route: route, url: routeURL)
            await remountedStore.send(
                to: \.content.eventViewer!.authoring.content.content.eventSettings!,
                .enterAuthoringButtonTapped
            )?.value

            let remountedAuthoring = try #require(
                remountedStore.state.content.eventViewer?.authoring
            )
            expectNoDifference(remountedAuthoring.grant?.role, .owner)
            expectNoDifference(remountedAuthoring.content.phase, .ready(.proposal(proposal)))
            expectNoDifference(
                remountedAuthoring.content.content.eventWorkspace?.changes.openProposal,
                proposal
            )
            expectNoDifference(operations.count(of: "clone"), 1)
            #expect(operations.count(of: "open") > openedRepositoriesBeforeRemount)
            let remountedEventNames = try await workspaceStoryEventNames(in: database)
            expectNoDifference(
                remountedEventNames,
                ["Wicked Woods 2025", "Wicked Woods 2026 - Local Edit"]
            )
            await remountedStore.dismount(timeout: .seconds(1))
        }
    }

    @Test(.tcaExhaustivity(.off))
    func `active authoring owns Workspace while source preparation fails and retries`() async throws {
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
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            let livePreparation = $0[SourceWorkspacePreparationClient.self]
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.omeEventInstallation = .liveValue
            $0.uuid = .incrementing
            $0.sourceWorkspaceStorage = .fileBacked(
                rootURL: storageRoot.appending(path: "workspaces")
            )
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                organizerID: organizerID
            )
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                organizerID: organizerID,
                archive: git.archive
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations
            )
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
            expectNoDifference(opened.state.content.eventViewer?.authoring.canEnter, true)

            // The Settings action activates authoring. Workspace availability follows the grant,
            // while source preparation remains independently suspended at its external boundary.
            let entry = opened.send(
                to: \.content.eventViewer!.authoring.content.content.eventSettings!,
                .enterAuthoringButtonTapped
            )
            await preparationGate.waitUntilFirstAttemptStarts()

            let preparingAuthoring = try #require(
                opened.state.content.eventViewer?.authoring
            )
            let preparingGrant = try #require(preparingAuthoring.grant)
            expectNoDifference(
                preparingGrant.principal,
                AuthoringPrincipal(actorID: organizerID)
            )
            expectNoDifference(preparingGrant.role, .owner)
            expectNoDifference(preparingAuthoring.content.phase, .preparingSource)
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
            expectNoDifference(preparingWorkspace.workspacePhase, .preparingSource)
            expectNoDifference(
                preparingWorkspace.changes.summary.availability,
                .workspaceNeedsPreparation
            )

            // Failure is presented by the same mounted Workspace; it does not revoke authoring.
            await preparationGate.failFirstAttempt()
            await entry?.value
            let failedAuthoring = try #require(opened.state.content.eventViewer?.authoring)
            guard case .sourcePreparationFailed = failedAuthoring.content.phase else {
                Issue.record("The controlled first preparation must fail in Workspace.")
                return
            }
            #expect(failedAuthoring.grant != nil)
            #expect(failedAuthoring.content.source == nil)
            #expect(failedAuthoring.content.content.eventWorkspace != nil)
            #expect(failedAuthoring.content.content.installedFeatures.contains(.workspace))
            #expect(failedAuthoring.content.content.authoringAccess.canEditContent)

            // Retry starts at EventWorkspace, crosses the app event bridge, and reaches the shared
            // Workspace state machine before executing the real source preparation implementation.
            await opened.send(
                workspaceStoryWorkspaceAction(.sourcePreparationRetryButtonTapped)
            )?.value
            let readyAuthoring = try #require(opened.state.content.eventViewer?.authoring)
            guard case .ready(.canonical) = readyAuthoring.content.phase else {
                Issue.record("Workspace retry must establish the canonical editing line.")
                return
            }
            #expect(readyAuthoring.content.source != nil)
            #expect(readyAuthoring.content.content.eventWorkspace != nil)
            #expect(readyAuthoring.content.content.installedFeatures.contains(.workspace))
            expectNoDifference(operations.count(of: "clone"), 1)

            // Exiting authoring removes Workspace from navigation even though its settled state is
            // retained for durable reentry.
            await opened.send(
                to: \.content.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            let exited = try #require(opened.state.content.eventViewer?.authoring)
            #expect(exited.grant == nil)
            expectNoDifference(exited.content.content.authoringAccess, .attendee)
            #expect(!exited.content.content.installedFeatures.contains(.workspace))
            #expect(exited.content.content.eventWorkspace != nil)
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
                OME.prepareDependencies(&$0, database: database)
                $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
                $0.uuid = .incrementing
                $0.tangledRepositoryMembership = TangledRepositoryMembershipClient {
                    _, _, _ in false
                }
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
                    store.content.eventViewer?.authoring.admission == .unavailable
                }

                expectNoDifference(store.content.eventViewer?.authoring.canEnter, false)
                #expect(store.content.eventViewer?.authoring.grant == nil)
                expectNoDifference(
                    store.content.eventViewer?.authoring.content.phase,
                    .inactive
                )
                #expect(operations.snapshot.isEmpty)
            }
        }
    }
}

private struct WorkspaceStoryGitFixture {
    let archive: Data
    let bareRepositoryURL: URL

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

private func workspaceStoryNetwork(
    organizerID: DID,
    archive: Data
) -> RunHTTPRequest {
    { request, _ in
        let path = request.url?.path ?? ""
        func ok(_ data: Data) -> (Data, HTTPResponse) {
            (data, HTTPResponse(status: .ok))
        }

        if path.hasSuffix("/archive/main.tar.gz") {
            return ok(archive)
        }
        if path.hasSuffix("/com.atproto.repo.listRecords") {
            return ok(Data(
                """
                {
                  "records": [
                    {
                      "uri": "at://\(organizerID)/sh.tangled.repo/ome-workspace",
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
            return ok(Data(
                """
                {
                  "uri": "at://\(organizerID)/sh.tangled.repo.pull/workspace-story",
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
    sourceControl.push = { request in
        recorder.record("push")
        var request = request
        request.credentials = nil
        try await live.push(request)
    }
    return sourceControl
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

private struct WorkspaceStoryUnexpectedSourceControlOperation: Error {}

private struct WorkspaceStoryFirstPreparationFailure: Error {}

private actor WorkspaceStoryPreparationGate {
    private var attempt = 0
    private var firstAttemptStarted = false
    private var firstAttemptStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstAttemptFailure: CheckedContinuation<Void, Never>?

    func prepare(
        _ workspace: SourceWorkspace,
        live: SourceWorkspacePreparationClient
    ) async throws -> WorkspacePreparation<SourceWorkspaceResource> {
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

private final class WorkspaceStorySourceControlRecorder: Sendable {
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
                name: "Wicked Woods 2026",
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
    organizerID: DID
) -> Atmosphere.Account.Client {
    let account = Atmosphere.Account(
        id: .init(organizerID),
        handle: Atmosphere.Account.Handle("woody.fm")
    )
    return Atmosphere.Account.Client(
        resolveHandle: { _ in
            (account, try workspaceStoryDIDDocument(did: organizerID))
        },
        resolveDID: { _ in
            (account, try workspaceStoryDIDDocument(did: organizerID))
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
