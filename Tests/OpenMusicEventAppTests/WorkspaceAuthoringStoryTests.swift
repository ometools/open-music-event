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
import IssueReporting
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
    @Test(
        .tcaExhaustivity(.off),
        arguments: [
            WorkspaceStoryProposalScenario(target: .settings, signsIn: true),
            WorkspaceStoryProposalScenario(target: .workspace),
            WorkspaceStoryProposalScenario(target: .settings, failsPush: true),
        ]
    )
    func `a source repository owner edits an organizer's event and publishes workspace changes`(
        _ scenario: WorkspaceStoryProposalScenario
    ) async throws {
        let target = scenario.target
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
        let originalSessionStore = OpenMusicEventOAuth.sessionStore.wrappedValue
        let originalSelectedSessionID = OpenMusicEventOAuth.selectedSessionID.wrappedValue
        let originalAuthFailure = OpenMusicEventOAuth.authFailureMessage.wrappedValue
        defer {
            if scenario.signsIn {
                OpenMusicEventOAuth.sessionStore.withLock { $0 = originalSessionStore }
                OpenMusicEventOAuth.selectedSessionID.withLock { $0 = originalSelectedSessionID }
                OpenMusicEventOAuth.authFailureMessage.withLock { $0 = originalAuthFailure }
            }
        }
        let authenticationStorage: OAuthSessionStorage
        if scenario.signsIn {
            OpenMusicEventOAuth.sessionStore.withLock { $0 = OAuth.SessionStore() }
            OpenMusicEventOAuth.selectedSessionID.withLock { $0 = nil }
            OpenMusicEventOAuth.authFailureMessage.withLock { $0 = nil }
            authenticationStorage = OpenMusicEventOAuth.storage
        } else {
            authenticationStorage = workspaceStoryOAuthStorage(actorID: repositoryOwnerID)
        }
        let route = AppRoute.event(selectedEventID, target)
        let routeURL = try #require(URL(string: "ome://workspace-story\(route.path)"))
        let authorizationRequestCenter = AuthorizationRequestCenter()

        try await withDependencies {
            $0.context = .test
            // Keep OME's database, installation, source import, diff, and proposal stack live.
            OME.prepareDependencies(&$0, database: database)
            let liveSourceControl = $0.sourceControl
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.omeEventInstallation = .liveValue
            $0.uuid = .incrementing
            // The second app mount must reopen this checkout instead of creating another one.
            $0.sourceWorkspaceStorage = .fileBacked(rootURL: storageRoot.appending(path: "workspaces"))
            // The selected OAuth account owns the source repository but is not the event organizer.
            $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                actorID: repositoryOwnerID
            )
            // Exercise OME's live membership and authorization clients against fixture transport.
            $0.tangledRepositoryMembership = .liveValue
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = workspaceStoryNetwork(
                organizerID: repositoryOwnerID,
                archive: git.archive
            )
            if scenario.signsIn {
                $0.openMusicEventAuthorizationRequests = OAuthAuthorizationRequests(
                    center: authorizationRequestCenter
                )
                $0[OAuth.Client.self] = workspaceStoryOAuthClient(actorID: repositoryOwnerID)
                $0.defaultPort = 443
                $0.oauthAppConfiguration = OpenMusicEventOAuth.appConfiguration
                $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
                $0.oauthBrowserStrategy = .webAuthenticationSession
                $0.webAuthenticationSession.open = { _, _ in
                    workspaceStoryOAuthCallbackURL
                }
            }
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                .sshAgent(hostKeyPolicy: .acceptForTesting)
            }
            // Run real Git operations against the local bare remote and record their user-visible effects.
            $0.sourceControl = workspaceStorySourceControl(
                live: liveSourceControl,
                remoteURL: git.bareRepositoryURL,
                recorder: operations,
                failsPush: scenario.failsPush
            )
        } operation: {
            let opened = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(
                    storage: authenticationStorage,
                    requestCenter: authorizationRequestCenter
                ) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(opened, route: route, url: routeURL)

            let eligibility = AuthoringEligibility(
                principal: AuthoringPrincipal(actorID: repositoryOwnerID),
                role: .owner
            )

            if scenario.signsIn {
                expectNoDifference(
                    opened.state.content.destination?.eventViewer?.authoring.phase,
                    .inactive(.unavailable)
                )
                #expect(opened.state.authentication.session == nil)
                #expect(operations.snapshot.isEmpty)

                await opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.account,
                    .signInButtonTapped
                )?.value
                let signInTask = opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.account,
                    .signInActorIdentityTapped(
                        ActorIdentity(
                            did: repositoryOwnerID,
                            handle: Atmosphere.Account.Handle(rawValue: "woody.fm"),
                            displayName: "Woody",
                            source: .typeahead
                        )
                    )
                )
                // Selecting an account supplies a login hint, so authorization uses the direct
                // browser route and completes from the mocked callback without presenting a sheet.
                await signInTask?.value
                if let failure = opened.state.authentication.authorizationFailure {
                    Issue.record(
                        "Authorization failed: \(failure.message) \(String(describing: failure.subtitle)) \(String(describing: failure.originalError))"
                    )
                }
                let signedInAccount = try #require(
                    opened.state.content.destination?.eventViewer?.authoring.content.content.account
                )
                expectNoDifference(signedInAccount.state.errorMessage, nil)
                expectNoDifference(
                    signedInAccount.state.selectedSessionID,
                    Atmosphere.Account.ID(repositoryOwnerID)
                )
                expectNoDifference(
                    opened.state.authentication.session?.accountID,
                    Atmosphere.Account.ID(repositoryOwnerID)
                )
                try await workspaceStoryWaitUntil {
                    opened.state.content.destination?.eventViewer?.authoring.phase
                        == .inactive(.eligible(eligibility))
                }
                expectNoDifference(
                    opened.state.authentication.session?.accountID,
                    Atmosphere.Account.ID(repositoryOwnerID)
                )
                #expect(opened.state.authentication.authorization == nil)
                #expect(opened.state.authentication.directAuthorization == nil)
                #expect(operations.snapshot.isEmpty)
            }

            if target == .settings {
                // Browsing Settings installs only the selected event until authoring is requested.
                let browsedEventNames = try await workspaceStoryEventNames(in: database)
                expectNoDifference(
                    browsedEventNames,
                    ["Wicked Woods 2026"]
                )
                #expect(operations.snapshot.isEmpty)
                expectNoDifference(
                    opened.state.content.destination?.eventViewer?.authoring.phase,
                    .inactive(.eligible(eligibility))
                )

                // The visible Event Settings control owns authorization and workspace preparation.
                await opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                    .enterAuthoringButtonTapped
                )?.value
            } else {
                // An editor deep link enters through the same eligibility and grant transition.
                try await workspaceStoryWaitUntil {
                    guard let authoring = opened.state.content.destination?.eventViewer?.authoring,
                          case .active = authoring.phase,
                          case .ready(.canonical) = authoring.content.phase
                    else { return false }
                    return true
                }
                expectNoDifference(
                    opened.state.content.destination?.eventViewer?.authoring.content.content
                        .pendingAuthoringEntry,
                    nil
                )
                expectNoDifference(
                    opened.state.content.destination?.eventViewer?.authoring.content.content.selectedFeature,
                    .workspace
                )
            }

            let authoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            let workspace = authoring.context
            let resource = try #require(authoring.content.source)
            expectNoDifference(
                authoring.grant?.principal,
                AuthoringPrincipal(actorID: repositoryOwnerID)
            )
            expectNoDifference(authoring.grant?.role, .owner)
            expectNoDifference(
                authoring.phase,
                .active(
                    AuthoringGrant(
                        principal: eligibility.principal,
                        role: eligibility.role,
                        workspaceID: authoring.context.id
                    )
                )
            )
            guard case .ready(.canonical(_)) = authoring.content.phase else {
                Issue.record("First preparation must establish the canonical editing line.")
                return
            }
            #expect(authoring.content.content.eventWorkspace != nil)
            expectNoDifference(
                authoring.content.content.eventWorkspace?.workspaceStatus,
                authoring.content.phase.editingLine.map(WorkspaceStatus.ready)
            )
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
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026"
            )

            // A real editor action opens the live form. TestStore.modify is the same blessed
            // binding entry point used by SwiftUI, and save writes through Workspace's database.
            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventInfoViewer!,
                .editButtonTapped
            )?.value
            opened.modify {
                guard var eventViewer = $0.content.destination?.eventViewer,
                      var form = eventViewer
                        .authoring.content.content.destination?
                        .eventInfoForm
                else { return }
                form.draft.name = "Wicked Woods 2026 - Local Edit"
                eventViewer.authoring.content.content.destination = .eventInfoForm(form)
                $0.content.destination = .eventViewer(eventViewer)
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
            // The event viewer mounted before authoring reflects the saved value without an app restart.
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026 - Local Edit"
            )

            // Exercise additional app-owned editor routes so the proposal covers more than one
            // record field and proves that the workspace captures a meaningful authoring session.
            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.contactInfoViewer!,
                .editButtonTapped
            )?.value
            try await workspaceStoryWaitUntil {
                opened.state.content.destination?.eventViewer?.authoring.content.content.destination?
                    .contactInfoForm?.hasLoadedDraft == true
            }
            await opened.send(
                workspaceStoryEventViewerAction(
                    .destination(.contactInfoForm(.addContactNumberButtonTapped))
                )
            )?.value
            opened.modify {
                guard var eventViewer = $0.content.destination?.eventViewer,
                      var form = eventViewer.authoring.content.content.destination?.contactInfoForm,
                      !form.contactNumbers.isEmpty
                else { return }
                form.contactNumbers[0].title = "Event office"
                form.contactNumbers[0].phoneNumber = "+1 303 555 0199"
                form.contactNumbers[0].description = "Questions during the event"
                eventViewer.authoring.content.content.destination = .contactInfoForm(form)
                $0.content.destination = .eventViewer(eventViewer)
            }
            await opened.send(
                workspaceStoryEventViewerAction(
                    .destination(.contactInfoForm(.saveButtonTapped))
                )
            )?.value

            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.locationViewer!,
                .editButtonTapped
            )?.value
            try await workspaceStoryWaitUntil {
                opened.state.content.destination?.eventViewer?.authoring.content.content.destination?
                    .locationForm?.hasLoadedDraft == true
            }
            await opened.send(
                workspaceStoryEventViewerAction(
                    .destination(.locationForm(.addLocationButtonTapped))
                )
            )?.value
            opened.modify {
                guard var eventViewer = $0.content.destination?.eventViewer,
                      var form = eventViewer.authoring.content.content.destination?.locationForm,
                      !form.locations.isEmpty
                else { return }
                form.locations[0].address = "123 Festival Road, Denver, CO"
                form.locations[0].directions = "Enter through the west gate."
                form.locations[0].hasCoordinates = true
                form.locations[0].latitude = "39.7392"
                form.locations[0].longitude = "-104.9903"
                eventViewer.authoring.content.content.destination = .locationForm(form)
                $0.content.destination = .eventViewer(eventViewer)
            }
            await opened.send(
                workspaceStoryEventViewerAction(
                    .destination(.locationForm(.saveButtonTapped))
                )
            )?.value

            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.stagesViewer!,
                .addButtonTapped
            )?.value
            try await workspaceStoryWaitUntil {
                opened.state.content.destination?.eventViewer?.authoring.content.content.destination?
                    .stageForm?.hasLoadedDraft == true
            }
            opened.modify {
                guard var eventViewer = $0.content.destination?.eventViewer,
                      var form = eventViewer.authoring.content.content.destination?.stageForm
                else { return }
                form.form.value.name = "Meadow Stage"
                form.category = "music"
                form.sortIndex = "1"
                form.colorHex = "#315C42"
                form.systemIconName = "music.mic"
                form.iconShortCode = "MS"
                eventViewer.authoring.content.content.destination = .stageForm(form)
                $0.content.destination = .eventViewer(eventViewer)
            }
            await opened.send(
                workspaceStoryEventViewerAction(
                    .destination(.stageForm(.saveButtonTapped))
                )
            )?.value

            let editedEvent = try await database.read { db in
                try #require(try OMERecord.Event.find(selectedEventID).fetchOne(db))
            }
            expectNoDifference(editedEvent.contactNumbers?.first?.title, "Event office")
            expectNoDifference(
                editedEvent.locations?.first?.address,
                "123 Festival Road, Denver, CO"
            )
            let editedStages = try await database.read { db in
                try OMERecord.Stage
                    .where { $0.id.organizerID.eq(selectedEventID.organizerID) }
                    .where { $0.id.eventID.eq(selectedEventID.eventID) }
                    .fetchAll(db)
            }
            #expect(editedStages.contains { $0.name == "Meadow Stage" })

            let editedSummary = try await database.read { db in
                try SourceWorkspaceEditSummary.query(
                    workspace: workspace,
                    in: db,
                    referenceDatabase: resource.referenceDatabase
                )
            }
            #expect(editedSummary.totalCount > 0)
            try await workspaceStoryWaitUntil {
                (opened.state.content.destination?.eventViewer?
                    .authoring.content.content.eventWorkspace?
                    .changes.summary.totalCount ?? 0) > 0
            }

            // Proposal creation is driven only through the mounted WorkspaceChanges surface.
            opened.send(workspaceStoryProposalAction(.proposalActionButtonTapped))
            opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(.titleChanged("Expand the 2026 event experience"))
                )
            )
            opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(
                        .descriptionChanged(
                            "Update event details, contact information, location, and stages."
                        )
                    )
                )
            )
            if scenario.failsPush {
                await withExpectedIssue {
                    await opened.send(
                        workspaceStoryProposalAction(
                            .proposalDraft(.createProposalButtonTapped)
                        )
                    )?.value
                }

                let failedAuthoring = try #require(
                    opened.state.content.destination?.eventViewer?.authoring
                )
                guard case let .publicationFailed(submission, failure) = failedAuthoring.content.phase
                else {
                    Issue.record("A failed push must leave Workspace in its publication failure phase.")
                    return
                }
                #expect(failure.message.contains("WorkspaceStoryPushFailure"))
                let failedWorkspace = try #require(
                    failedAuthoring.content.content.eventWorkspace
                )
                expectNoDifference(
                    failedWorkspace.workspaceStatus,
                    .failed(operation: .publication, failure: failure)
                )
                #expect(!failedWorkspace.workspaceIsReady)
                expectNoDifference(failedWorkspace.changes.openProposal, nil)

                // Publication failure blocks another proposal, not authoring. A subsequent real
                // editor save must remain available and durable while the failed submission is
                // preserved for diagnosis/recovery.
                await opened.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.eventInfoViewer!,
                    .editButtonTapped
                )?.value
                opened.modify {
                    guard var eventViewer = $0.content.destination?.eventViewer,
                          var form = eventViewer.authoring.content.content.destination?.eventInfoForm
                    else { return }
                    form.draft.name = "Wicked Woods 2026 - Continued after failure"
                    eventViewer.authoring.content.content.destination = .eventInfoForm(form)
                    $0.content.destination = .eventViewer(eventViewer)
                }
                await opened.send(
                    workspaceStoryEventViewerAction(
                        .destination(.eventInfoForm(.saveButtonTapped))
                    )
                )?.value
                expectNoDifference(
                    opened.state.content.destination?.eventViewer?.authoring.content.content.event?.name,
                    "Wicked Woods 2026 - Continued after failure"
                )
                #expect(operations.count(of: "push") == 1)

                await opened.dismount(timeout: .seconds(1))

                // A fresh app mount must recognize the durable local commit, restore the settled
                // source, and surface one interrupted publication instead of trapping the user in
                // source preparation with a persisted-revision mismatch.
                let remountedStore = TestStore(
                    initialState: OpenMusicEventApplication.State(
                        storage: authenticationStorage
                    ) {
                        OpenMusicEventAppRoot.State()
                    }
                ) {
                    OpenMusicEventApplication(
                        storage: authenticationStorage,
                        requestCenter: authorizationRequestCenter
                    ) {
                        OpenMusicEventAppRoot()
                    }
                        .presentAuthorizationFailures()
                        .deliverAuthoringAuthorizationChanges()
                }
                await workspaceStoryOpenEvent(remountedStore, route: route, url: routeURL)
                try await workspaceStoryWaitUntil {
                    guard case .publicationInterrupted = remountedStore.state.content.destination?
                        .eventViewer?.authoring.content.phase
                    else { return false }
                    return true
                }

                let recoveredAuthoring = try #require(
                    remountedStore.state.content.destination?.eventViewer?.authoring
                )
                expectNoDifference(
                    recoveredAuthoring.content.phase,
                    .publicationInterrupted(submission)
                )
                expectNoDifference(
                    recoveredAuthoring.content.content.eventWorkspace?.workspaceStatus,
                    .interrupted(.publication)
                )
                #expect(recoveredAuthoring.content.source != nil)
                #expect(recoveredAuthoring.content.content.eventWorkspace != nil)
                expectNoDifference(
                    recoveredAuthoring.content.content.event?.name,
                    "Wicked Woods 2026 - Continued after failure"
                )
                let recoveredEvent = try await database.read { db in
                    try #require(try OMERecord.Event.find(selectedEventID).fetchOne(db))
                }
                expectNoDifference(recoveredEvent.contactNumbers?.first?.title, "Event office")
                expectNoDifference(
                    recoveredEvent.locations?.first?.address,
                    "123 Festival Road, Denver, CO"
                )
                let recoveredStages = try await database.read { db in
                    try OMERecord.Stage
                        .where { $0.id.organizerID.eq(selectedEventID.organizerID) }
                        .where { $0.id.eventID.eq(selectedEventID.eventID) }
                        .fetchAll(db)
                }
                #expect(recoveredStages.contains { $0.name == "Meadow Stage" })
                #expect(operations.count(of: "clone") == 1)
                #expect(operations.count(of: "checkout") == 1)
                #expect(operations.count(of: "push") == 1)
                await remountedStore.dismount(timeout: .seconds(1))
                return
            }

            await opened.send(
                workspaceStoryProposalAction(
                    .proposalDraft(.createProposalButtonTapped)
                )
            )?.value

            let proposal = try #require(
                opened.state.content.destination?.eventViewer?
                    .authoring.content.content.eventWorkspace?
                    .changes.openProposal
            )
            guard case let .ready(.proposal(recordedProposal)) = opened.state.content.destination?.eventViewer?
                .authoring.content.phase,
                recordedProposal == proposal
            else {
                Issue.record("Creating the proposal must advance Workspace to its proposal line.")
                return
            }
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.content.content
                    .eventWorkspace?.workspaceStatus,
                .ready(.proposal(proposal))
            )
            let settledSummary = try await database.read { db in
                try SourceWorkspaceEditSummary.query(
                    workspace: workspace,
                    in: db,
                    referenceDatabase: resource.referenceDatabase
                )
            }
            #expect(settledSummary.totalCount == 0)
            try await workspaceStoryWaitUntil {
                opened.state.content.destination?.eventViewer?
                    .authoring.content.content.eventWorkspace?
                    .changes.summary.totalCount == 0
            }
            #expect(operations.count(of: "createBranch") == 1)
            #expect(operations.count(of: "checkout") == 1)
            #expect(operations.count(of: "stage") == 1)
            #expect(operations.count(of: "commit") == 1)
            #expect(operations.count(of: "formatPatch") == 1)
            #expect(operations.count(of: "push") == 1)

            // Exiting revokes the grant, but the settled workspace and proposal survive by design.
            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            #expect(opened.state.content.destination?.eventViewer?.authoring.grant == nil)
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.phase,
                .inactive(.eligible(eligibility))
            )
            guard case let .ready(.proposal(settledProposal)) = opened.state.content.destination?.eventViewer?
                .authoring.content.phase,
                settledProposal == proposal
            else {
                Issue.record("Grant loss must not discard the settled proposal workspace.")
                return
            }

            let openedRepositoriesBeforeRemount = operations.count(of: "open")
            await opened.dismount(timeout: .seconds(1))

            // A fresh application mount repeats the same route-owned transition. It must open and
            // validate the durable repository and proposal rather than cloning or reinstalling it.
            let remountedStore = TestStore(
                initialState: OpenMusicEventApplication.State(
                    storage: authenticationStorage
                ) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(
                    storage: authenticationStorage,
                    requestCenter: authorizationRequestCenter
                ) {
                    OpenMusicEventAppRoot()
                }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
            }
            await workspaceStoryOpenEvent(remountedStore, route: route, url: routeURL)
            if target == .settings {
                await remountedStore.send(
                    to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                    .enterAuthoringButtonTapped
                )?.value
            } else {
                try await workspaceStoryWaitUntil {
                    guard let authoring = remountedStore.state.content.destination?.eventViewer?.authoring,
                          case .active = authoring.phase,
                          case .ready(.proposal) = authoring.content.phase
                    else { return false }
                    return true
                }
            }

            let remountedAuthoring = try #require(
                remountedStore.state.content.destination?.eventViewer?.authoring
            )
            expectNoDifference(remountedAuthoring.grant?.role, .owner)
            expectNoDifference(
                remountedAuthoring.phase,
                .active(
                    AuthoringGrant(
                        principal: eligibility.principal,
                        role: eligibility.role,
                        workspaceID: remountedAuthoring.context.id
                    )
                )
            )
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
            let remountedEvent = try await database.read { db in
                try #require(try OMERecord.Event.find(selectedEventID).fetchOne(db))
            }
            expectNoDifference(remountedEvent.contactNumbers?.first?.title, "Event office")
            expectNoDifference(
                remountedEvent.locations?.first?.address,
                "123 Festival Road, Denver, CO"
            )
            let remountedStages = try await database.read { db in
                try OMERecord.Stage
                    .where { $0.id.organizerID.eq(selectedEventID.organizerID) }
                    .where { $0.id.eventID.eq(selectedEventID.eventID) }
                    .fetchAll(db)
            }
            #expect(remountedStages.contains { $0.name == "Meadow Stage" })

            // Revoking the selected account invalidates the one authoring phase. Settings can no
            // longer offer entry, the active grant disappears, and no second workspace path is
            // installed to preserve authoring.
            authenticationStorage.reset()
            try await workspaceStoryWaitUntil {
                remountedStore.state.content.destination?.eventViewer?.authoring.phase
                    == .inactive(.unavailable)
            }
            let revokedAuthoring = try #require(
                remountedStore.state.content.destination?.eventViewer?.authoring
            )
            expectNoDifference(revokedAuthoring.phase, .inactive(.unavailable))
            #expect(revokedAuthoring.grant == nil)
            expectNoDifference(
                revokedAuthoring.content.content.authoringAccess,
                .attendee
            )
            #expect(!revokedAuthoring.content.content.installedFeatures.contains(.workspace))
            await remountedStore.dismount(timeout: .seconds(1))
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
            $0.omeEventInstallation = .liveValue
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
            expectNoDifference(authoring.content.phase, .preparingSource)
            expectNoDifference(authoring.content.content.selectedFeature, .settings)
            #expect(authoring.content.content.eventSettings != nil)

            // Source preparation can finish without changing or replacing the restored grant.
            await preparation.continuePreparation()
            await opening?.value
            try await workspaceStoryWaitUntil {
                guard case .ready(.canonical) = store.content.destination?.eventViewer?.authoring.content.phase
                else { return false }
                return true
            }
            expectNoDifference(store.content.destination?.eventViewer?.authoring.grant, grant)
            expectNoDifference(operations.count(of: "clone"), 1)
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
            $0.omeEventInstallation = .liveValue
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
            await withExpectedIssue {
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
                    preparingWorkspace.workspaceStatus,
                    .activity(.preparingSource)
                )
                expectNoDifference(
                    preparingWorkspace.changes.summary.availability,
                    .workspaceNeedsPreparation
                )

                // Failure is presented by the same mounted Workspace; it does not revoke authoring.
                await preparationGate.failFirstAttempt()
                await entry?.value
            }
            let failedAuthoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            guard case .sourcePreparationFailed = failedAuthoring.content.phase else {
                Issue.record("The controlled first preparation must fail in Workspace.")
                return
            }
            #expect(failedAuthoring.grant != nil)
            #expect(failedAuthoring.content.source == nil)
            #expect(failedAuthoring.content.content.eventWorkspace != nil)
            #expect(failedAuthoring.content.content.installedFeatures.contains(.workspace))
            #expect(failedAuthoring.content.content.authoringAccess.canEditContent)
            guard case let .sourcePreparationFailed(failure) = failedAuthoring.content.phase else {
                Issue.record("The controlled first preparation must retain its failure details.")
                return
            }
            expectNoDifference(
                failedAuthoring.content.content.eventWorkspace?.workspaceStatus,
                .failed(operation: .sourcePreparation, failure: failure)
            )

            // Retry starts at EventWorkspace, crosses the app event bridge, and reaches the shared
            // Workspace state machine before executing the real source preparation implementation.
            await opened.send(
                workspaceStoryWorkspaceAction(.sourcePreparationRetryButtonTapped)
            )?.value
            let readyAuthoring = try #require(opened.state.content.destination?.eventViewer?.authoring)
            guard case .ready(.canonical) = readyAuthoring.content.phase else {
                Issue.record("Workspace retry must establish the canonical editing line.")
                return
            }
            #expect(readyAuthoring.content.source != nil)
            #expect(readyAuthoring.content.content.eventWorkspace != nil)
            #expect(readyAuthoring.content.content.installedFeatures.contains(.workspace))
            expectNoDifference(
                readyAuthoring.content.content.eventWorkspace?.workspaceStatus,
                readyAuthoring.content.phase.editingLine.map(WorkspaceStatus.ready)
            )
            expectNoDifference(operations.count(of: "clone"), 1)

            // Exiting authoring removes Workspace from navigation even though its settled state is
            // retained for durable reentry.
            await opened.send(
                to: \.content.destination!.eventViewer!.authoring.content.content.eventSettings!,
                .exitAuthoringButtonTapped
            )?.value
            let exited = try #require(opened.state.content.destination?.eventViewer?.authoring)
            #expect(exited.grant == nil)
            expectNoDifference(exited.content.content.authoringAccess, .attendee)
            #expect(!exited.content.content.installedFeatures.contains(.workspace))
            #expect(exited.content.content.eventWorkspace != nil)
            await opened.dismount(timeout: .seconds(1))
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
            $0.omeEventInstallation = .liveValue
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
                organizerID: organizerID,
                archive: git.archive
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
            expectNoDifference(authoring.content.phase, .inactive)
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
            await withExpectedIssue {
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
            expectNoDifference(
                opened.state.content.destination?.eventViewer?.authoring.content.phase,
                .inactive
            )
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
                expectNoDifference(
                    store.content.destination?.eventViewer?.authoring.content.phase,
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
    recorder: WorkspaceStorySourceControlRecorder,
    failsPush: Bool = false
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
        if failsPush {
            throw WorkspaceStoryPushFailure()
        }
        var request = request
        request.credentials = nil
        try await live.push(request)
    }
    return sourceControl
}

struct WorkspaceStoryProposalScenario: CustomStringConvertible, Sendable {
    var target: EventTarget
    var failsPush = false
    var signsIn = false

    var description: String {
        if failsPush { return "\(target)-push-failure" }
        if signsIn { return "\(target)-sign-in-success" }
        return "\(target)-success"
    }
}

private struct WorkspaceStoryPushFailure: Error {}

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
    ) async throws -> WorkspacePreparation<SourceWorkspaceResource> {
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
