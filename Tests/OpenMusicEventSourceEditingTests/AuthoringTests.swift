import ComposableArchitecture2
import CustomDump
import Dependencies
import ErrorHandling
import Foundation
import GRDB
import IssueReporting
import OpenMusicEventSourceEditing
import Sharing
import SourceControlClient
import Synchronization
import Testing

@Suite
struct AuthoringTests {
    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `entering authoring does not wait for source preparation`() async throws {
        let database = try DatabaseQueue()
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "instant-authoring"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let preparationGate = AuthoringPreparationGate()

        let store: TestStoreActor<Authoring<WorkspaceProbe>> = await withDependencies {
            $0[AuthoringPolicyClient.self] = .authoring
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { workspaceID in
                    #expect(workspaceID == workspace.id)
                    return workspace
                },
                prepareSource: { workspaceID in
                    await preparationGate.prepare(workspaceID)
                }
            )
        } operation: {
            await TestStoreActor(
                initialState: Authoring<WorkspaceProbe>.State(workspace: workspace) {
                    WorkspaceProbe.State()
                }
            ) {
                Authoring { WorkspaceProbe() }
            }
        }

        let entry = await store.send(.enterButtonTapped)
        let sourcePreparation = await store.receive(\.authoringEntryPrepared) {
            $0.grant = AuthoringGrant(
                capabilities: [.editContent],
                workspace: workspace
            )
        }
        let preparationRequests = await preparationGate.waitForPreparationToStart()

        expectNoDifference(preparationRequests, [workspace.id])
        let access = await store[dynamicMember: \.access]
        expectNoDifference(
            access,
            .authoring([.editContent])
        )

