import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
import HTTPClient
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SQLiteData
import Synchronization
import Testing
import XRPCClient

@testable import OpenMusicEventApp

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@MainActor
@Suite(.serialized)
struct WorkspaceAuthoringStoryTests {
    @Test
    func `authorized entry prepares the organization workspace once and durable reentry only validates it`() async throws {
        let database = try makeWorkspaceStoryDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let selectedEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "wicked-woods-ome-2026"
        )
        let olderEventID = workspaceStoryEventID(
            organizerID: organizerID,
            localID: "wicked-woods-ome-2025"
        )
        let unrelatedEventID = try await insertUnrelatedWorkspaceStoryEvent(into: database)
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(
                path: "OME-WorkspaceAuthoringStory-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }

        let revision = CommitID(rawValue: "0123456789012345678901234567890123456789")
        let operations = WorkspaceStorySourceControlRecorder()
        let cloneGate = AsyncStream<Void>.makeStream()
        defer { cloneGate.continuation.finish() }

        try await withWorkspaceStoryOAuthSession(actorID: organizerID) {
            try await withDependencies {
                $0.context = .test
                OME.prepareDependencies(&$0, database: database)
                $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
                $0.uuid = .incrementing
                $0.sourceWorkspaceStorage = .fileBacked(rootURL: storageRoot)
                $0.tangledRepositoryMembership = TangledRepositoryMembershipClient {
                    _, expectedOwnerID, actorID in
                    expectedOwnerID == organizerID && actorID == organizerID
                }
                $0[Atmosphere.Account.Client.self] = workspaceStoryAccountClient(
                    organizerID: organizerID
                )
                $0[XRPC.Client.self] = .liveValue
                $0.httpClient = workspaceStoryTangledRecordsHTTPClient()
                $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                    .sshAgent(hostKeyPolicy: .acceptForTesting)
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
                sourceControl.clone = { request in
                    operations.record("clone")
                    if operations.count(of: "clone") == 1 {
                        for await _ in cloneGate.stream { break }
                        throw WorkspaceStoryCloneFailure()
                    }
                    try FileManager.default.createDirectory(
                        at: request.destinationURL.appending(path: ".git", directoryHint: .isDirectory),
                        withIntermediateDirectories: true
                    )
                    try writeWorkspaceStorySource(
                        organizerID: organizerID,
                        to: request.destinationURL
                    )
                    return Repository(url: request.destinationURL)
                }
                sourceControl.open = { url in
                    operations.record("open")
                    return Repository(url: url)
                }
                sourceControl.fetch = { _ in operations.record("fetch") }
                sourceControl.checkout = { _ in operations.record("checkout") }
                sourceControl.resolveRevision = { request in
                    operations.record("resolve:\(request.ref.rawValue)")
                    return revision
                }
                $0.sourceControl = sourceControl
            } operation: {
                // Browsing uses the temporary source artifact path and installs only the selected
                // event into the real writable database. Git is still untouched.
                let installedEventID = try await OMEEventInstallationClient.liveValue
                    .ensureInstalled(OMERecord.Event.reference(id: selectedEventID).uri)
                expectNoDifference(installedEventID, selectedEventID)
                let browsedEventNames = try await workspaceStoryEventNames(in: database)
                expectNoDifference(browsedEventNames, ["Other Festival", "Wicked Woods 2026"])
                #expect(operations.snapshot.isEmpty)

                var firstStore: StoreOf<OpenMusicEventAppRoot>? = Store(
                    initialState: OpenMusicEventAppRoot.State(
                        selectedEventIDAtLaunch: selectedEventID
                    )
                ) {
                    OpenMusicEventAppRoot()
                }

                try await workspaceStoryWaitUntil {
                    firstStore?.eventViewer?.content.authoring.canEnter == true
                }
                #expect(operations.snapshot.isEmpty)

                // The real AppRoot -> OAuth -> Authoring -> Workspace action path owns entry.
                let entry = firstStore?.send(
                    .destination(
                        .eventViewer(
                            .content(.authoring(.enterButtonTapped))
                        )
                    )
                )
                try await workspaceStoryWaitUntil {
                    guard case .preparingSource = firstStore?
                        .eventViewer?
                        .content
                        .authoring
                        .content
                        .phase
                    else { return false }
                    return operations.count(of: "clone") == 1
                }

                // EventSettingsView and WorkspacePublicationStatusView both render a ProgressView
                // directly from this phase, so the control cannot simply disappear during entry.
                let enteringAuthoring = try #require(
                    firstStore?.eventViewer?.content.authoring
                )
                let enteringGrant = try #require(enteringAuthoring.grant)
                expectNoDifference(enteringAuthoring.phase, .entering)
                expectNoDifference(enteringGrant.principal, AuthoringPrincipal(actorID: organizerID))
                expectNoDifference(enteringGrant.role, .owner)

                cloneGate.continuation.yield(())
                await entry?.value
                try await workspaceStoryWaitUntil {
                    guard case .sourcePreparationFailed = firstStore?
                        .eventViewer?
                        .content
                        .authoring
                        .content
                        .phase
                    else { return false }
                    return firstStore?.eventViewer?.content.authoring.grant != nil
                }
                expectNoDifference(operations.count(of: "clone"), 1)

                // The mounted Workspace owns retry. Authoring keeps the valid grant, and retrying
                // repeats only source preparation rather than authentication or authorization.
                let retry = firstStore?.send(
                    .destination(
                        .eventViewer(
                            .content(
                                .authoring(
                                    .content(.sourcePreparationRetryButtonTapped)
                                )
                            )
                        )
                    )
                )
                await retry?.value
                try await workspaceStoryWaitUntil {
                    guard case .ready(.canonical) = firstStore?
                        .eventViewer?
                        .content
                        .authoring
                        .content
                        .phase
                    else { return false }
                    return firstStore?.eventViewer?.content.authoring.content.source != nil
                }

                let workspace = try #require(firstStore?.eventViewer?.content.authoring.context)
                let firstResource = try #require(
                    firstStore?.eventViewer?.content.authoring.content.source
                )
                expectNoDifference(workspace.organizerID, organizerID)
                let preparedEventNames = try await workspaceStoryEventNames(in: database)
                expectNoDifference(
                    preparedEventNames,
                    ["Other Festival", "Wicked Woods 2025", "Wicked Woods 2026"]
                )
                expectNoDifference(operations.count(of: "clone"), 2)
                expectNoDifference(operations.count(prefix: "resolve:"), 1)

                let cleanSummary = try await firstResource.database.read { db in
                    try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
                }
                expectNoDifference(cleanSummary.availability, .available)
                expectNoDifference(cleanSummary.totalCount, 0)

                // A real application write is immediately visible against the attached baseline.
                try await database.write { db in
                    try OMERecord.Event.find(selectedEventID)
                        .update { $0.name = "Wicked Woods 2026 - Local Edit" }
                        .execute(db)
                }
                let editedSummary = try await firstResource.database.read { db in
                    try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
                }
                #expect(editedSummary.totalCount > 0)

                // Grant loss does not destroy settled workspace state within the mounted feature.
                let exit = firstStore?.send(
                    .destination(
                        .eventViewer(
                            .content(.authoring(.exitButtonTapped))
                        )
                    )
                )
                await exit?.value
                try await workspaceStoryWaitUntil {
                    firstStore?.eventViewer?.content.authoring.grant == nil
                        && firstStore?.eventViewer?.content.authoring.canEnter == true
                }
                guard case .ready(.canonical) = firstStore?
                    .eventViewer?
                    .content
                    .authoring
                    .content
                    .phase
                else {
                    Issue.record("Settled workspace state must outlive authoring grant loss.")
                    return
                }

                let sameMountReentry = firstStore?.send(
                    .destination(
                        .eventViewer(
                            .content(.authoring(.enterButtonTapped))
                        )
                    )
                )
                await sameMountReentry?.value
                try await workspaceStoryWaitUntil {
                    firstStore?.eventViewer?.content.authoring.grant != nil
                }
                expectNoDifference(operations.count(of: "clone"), 2)
                expectNoDifference(operations.count(prefix: "resolve:"), 1)

                let secondExit = firstStore?.send(
                    .destination(
                        .eventViewer(
                            .content(.authoring(.exitButtonTapped))
                        )
                    )
                )
                await secondExit?.value
                try await workspaceStoryWaitUntil {
                    firstStore?.eventViewer?.content.authoring.grant == nil
                }
                firstStore = nil
                await Task.yield()

                // A new application mount has inactive Workspace state, so it opens and validates
                // the durable repository/reference pair. It neither clones nor reinstalls source.
                let remountedStore = Store(
                    initialState: OpenMusicEventAppRoot.State(
                        selectedEventIDAtLaunch: selectedEventID
                    )
                ) {
                    OpenMusicEventAppRoot()
                }
                try await workspaceStoryWaitUntil {
                    remountedStore.eventViewer?.content.authoring.canEnter == true
                }
                let durableReentry = remountedStore.send(
                    .destination(
                        .eventViewer(
                            .content(.authoring(.enterButtonTapped))
                        )
                    )
                )
                await durableReentry?.value
                try await workspaceStoryWaitUntil {
                    guard case .ready(.canonical) = remountedStore
                        .eventViewer?
                        .content
                        .authoring
                        .content
                        .phase
                    else { return false }
                    return remountedStore.eventViewer?.content.authoring.content.source != nil
                }

                expectNoDifference(operations.count(of: "clone"), 2)
                expectNoDifference(operations.count(prefix: "resolve:"), 2)
                let remountedEventNames = try await workspaceStoryEventNames(in: database)
                expectNoDifference(
                    remountedEventNames,
                    [
                        "Other Festival",
                        "Wicked Woods 2025",
                        "Wicked Woods 2026 - Local Edit",
                    ]
                )

                let remountedResource = try #require(
                    remountedStore.eventViewer?.content.authoring.content.source
                )
                let remountedSummary = try await remountedResource.database.read { db in
                    try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
                }
                #expect(remountedSummary.totalCount > 0)

