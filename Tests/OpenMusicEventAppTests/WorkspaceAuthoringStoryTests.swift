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

@MainActor
@Suite(.serialized)
struct WorkspaceAuthoringStoryTests {
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
    func `canonical event installation resolves the database prepared in the same dependency update`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            @Dependency(\.eventRecords) var eventRecords

            let installedEventID = try await eventRecords.install(eventID)
            expectNoDifference(installedEventID, eventID)
        }
    }

    @Test
    func `foregrounding keeps the canonical event and local edits mounted`() async throws {
        struct UnexpectedRecordLoad: Error {}

        let database = try makeWorkspaceStoryDatabase()
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.uuid = .incrementing
            $0.eventRecords = EventRecordClient { _ in
                throw UnexpectedRecordLoad()
            }
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            @Dependency(\.eventRecords) var eventRecords
            let installedEventID = try await eventRecords.install(eventID)
            expectNoDifference(installedEventID, eventID)

            let store = Store(
                initialState: OpenMusicEventAppRoot.State(
                    selectedEventIDAtLaunch: eventID
                )
            ) {
                OpenMusicEventAppRoot()
            }
            try await workspaceStoryWaitUntil {
                store.destination?.eventViewer?.eventID == eventID
            }

            var edited = try await database.read { db in
                try #require(try Event.find(eventID).fetchOne(db))
            }
            edited.name = "Edited locally"
            let updatedEvent = edited
            try await database.write { db in
                try Event.upsert { updatedEvent }.execute(db)
            }

            let resume = try store.state.appDelegateEvent(.resumed)
            await resume?.value

            let saved = try await database.read {
                try Event.find(eventID).fetchOne($0)
            }
            expectNoDifference(saved, updatedEvent)
            try await workspaceStoryWaitUntil {
                store.destination?.eventViewer?.event?.name == "Edited locally"
            }
            #expect(store.destination?.eventViewer?.canonicalWorkspace == nil)
        }
    }
    #if os(macOS)
    @Test(.tcaExhaustivity(.off))
    func `relaunching an owner workspace keeps canonical event settings available`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(DID("did:web:example.com"))
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID
        let authenticationStorage = OpenMusicEventOAuth.storage

        try await withWorkspaceStoryOAuthSession(actorID: organizerID) {
        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.canonicalWorkspaceStorage = .fileBacked(
                rootURL: FileManager.default.temporaryDirectory
                    .appending(path: "OME-WorkspaceRelaunch-\(UUID())", directoryHint: .isDirectory)
            )
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.uuid = .incrementing
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            @Dependency(\.eventRecords) var eventRecords
            let installedEventID = try await eventRecords.install(eventID)
            expectNoDifference(installedEventID, eventID)

            let route = AppRoute.event(eventID, .settings)
            let routeURL = try #require(URL(string: "ome://saved-event\(route.path)"))
            for visit in 1...2 {
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
                let viewer = try #require(store.state.content.destination?.eventViewer)
                expectNoDifference(viewer.eventID, eventID)
                expectNoDifference(viewer.selectedFeature, .settings)
                #expect(viewer.eventSettings != nil)
                if visit == 1 {
                    #expect(viewer.canonicalWorkspace == nil)
                    #expect(!viewer.showsAuthoringControls)
                } else {
                    #expect(viewer.canonicalWorkspace != nil)
                }

                if visit == 1 {
                    await store.send(
                        to: \.content.destination!.eventViewer!.eventSettings!,
                        .enterAuthoringButtonTapped
                    )?.value
                    try await workspaceStoryWaitUntil {
                        store.state.content.destination?.eventViewer?.showsAuthoringControls == true
                    }
                } else {
                    try await workspaceStoryWaitUntil {
                        store.state.content.destination?.eventViewer?.showsAuthoringControls == true
                    }
                }
                await store.dismount()
            }
        }
        }
    }
    #endif

    #if os(macOS)
    @Test(.tcaExhaustivity(.off))
    func `failed canonical event installation retries through the event entry`() async throws {
        struct FirstLoadFailure: Error {}

        let database = try makeWorkspaceStoryDatabase()
        let event = try Event(
            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Retry Festival",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let attempts = TestMutex(0)

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.continuousClock = ContinuousClock()
            $0.eventRecords = EventRecordClient { requestedID in
                #expect(requestedID == event.id)
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 {
                    throw FirstLoadFailure()
                }
                return EventRecordGraph(event: event)
            }
        } operation: {
            let store = Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
            try await expectReportedIssue(containing: "FirstLoadFailure") {
                await store.send(.openRoute(.event(event.id, .settings)))?.value
                try await workspaceStoryWaitUntil {
                    store.eventEntry?.phase == .failed("This event could not be loaded.")
                }
            }
            #expect(store.destination?.eventViewer == nil)
            let beforeRetry = try await database.read {
                try Event.find(event.id).fetchOne($0)
            }
            #expect(beforeRetry == nil)

            await store.send(.eventEntryRetryTapped)?.value
            try await workspaceStoryWaitUntil {
                store.destination?.eventViewer?.eventID == event.id
            }
            expectNoDifference(attempts.withLock { $0 }, 2)
            #expect(store.eventEntry == nil)
            #expect(store.destination?.eventViewer?.eventSettings != nil)
            let installed = try await database.read {
                try Event.find(event.id).fetchOne($0)
            }
            expectNoDifference(installed, event)
        }
    }
    #endif

    @Test
    func `owner workspace editing resets canonical event changes when discarded`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID
        let ownerID = try #require(DID("did:web:example.com"))

        try await withWorkspaceStoryOAuthSession(actorID: ownerID) {
            try await withDependencies {
                $0.context = .test
                OME.prepareDependencies(&$0, database: database)
                $0.defaultEventID = eventID
                $0.canonicalWorkspaceStorage = .fileBacked(
                    rootURL: FileManager.default.temporaryDirectory
                        .appending(path: "OME-WorkspaceStory-\(UUID())", directoryHint: .isDirectory)
                )
                $0.uuid = .incrementing
                $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            } operation: {
                try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
                let store = Store(initialState: EventDetail.State(eventID: eventID)) {
                    EventDetail()
                }
                let settings = try #require(store.spawn(\.eventSettings))

                await settings.send(.enterAuthoringButtonTapped)?.value
                try await workspaceStoryWaitUntil { store.showsAuthoringControls }
                #expect(store.canonicalWorkspace != nil)

                var edited = try await database.read { db in
                    try #require(try Event.find(eventID).fetchOne(db))
                }
                edited.name = "Wicked Woods, locally edited"
                let updatedEvent = edited
                try await database.write { db in
                    try Event.upsert { updatedEvent }.execute(db)
                }

                await settings.send(.exitAuthoringButtonTapped)?.value
                try await workspaceStoryWaitUntil { settings.destination != nil }
                await settings.send(
                    .destination(.exitAuthoringConfirmation(.exitAndDeleteButtonTapped))
                )?.value
                try await workspaceStoryWaitUntil { store.workspaceSession == nil }

                let saved = try await database.read {
                    try Event.find(eventID).fetchOne($0)
                }
                #expect(saved?.name != updatedEvent.name)
                #expect(store.eventID == eventID)
                #expect(store.canonicalWorkspace == nil)
                #expect(!store.showsAuthoringControls)
            }
        }
    }
    #if os(macOS)
    @Test(.tcaExhaustivity(.off))
    func `signed-out app cannot enter local editing through canonical event settings`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID
        let authenticationStorage = workspaceStorySignedOutOAuthStorage()

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            @Dependency(\.eventRecords) var eventRecords
            let installedEventID = try await eventRecords.install(eventID)
            expectNoDifference(installedEventID, eventID)

            let route = AppRoute.event(eventID, .settings)
            let routeURL = try #require(URL(string: "ome://signed-out-editing\(route.path)"))
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

            let viewer = try #require(opened.state.content.destination?.eventViewer)
            #expect(viewer.workspaceSession == nil)
            #expect(viewer.canonicalWorkspace == nil)
            #expect(!viewer.showsAuthoringControls)

            try await expectReportedIssue(containing: "ownerAccountRequired") {
                await opened.send(
                    to: \.content.destination!.eventViewer!.eventSettings!,
                    .enterAuthoringButtonTapped
                )?.value
            }
            #expect(opened.state.content.destination?.eventViewer?.showsAuthoringControls == false)
            #expect(opened.state.content.destination?.eventViewer?.workspaceSession == nil)
            #expect(opened.state.content.destination?.eventViewer?.canonicalWorkspace == nil)
            await opened.dismount()
        }
    }
    #endif

    @Test
    func `authenticated attendee cannot edit another owner's event`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID
        let operations = WorkspaceStorySourceControlRecorder()

        try await withWorkspaceStoryOAuthSession(actorID: organizerID) {
            try await withDependencies {
                $0.context = .test
                OME.prepareDependencies(&$0, database: database)
                $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
                $0.uuid = .incrementing
                $0.continuousClock = ContinuousClock()
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
                try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
                @Dependency(\.eventRecords) var eventRecords
                let installedEventID = try await eventRecords.install(eventID)
                expectNoDifference(installedEventID, eventID)
                #expect(operations.snapshot.isEmpty)

                let route = AppRoute.event(eventID, .settings)
                let routeURL = try #require(URL(string: "ome://attendee-editing\(route.path)"))
                let store = TestStore(
                    initialState: OpenMusicEventApplication.State(
                        storage: OpenMusicEventOAuth.storage
                    ) {
                        OpenMusicEventAppRoot.State()
                    }
                ) {
                    OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                        OpenMusicEventAppRoot()
                    }
                    .presentAuthorizationFailures()
                    .deliverAuthoringAuthorizationChanges()
                }
                await workspaceStoryOpenEvent(store, route: route, url: routeURL)
                #expect(store.state.content.destination?.eventViewer?.workspaceSession == nil)
                #expect(store.state.content.destination?.eventViewer?.canonicalWorkspace == nil)
                #expect(store.state.content.destination?.eventViewer?.showsAuthoringControls == false)

                try await expectReportedIssue(containing: "ownerAccountRequired") {
                    await store.send(
                        to: \.content.destination!.eventViewer!.eventSettings!,
                        .enterAuthoringButtonTapped
                    )?.value
                }
                #expect(store.state.content.destination?.eventViewer?.showsAuthoringControls == false)
                #expect(store.state.content.destination?.eventViewer?.workspaceSession == nil)
                #expect(store.state.content.destination?.eventViewer?.canonicalWorkspace == nil)
                #expect(operations.snapshot.isEmpty)
                await store.dismount()
            }
        }
    }
}

private func workspaceStorySignedOutOAuthStorage() -> OAuthSessionStorage {
    OAuthSessionStorage(
        sessionStore: Shared(value: OAuth.SessionStore()),
        authFailureMessage: Shared(value: nil),
        selectedSessionID: Shared(value: nil)
    )
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
    let observations = TestMutex<[WorkspaceStoryDependencyPropagationObservation]>([])
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
        .ifLet(\.child) {
            Child(recorder: recorder)
        }
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
}

private struct WorkspaceStoryUnexpectedSourceControlOperation: Error {}

private final class WorkspaceStorySourceControlRecorder: Sendable {
    private let failsNextCheckout = TestMutex(false)
    private let operations = TestMutex<[String]>([])

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