        await preparationGate.finish()
        await entry?.value
        await sourcePreparation?.value
        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `entering authoring changes only the selected workspace context`() async throws {
        let attendeeDatabaseA = try DatabaseQueue()
        let authoringDatabaseA = try DatabaseQueue()
        try setMarker("A attendee", in: attendeeDatabaseA)
        try setMarker("A authoring", in: authoringDatabaseA)
        let workspaceA = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-a"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: attendeeDatabaseA)
        )
        let preparedWorkspaceA = WorkspaceContext(
            id: workspaceA.id,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: authoringDatabaseA)
        )
        let workspaceB = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-b"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let authorizationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])

        let stores: (
            TestStoreActor<Authoring<WorkspaceProbe>>,
            TestStoreActor<Authoring<WorkspaceProbe>>
        ) = await withDependencies {
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                authorizationRequests.withLock { $0.append(workspaceID) }
                return [.editContent]
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { workspaceID in
                    switch workspaceID {
                    case workspaceA.id:
                        return preparedWorkspaceA
                    case workspaceB.id:
                        return workspaceB
                    default:
                        throw TestFailure.unexpectedWorkspace
                    }
                },
                prepareSource: { workspaceID in
                    preparationRequests.withLock { $0.append(workspaceID) }
                }
            )
        } operation: {
            (
                await TestStoreActor(
                    initialState: Authoring<WorkspaceProbe>.State(workspace: workspaceA) {
                        WorkspaceProbe.State()
                    }
                ) {
                    Authoring { WorkspaceProbe() }
                },
                await TestStoreActor(
                    initialState: Authoring<WorkspaceProbe>.State(workspace: workspaceB) {
                        WorkspaceProbe.State()
                    }
                ) {
                    Authoring { WorkspaceProbe() }
                }
            )
        }
        let (storeA, storeB) = stores

        // Two downloaded workspaces begin in attendee mode, independently.
        let initialAccessA = await storeA[dynamicMember: \.access]
        let initialAccessB = await storeB[dynamicMember: \.access]
        let initialContentAccessA = await storeA[dynamicMember: \.content.access]
        let initialContentAccessB = await storeB[dynamicMember: \.content.access]
        expectNoDifference(initialAccessA, .attendee)
        expectNoDifference(initialAccessB, .attendee)
        expectNoDifference(initialContentAccessA, .attendee)
        expectNoDifference(initialContentAccessB, .attendee)

        // A child can request entry, but only its workspace wrapper can grant it.
        let entry = await storeA.send(.content(.requestAuthoringButtonTapped))
        let sourcePreparation = await storeA.receive(\.authoringEntryPrepared) {
            $0.grant = AuthoringGrant(
                capabilities: [.editContent],
                workspace: preparedWorkspaceA
            )
        }
        await entry?.value
        await sourcePreparation?.value

        // The shared authoring dependency updates workspace A's content only.
        let authoringContentAccessA = await storeA[dynamicMember: \.content.access]
        let authoringAccessB = await storeB[dynamicMember: \.access]
        let authoringContentAccessB = await storeB[dynamicMember: \.content.access]
        expectNoDifference(authoringContentAccessA, .authoring([.editContent]))
        expectNoDifference(authoringAccessB, .attendee)
        expectNoDifference(authoringContentAccessB, .attendee)
        expectNoDifference(authorizationRequests.withLock { $0 }, [workspaceA.id])
        expectNoDifference(preparationRequests.withLock { $0 }, [workspaceA.id])

        // Each wrapped feature reads its own workspace and authoring dependency context.
        await storeA.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = true
            $0.content.observedDatabaseMarker = "A authoring"
            $0.content.observedWorkspaceID = workspaceA.id
        }
        await storeB.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = false
            $0.content.observedWorkspaceID = workspaceB.id
        }

        // Exiting switches the same child back to its attendee database context.
        await storeA.send(.exitButtonTapped) {
            $0.grant = nil
        }
        await storeA.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = false
            $0.content.observedDatabaseMarker = "A attendee"
        }

        await storeA.dismount()
        await storeB.dismount()
    }

    private func setMarker(
        _ value: String,
        in database: any DatabaseWriter
    ) throws {
        try database.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES (?)", arguments: [value])
        }
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `authorization failure reports an ephemeral issue and remains attendee`() async throws {
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-denied"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let store: TestStoreActor<AuthoringErrorHost> = await withDependencies {
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { _ in
                throw TestFailure.authorizationDenied
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { _ in workspace },
                prepareSource: { workspaceID in
                    preparationRequests.withLock { $0.append(workspaceID) }
                }
            )
        } operation: {
            await TestStoreActor(
                initialState: AuthoringErrorHost.State(workspace: workspace)
            ) {
                AuthoringErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.authoring, .enterButtonTapped)?.value
        }
        await store.expect {
            $0.reportedErrorDebugDescription = String(
                describing: TestFailure.authorizationDenied
            )
            $0.reportedErrorMessage = "Unable to enter authoring."
            $0.reportedErrorOperation = ErrorOperation(
                rawValue: "authoring.entry.authorization"
            )
        }

        let deniedAccess = await store[dynamicMember: \.authoring.state.access]
        let deniedContentAccess = await store[dynamicMember: \.authoring.state.content.access]
        expectNoDifference(deniedAccess, .attendee)
        expectNoDifference(deniedContentAccess, .attendee)
        expectNoDifference(preparationRequests.withLock { $0 }, [])

        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `workspace opening failure reports an ephemeral issue and remains attendee`() async throws {
        let failure = SourceControlError.remoteOperationFailed(
            SourceControlRemoteFailure(
                kind: .timedOut,
                message: "SSH could not read data: Timed out waiting on socket"
            )
        )
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-preparation-failed"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let store: TestStoreActor<AuthoringErrorHost> = await withDependencies {
            $0[AuthoringPolicyClient.self] = .authoring
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { _ in throw failure },
                prepareSource: { _ in }
            )
        } operation: {
            await TestStoreActor(
                initialState: AuthoringErrorHost.State(workspace: workspace)
            ) {
                AuthoringErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.authoring, .enterButtonTapped)?.value
        }
        await store.expect {
            $0.reportedErrorMessage = "Unable to enter authoring."
            $0.reportedErrorDebugDescription = String(describing: failure)
            $0.reportedErrorOperation = ErrorOperation(
                rawValue: "authoring.entry.preparation"
            )
        }

        let deniedAccess = await store[dynamicMember: \.authoring.state.access]
        let deniedContentAccess = await store[dynamicMember: \.authoring.state.content.access]
        expectNoDifference(deniedAccess, .attendee)
        expectNoDifference(deniedContentAccess, .attendee)

        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `source preparation failure reports an ephemeral issue and keeps authoring`() async throws {
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-source-preparation-failed"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let store: TestStoreActor<AuthoringErrorHost> = await withDependencies {
            $0[AuthoringPolicyClient.self] = .authoring
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { _ in workspace },
                prepareSource: { _ in throw TestFailure.preparationFailed }
            )
        } operation: {
            await TestStoreActor(
                initialState: AuthoringErrorHost.State(workspace: workspace)
            ) {
                AuthoringErrorHost()
            }
        }

        await withIssueReporters([]) {
            let entry = await store.send(to: \.authoring, .enterButtonTapped)
            let sourcePreparation = await store.receive(
                from: \.authoring,
                \.authoringEntryPrepared
            ) {
                $0.authoring.grant = AuthoringGrant(
                    capabilities: [.editContent],
                    workspace: workspace
                )
            }
            await entry?.value
            await sourcePreparation?.value
            await store.expect {
                $0.reportedErrorMessage =
                    "Editing is available, but the source repository is not ready."
                $0.reportedErrorOperation = ErrorOperation(
                    rawValue: "authoring.source-preparation"
                )
            }
        }

        let access = await store[dynamicMember: \.authoring.state.access]
        expectNoDifference(access, .authoring([.editContent]))

        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `one grant carries access and database context across mounts of one workspace`() async throws {
        let attendeeDatabase = try DatabaseQueue()
        let authoringDatabase = try DatabaseQueue()
        try setMarker("attendee", in: attendeeDatabase)
        try setMarker("authoring", in: authoringDatabase)
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "shared-workspace")
        let preparedWorkspace = WorkspaceContext(
            id: workspaceID,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: authoringDatabase)
        )
        let grant = Shared<AuthoringGrant?>(value: nil)

        let stores: (
            TestStoreActor<Authoring<WorkspaceProbe>>,
            TestStoreActor<Authoring<WorkspaceProbe>>
        ) = await withDependencies {
            $0.defaultDatabase = attendeeDatabase
            $0[AuthoringPolicyClient.self] = .authoring
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { id in
                    #expect(id == workspaceID)
                    return preparedWorkspace
                },
                prepareSource: { _ in }
            )
        } operation: {
            (
                await TestStoreActor(
                    initialState: Authoring<WorkspaceProbe>.State(
                        workspaceID: workspaceID,
                        grant: grant
                    ) {
                        WorkspaceProbe.State()
                    }
                ) {
                    Authoring { WorkspaceProbe() }
                },
                await TestStoreActor(
                    initialState: Authoring<WorkspaceProbe>.State(
                        workspaceID: workspaceID,
                        grant: grant
                    ) {
                        WorkspaceProbe.State()
                    }
                ) {
                    Authoring { WorkspaceProbe() }
                }
            )
        }
        let (storeA, storeB) = stores

        let entry = await storeA.send(.enterButtonTapped)
        let sourcePreparation = await storeA.receive(\.authoringEntryPrepared) {
            $0.grant = AuthoringGrant(
                capabilities: [.editContent],
                workspace: preparedWorkspace
            )
        }
        await entry?.value
        await sourcePreparation?.value

        let accessB = await storeB[dynamicMember: \.access]
        expectNoDifference(accessB, .authoring([.editContent]))
        await TestExhaustivity.$current.withValue(.off) {
            await storeB.send(.content(.inspectButtonTapped)) {
                $0.content.observedCanAuthor = true
                $0.content.observedDatabaseMarker = "authoring"
                $0.content.observedWorkspaceID = workspaceID
            }
        }

        await storeB.send(.exitButtonTapped) {
            $0.grant = nil
        }
        let accessA = await storeA[dynamicMember: \.access]
        expectNoDifference(accessA, .attendee)
        await TestExhaustivity.$current.withValue(.off) {
            await storeA.send(.content(.inspectButtonTapped)) {
                $0.content.observedCanAuthor = false
                $0.content.observedDatabaseMarker = "attendee"
                $0.content.observedWorkspaceID = workspaceID
            }
        }

        await storeA.dismount()
        await storeB.dismount()
    }
}