                // Keep the exact identities visible in this application story.
                let exactEventsRemain = try await database.read { db in
                    try OMERecord.Event.find(olderEventID).fetchOne(db) != nil
                        && OMERecord.Event.find(unrelatedEventID).fetchOne(db) != nil
                }
                #expect(exactEventsRemain)
            }
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
            localID: "wicked-woods-ome-2026"
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
                    initialState: OpenMusicEventAppRoot.State(
                        selectedEventIDAtLaunch: selectedEventID
                    )
                ) {
                    OpenMusicEventAppRoot()
                }
                try await workspaceStoryWaitUntil {
                    store.eventViewer?.content.authoring.admission == .unavailable
                }

                expectNoDifference(store.eventViewer?.content.authoring.canEnter, false)
                #expect(store.eventViewer?.content.authoring.grant == nil)
                expectNoDifference(
                    store.eventViewer?.content.authoring.content.phase,
                    .inactive
                )
                #expect(operations.snapshot.isEmpty)
            }
        }
    }
}

private struct WorkspaceStoryCloneFailure: Error {}
private struct WorkspaceStoryUnexpectedSourceControlOperation: Error {}

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
                    localID: "wicked-woods-ome-2025"
                ),
                directoryName: "2025",
                name: "Wicked Woods 2025",
                timeZone: timeZone
            ),
            workspaceStorySourceEvent(
                id: workspaceStoryEventID(
                    organizerID: organizerID,
                    localID: "wicked-woods-ome-2026"
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
                    "name": "wicked-woods-ome",
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
