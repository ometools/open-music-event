import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import Sharing
import Synchronization
import Testing

@Suite
struct AuthoringTests {
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
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient { workspaceID in
                preparationRequests.withLock { $0.append(workspaceID) }
                switch workspaceID {
                case workspaceA.id:
                    return preparedWorkspaceA
                case workspaceB.id:
                    return workspaceB
                default:
                    throw TestFailure.unexpectedWorkspace
                }
            }
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
        await entry?.value
        await storeA.expect {
            $0.grant = AuthoringGrant(
                capabilities: [.editContent],
                workspace: preparedWorkspaceA
            )
        }

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
    func `authorization failure remains attendee without a response action`() async throws {
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-denied"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: try DatabaseQueue())
        )
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let store: TestStoreActor<Authoring<WorkspaceProbe>> = await withDependencies {
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { _ in
                throw TestFailure.authorizationDenied
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient { workspaceID in
                preparationRequests.withLock { $0.append(workspaceID) }
                return workspace
            }
        } operation: {
            await TestStoreActor(
                initialState: Authoring<WorkspaceProbe>.State(workspace: workspace) {
                    WorkspaceProbe.State()
                }
            ) {
                Authoring { WorkspaceProbe() }
            }
        }

        // Authorization fails inside the entry task and modifies the store directly.
        let entry = await store.send(.enterButtonTapped)
        await entry?.value
        await store.expect {
            $0.entryFailure = AuthoringEntryFailure(
                stage: .authorization,
                message: "Authorization denied"
            )
        }

        // Preparation never starts, and the workspace stays attendee-only.
        let deniedAccess = await store[dynamicMember: \.access]
        let deniedContentAccess = await store[dynamicMember: \.content.access]
        expectNoDifference(deniedAccess, .attendee)
        expectNoDifference(deniedContentAccess, .attendee)
        expectNoDifference(preparationRequests.withLock { $0 }, [])

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
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient { id in
                #expect(id == workspaceID)
                return preparedWorkspace
            }
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
        await entry?.value
        await storeA.expect {
            $0.grant = AuthoringGrant(
                capabilities: [.editContent],
                workspace: preparedWorkspace
            )
        }

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
    case unexpectedWorkspace

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Authorization denied"
        case .unexpectedWorkspace:
            "Unexpected workspace"
        }
    }
}