private actor AuthoringPreparationGate {
    private var isFinished = false
    private var workspaceIDs: [EditingWorkspaceRecord.ID] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<[EditingWorkspaceRecord.ID], Never>] = []

    func finish() {
        isFinished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func prepare(_ workspaceID: EditingWorkspaceRecord.ID) async {
        workspaceIDs.append(workspaceID)
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume(returning: workspaceIDs) }
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    func waitForPreparationToStart() async -> [EditingWorkspaceRecord.ID] {
        if !workspaceIDs.isEmpty {
            return workspaceIDs
        }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

@Feature
struct AuthoringErrorHost {
    struct State {
        init(workspace: WorkspaceContext) {
            self.authoring = Spawn(
                Authoring<WorkspaceProbe>.State(workspace: workspace) {
                    WorkspaceProbe.State()
                }
            )
        }

        var authoring: Spawn<Authoring<WorkspaceProbe>>
        var reportedErrorDebugDescription: String?
        var reportedErrorMessage: String?
        var reportedErrorOperation: ErrorOperation?
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.authoring) {
                Authoring { WorkspaceProbe() }
            }
            .onEvent(ErrorReported.self) { error, state in
                state.reportedErrorDebugDescription = error.debugDescription
                state.reportedErrorMessage = error.message.fallback
                state.reportedErrorOperation = error.operation
            }
    }
}

@Feature
struct WorkspaceProbe {
    struct State {
        init() {
            @Dependency(\.authoringContext) var authoringContext
            self._grant = authoringContext?.$grant ?? SharedReader(value: nil)
        }

        @SharedReader var grant: AuthoringGrant?
        var observedCanAuthor: Bool?
        var observedDatabaseMarker: String?
        var observedWorkspaceID: EditingWorkspaceRecord.ID?

        var access: AuthoringAccess {
            grant?.access ?? .attendee
        }
    }

    enum Action {
        case inspectButtonTapped
        case requestAuthoringButtonTapped
    }

    @Dependency(\.authoringContext) var authoringContext
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.workspaceContext) var workspaceContext

    var body: some Feature {
        Update { state, action in
            switch action {
            case .inspectButtonTapped:
                state.observedCanAuthor = authoringContext?.canEditContent
                state.observedDatabaseMarker = try? database.read { db in
                    try String.fetchOne(db, sql: "SELECT value FROM marker")
                }
                state.observedWorkspaceID = workspaceContext?.id

            case .requestAuthoringButtonTapped:
                store.addTask {
                    try store.post(key: AuthoringRequested.self, value: ())
                }
            }
        }
    }
}

enum TestFailure: Error, LocalizedError {
    case authorizationDenied
    case preparationFailed
    case unexpectedWorkspace

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Authorization denied"
        case .preparationFailed:
            "Preparation failed"
        case .unexpectedWorkspace:
            "Unexpected workspace"
        }
    }
}
