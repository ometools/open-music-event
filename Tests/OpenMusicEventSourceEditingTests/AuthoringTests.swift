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

@Suite(.tcaExhaustivity(.off))
struct AuthoringTests {
    @Test @MainActor
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `persisted activation restores authoring before source preparation`() async throws {
        let database = try DatabaseQueue()
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "restored-workspace")
        let workspace = EditingWorkspace(
            id: workspaceID,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let activation = WorkspaceAuthoringActivationRecord(
            id: workspaceID,
            principal: .local,
            role: .owner,
            activatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let preparationGate = AuthoringPreparationGate()
        let admissionRequests = Mutex<[EditingWorkspaceRecord.ID]>([])

        let store = withDependencies {
            $0.defaultDatabase = database
            $0[WorkspaceAuthoringActivationClient.self] = WorkspaceAuthoringActivationClient(
                current: { requestedWorkspaceID in
                    #expect(requestedWorkspaceID == workspaceID)
                    return activation
                },
                activate: { _, _, _ in },
                deactivate: { _ in }
            )
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { requestedWorkspaceID in
                admissionRequests.withLock { $0.append(requestedWorkspaceID) }
                return .denied
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { requestedWorkspaceID in
                    #expect(requestedWorkspaceID == workspaceID)
                    return workspace
                },
                prepareSource: { requestedWorkspaceID in
                    await preparationGate.prepare(requestedWorkspaceID)
                }
            )
        } operation: {
            Store(
                initialState: Authoring<WorkspaceProbe>.State(workspaceID: workspaceID) {
                    WorkspaceProbe.State()
                }
            ) {
                Authoring { WorkspaceProbe() }
            }
        }

        expectNoDifference(store.access, .authoring(.owner))
        expectNoDifference(store.grant?.principal, .local)
        expectNoDifference(admissionRequests.withLock { $0 }, [])

        let preparationRequests = await preparationGate.waitForPreparationToStart()
        expectNoDifference(preparationRequests, [workspaceID])
        expectNoDifference(store.access, .authoring(.owner))

        await preparationGate.finish()
        try await waitForAuthoringCondition {
            store.grant?.workspace.id == workspaceID
                && store.sourcePreparation.isRunning == false
        }
        expectNoDifference(admissionRequests.withLock { $0 }, [])
    }

    @Test
    func `entry eligibility requires a granted admission`() throws {
        let workspace = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "eligibility-workspace"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        var state = Authoring<WorkspaceProbe>.State(workspace: workspace) {
            WorkspaceProbe.State()
        }

        #expect(!state.canEnterAuthoring)
        state.admission = .signInRequired
        #expect(!state.canEnterAuthoring)
        state.admission = .denied
        #expect(!state.canEnterAuthoring)
        state.admission = .granted(principal: .local, role: .owner)
        #expect(state.canEnterAuthoring)
    }

    @Test @MainActor
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `eligible attendee sees explicit entry and tapping rechecks admission`() async throws {
        let workspace = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "eligible-workspace"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let admissionRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let store = withDependencies {
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                admissionRequests.withLock { $0.append(workspaceID) }
                return .granted(principal: .local, role: .owner)
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { workspaceID in
                    #expect(workspaceID == workspace.id)
                    return workspace
                },
                prepareSource: { _ in }
            )
        } operation: {
            Store(
                initialState: Authoring<WorkspaceProbe>.State(workspace: workspace) {
                    WorkspaceProbe.State()
                }
            ) {
                Authoring { WorkspaceProbe() }
            }
        }

        try await waitForAuthoringCondition {
            store.admission == .granted(principal: .local, role: .owner)
        }
        #expect(store.canEnterAuthoring)
        #expect(store.grant == nil)

        await store.send(.enterButtonTapped)?.value

        #expect(store.access == .authoring(.owner))
        #expect(!store.canEnterAuthoring)
        expectNoDifference(
            admissionRequests.withLock { $0 },
            [workspace.id, workspace.id]
        )
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `entering authoring does not wait for source preparation`() async throws {
        let database = try DatabaseQueue()
        let workspace = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "instant-authoring"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let preparationGate = AuthoringPreparationGate()
        let persistedActivations = Mutex<[WorkspaceAuthoringActivationRecord]>([])
        let activatedAt = Date(timeIntervalSince1970: 2_000)

        let store: TestStoreActor<Authoring<WorkspaceProbe>> = await withDependencies {
            $0[WorkspaceAuthoringActivationClient.self] = WorkspaceAuthoringActivationClient(
                current: { _ in nil },
                activate: { workspaceID, principal, role in
                    persistedActivations.withLock {
                        $0.append(
                            WorkspaceAuthoringActivationRecord(
                                id: workspaceID,
                                principal: principal,
                                role: role,
                                activatedAt: activatedAt
                            )
                        )
                    }
                },
                deactivate: { _ in }
            )
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
                principal: .local,
                role: .owner,
                workspace: workspace
            )
        }
        let preparationRequests = await preparationGate.waitForPreparationToStart()

        expectNoDifference(preparationRequests, [workspace.id])
        let access = await store[dynamicMember: \.access]
        expectNoDifference(
            access,
            .authoring(.owner)
        )
        expectNoDifference(
            persistedActivations.withLock { $0 },
            [
                WorkspaceAuthoringActivationRecord(
                    id: workspace.id,
                    principal: .local,
                    role: .owner,
                    activatedAt: activatedAt
                )
            ]
        )

        await preparationGate.finish()
        await entry?.value
        await sourcePreparation?.value
        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `entering authoring mounts only the selected editing workspace`() async throws {
        let appDatabase = try DatabaseQueue()
        let referenceDatabaseA = try DatabaseQueue()
        let preparedReferenceDatabaseA = try DatabaseQueue()
        let referenceDatabaseB = try DatabaseQueue()
        try setMarker("app", in: appDatabase)
        try setMarker("A reference", in: referenceDatabaseA)
        try setMarker("A prepared reference", in: preparedReferenceDatabaseA)
        try setMarker("B reference", in: referenceDatabaseB)
        let workspaceA = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-a"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: referenceDatabaseA)
        )
        let preparedWorkspaceA = EditingWorkspace(
            id: workspaceA.id,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: preparedReferenceDatabaseA)
        )
        let workspaceB = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-b"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: referenceDatabaseB)
        )
        let authorizationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])

        let stores: (
            TestStoreActor<Authoring<WorkspaceProbe>>,
            TestStoreActor<Authoring<WorkspaceProbe>>
        ) = await withDependencies {
            $0.defaultDatabase = appDatabase
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                authorizationRequests.withLock { $0.append(workspaceID) }
                return .granted(principal: .local, role: .owner)
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
            var stateA = Authoring<WorkspaceProbe>.State(workspace: workspaceA) {
                WorkspaceProbe.State()
            }
            stateA.admission = .granted(principal: .local, role: .owner)
            let storeA = await TestStoreActor(initialState: stateA) {
                Authoring { WorkspaceProbe() }
            }

            var stateB = Authoring<WorkspaceProbe>.State(workspace: workspaceB) {
                WorkspaceProbe.State()
            }
            stateB.admission = .granted(principal: .local, role: .owner)
            let storeB = await TestStoreActor(initialState: stateB) {
                Authoring { WorkspaceProbe() }
            }
            return (storeA, storeB)
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
                principal: .local,
                role: .owner,
                workspace: preparedWorkspaceA
            )
        }
        await entry?.value
        await sourcePreparation?.value

        // The shared authoring grant updates workspace A's content only.
        let authoringContentAccessA = await storeA[dynamicMember: \.content.access]
        let authoringAccessB = await storeB[dynamicMember: \.access]
        let authoringContentAccessB = await storeB[dynamicMember: \.content.access]
        expectNoDifference(authoringContentAccessA, .authoring(.owner))
        expectNoDifference(authoringAccessB, .attendee)
        expectNoDifference(authoringContentAccessB, .attendee)
        expectNoDifference(
            authorizationRequests.withLock { $0 },
            [workspaceA.id, workspaceB.id, workspaceA.id]
        )
        expectNoDifference(preparationRequests.withLock { $0 }, [workspaceA.id])

        // Each wrapped feature reads its own mounted workspace and grant.
        await storeA.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = true
            $0.content.observedDatabaseMarker = "A prepared reference"
            $0.content.observedWorkspaceID = workspaceA.id
        }
        await storeB.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = false
            $0.content.observedDatabaseMarker = "B reference"
            $0.content.observedWorkspaceID = workspaceB.id
        }

        // Exiting revokes the same child's grant and remounts its attendee workspace.
        await TestExhaustivity.$current.withValue(.off) {
            await storeA.send(.exitButtonTapped)?.value
        }
        let refreshedAdmission = await storeA[dynamicMember: \.admission]
        expectNoDifference(
            refreshedAdmission,
            .granted(principal: .local, role: .owner)
        )
        await storeA.send(.content(.inspectButtonTapped)) {
            $0.content.observedCanAuthor = false
            $0.content.observedDatabaseMarker = "A reference"
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
        let workspace = EditingWorkspace(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-denied"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let admissionRequestCount = Mutex(0)
        let store: TestStoreActor<AuthoringErrorHost> = await withDependencies {
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { _ in
                let requestNumber = admissionRequestCount.withLock { count in
                    count += 1
                    return count
                }
                if requestNumber == 1 {
                    return .denied
                }
                throw TestFailure.authorizationDenied
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { _ in workspace },
                prepareSource: { workspaceID in
                    preparationRequests.withLock { $0.append(workspaceID) }
                }
            )
        } operation: {
            var state = AuthoringErrorHost.State(workspace: workspace)
            state.authoring.state.admission = .denied
            return await TestStoreActor(
                initialState: state
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
    func `workspace opening failure reports an ephemeral issue and keeps authoring`() async throws {
        let failure = SourceControlError.remoteOperationFailed(
            SourceControlRemoteFailure(
                kind: .timedOut,
                message: "SSH could not read data: Timed out waiting on socket"
            )
        )
        let workspace = EditingWorkspace(
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
            var state = AuthoringErrorHost.State(workspace: workspace)
            state.authoring.state.admission = .granted(principal: .local, role: .owner)
            return await TestStoreActor(
                initialState: state
            ) {
                AuthoringErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.authoring, .enterButtonTapped)?.value
        }
        await store.expect {
            $0.reportedErrorMessage =
                "Editing is available, but the source repository is not ready."
            $0.reportedErrorDebugDescription = String(describing: failure)
            $0.reportedErrorOperation = ErrorOperation(
                rawValue: "authoring.source-preparation"
            )
        }

        let deniedAccess = await store[dynamicMember: \.authoring.state.access]
        let deniedContentAccess = await store[dynamicMember: \.authoring.state.content.access]
        expectNoDifference(deniedAccess, .authoring(.owner))
        expectNoDifference(deniedContentAccess, .authoring(.owner))

        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `source preparation failure reports an ephemeral issue and keeps authoring`() async throws {
        let workspace = EditingWorkspace(
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
                    principal: .local,
                    role: .owner,
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
        expectNoDifference(access, .authoring(.owner))

        await store.dismount()
    }

    @Test
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func `one grant carries access and its editing database across mounts`() async throws {
        let attendeeDatabase = try DatabaseQueue()
        let authoringDatabase = try DatabaseQueue()
        try setMarker("attendee", in: attendeeDatabase)
        try setMarker("authoring", in: authoringDatabase)
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "shared-workspace")
        let preparedWorkspace = EditingWorkspace(
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
            var stateA = Authoring<WorkspaceProbe>.State(
                workspaceID: workspaceID,
                grant: grant
            ) {
                WorkspaceProbe.State()
            }
            stateA.admission = .granted(principal: .local, role: .owner)
            let storeA = await TestStoreActor(initialState: stateA) {
                Authoring { WorkspaceProbe() }
            }

            var stateB = Authoring<WorkspaceProbe>.State(
                workspaceID: workspaceID,
                grant: grant
            ) {
                WorkspaceProbe.State()
            }
            stateB.admission = .granted(principal: .local, role: .owner)
            let storeB = await TestStoreActor(initialState: stateB) {
                Authoring { WorkspaceProbe() }
            }
            return (storeA, storeB)
        }
        let (storeA, storeB) = stores

        let entry = await storeA.send(.enterButtonTapped)
        let sourcePreparation = await storeA.receive(\.authoringEntryPrepared) {
            $0.grant = AuthoringGrant(
                principal: .local,
                role: .owner,
                workspace: preparedWorkspace
            )
        }
        await entry?.value
        await sourcePreparation?.value

        let accessB = await storeB[dynamicMember: \.access]
        expectNoDifference(accessB, .authoring(.owner))
        await TestExhaustivity.$current.withValue(.off) {
            await storeB.send(.content(.inspectButtonTapped)) {
                $0.content.observedCanAuthor = true
                $0.content.observedDatabaseMarker = "authoring"
                $0.content.observedWorkspaceID = workspaceID
            }
        }

        await TestExhaustivity.$current.withValue(.off) {
            await storeB.send(.exitButtonTapped)?.value
        }
        let refreshedAdmission = await storeB[dynamicMember: \.admission]
        expectNoDifference(
            refreshedAdmission,
            .granted(principal: .local, role: .owner)
        )
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

@MainActor
private func waitForAuthoringCondition(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}

@Feature
struct AuthoringErrorHost {
    struct State {
        init(workspace: EditingWorkspace) {
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
            @Dependency(\.authoringGrant) var authoringGrant
            self._grant = authoringGrant
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

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.editingWorkspaceID) var editingWorkspaceID

    var body: some Feature {
        Update { state, action in
            switch action {
            case .inspectButtonTapped:
                state.observedCanAuthor = state.grant?.access.canEditContent ?? false
                state.observedDatabaseMarker = try? database.read { db in
                    try String.fetchOne(db, sql: "SELECT value FROM marker")
                }
                state.observedWorkspaceID = editingWorkspaceID

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

private extension Trait where Self == SourceEditingTestExhaustivityTrait {
    static func tcaExhaustivity(_ exhaustivity: TestExhaustivity) -> Self {
        SourceEditingTestExhaustivityTrait(exhaustivity: exhaustivity)
    }
}

private struct SourceEditingTestExhaustivityTrait: SuiteTrait, TestScoping, TestTrait {
    let exhaustivity: TestExhaustivity

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void
    ) async throws {
        try await TestExhaustivity.$current.withValue(exhaustivity) {
            try await function()
        }
    }
}
