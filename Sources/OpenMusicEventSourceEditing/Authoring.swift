import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
#if canImport(OSLog)
import OSLog
#endif
import Sharing

public enum AuthoringCapability: Hashable, Sendable {
    case editContent
    case manageWorkspace
}

public enum AuthoringAccess: Equatable, Sendable {
    case attendee
    case authoring(Set<AuthoringCapability>)

    public var canEditContent: Bool {
        capabilities.contains(.editContent)
    }

    public var canManageWorkspace: Bool {
        capabilities.contains(.manageWorkspace)
    }

    public var capabilities: Set<AuthoringCapability> {
        guard case let .authoring(capabilities) = self else { return [] }
        return capabilities
    }
}

public struct AuthoringGrant: Equatable, Sendable {
    public var capabilities: Set<AuthoringCapability>
    public var workspace: WorkspaceContext

    public init(
        capabilities: Set<AuthoringCapability>,
        workspace: WorkspaceContext
    ) {
        self.capabilities = capabilities
        self.workspace = workspace
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.capabilities == rhs.capabilities
            && lhs.workspace.id == rhs.workspace.id
            && lhs.workspace.sourceEditingSession?.workingDatabasePath
                == rhs.workspace.sourceEditingSession?.workingDatabasePath
            && lhs.workspace.sourceEditingSession?.baselineDatabasePath
                == rhs.workspace.sourceEditingSession?.baselineDatabasePath
    }

    public var access: AuthoringAccess {
        .authoring(capabilities)
    }
}

public struct AuthoringContext: Sendable {
    @SharedReader public var grant: AuthoringGrant?

    public init(grant: SharedReader<AuthoringGrant?>) {
        self._grant = grant
    }

    public var access: AuthoringAccess {
        grant?.access ?? .attendee
    }

    public var canEditContent: Bool {
        access.canEditContent
    }

    public var canManageWorkspace: Bool {
        access.canManageWorkspace
    }
}

public struct AuthoringPolicyClient: Sendable {
    public var authorize: @Sendable (
        EditingWorkspaceRecord.ID
    ) async throws -> Set<AuthoringCapability>

    public init(
        authorize: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) async throws -> Set<AuthoringCapability>
    ) {
        self.authorize = authorize
    }
}

public enum AuthoringPolicyError: Error, Equatable, Sendable {
    case authorizationRequired
    case editContentDenied
}

public extension AuthoringPolicyClient {
    static var authoring: Self {
        Self { _ in [.editContent] }
    }

    static var attendee: Self {
        Self { _ in
            throw AuthoringPolicyError.authorizationRequired
        }
    }

    static var live: Self {
        .attendee
    }
}

public struct AuthoringRequested: FeatureEventKey {
    public typealias Value = Void

    public init() {}
}

@Feature
public struct Authoring<Content: FeatureProtocol> {
    public typealias Access = AuthoringAccess
    public typealias Capability = AuthoringCapability
    public typealias Context = AuthoringContext
    public typealias Grant = AuthoringGrant

    public init(
        makeContent: @escaping @Sendable () -> Content
    ) {
        self.makeContent = makeContent
    }

    let makeContent: @Sendable () -> Content

    public struct State {
        public init(
            workspaceID: EditingWorkspaceRecord.ID,
            initiallyRequestsEntry: Bool = false,
            makeContentState: () -> Content.State
        ) {
            @Dependency(\.defaultDatabase) var database
            self.init(
                attendeeWorkspace: WorkspaceContext(
                    id: workspaceID,
                    sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                ),
                grant: Shared(value: nil),
                initiallyRequestsEntry: initiallyRequestsEntry,
                makeContentState: makeContentState
            )
        }

        public init(
            workspace: WorkspaceContext,
            initiallyRequestsEntry: Bool = false,
            makeContentState: () -> Content.State
        ) {
            self.init(
                attendeeWorkspace: workspace,
                grant: Shared(value: nil),
                initiallyRequestsEntry: initiallyRequestsEntry,
                makeContentState: makeContentState
            )
        }

        public init(
            workspaceID: EditingWorkspaceRecord.ID,
            grant: Shared<AuthoringGrant?>,
            initiallyRequestsEntry: Bool = false,
            makeContentState: () -> Content.State
        ) {
            @Dependency(\.defaultDatabase) var database
            self.init(
                attendeeWorkspace: WorkspaceContext(
                    id: workspaceID,
                    sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                ),
                grant: grant,
                initiallyRequestsEntry: initiallyRequestsEntry,
                makeContentState: makeContentState
            )
        }

        private init(
            attendeeWorkspace: WorkspaceContext,
            grant: Shared<AuthoringGrant?>,
            initiallyRequestsEntry: Bool,
            makeContentState: () -> Content.State
        ) {
            self._grant = grant
            self.attendeeWorkspace = attendeeWorkspace
            self.initiallyRequestsEntry = initiallyRequestsEntry
            let workspace = grant.wrappedValue?.workspace ?? attendeeWorkspace
            self.content = withDependencies {
                $0.useWorkspaceContext(
                    workspace,
                    authoring: AuthoringContext(grant: SharedReader(grant))
                )
            } operation: {
                makeContentState()
            }
        }

        @Shared public var grant: AuthoringGrant?
        public var content: Content.State
        @StoreTaskID public var entry
        @DebugSnapshotIgnored public var attendeeWorkspace: WorkspaceContext
        @DebugSnapshotIgnored var initiallyRequestsEntry: Bool

        var grantReference: Shared<AuthoringGrant?> {
            get { $grant }
            set { $grant = newValue }
        }

        public var access: AuthoringAccess {
            grant?.access ?? .attendee
        }

        public var workspace: WorkspaceContext {
            guard let grant else { return attendeeWorkspace }
            precondition(
                grant.workspace.id == attendeeWorkspace.id,
                "An authoring grant cannot be mounted into a different workspace."
            )
            return grant.workspace
        }

        public var workspaceID: EditingWorkspaceRecord.ID {
            attendeeWorkspace.id
        }

        public mutating func invalidateAuthoring() {
            $grant.withLock { $0 = nil }
        }
    }

    public enum Action {
        case content(Content.Action)
        case enterButtonTapped
        case exitButtonTapped
    }

    @Dependency(AuthoringPolicyClient.self) var policy
    @Dependency(WorkspacePreparationClient.self) var preparation

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .content:
                break

            case .enterButtonTapped:
                enterAuthoring(state: &state)

            case .exitButtonTapped:
                state.invalidateAuthoring()
            }
        }
        Scope(\.content, action: \.content) {
            makeContent()
                .transformDependency(\.self) { dependencies in
                    let workspace = store.grant?.workspace ?? store.attendeeWorkspace
                    precondition(
                        workspace.id == store.attendeeWorkspace.id,
                        "An authoring grant cannot be mounted into a different workspace."
                    )
                    dependencies.useWorkspaceContext(
                        workspace,
                        authoring: AuthoringContext(
                            grant: SharedReader(store.grantReference)
                        )
                    )
                }
        }
        .onEvent(AuthoringRequested.self) { _, state in
            enterAuthoring(state: &state)
        }
        .onMount { state in
            guard state.initiallyRequestsEntry else { return }
            state.initiallyRequestsEntry = false
            enterAuthoring(state: &state)
        }
    }

    private func enterAuthoring(state: inout State) {
        guard !state.access.canEditContent, !state.entry.isRunning else { return }

        let workspaceID = state.workspaceID
        store.addTask(id: state.entry) {
            AuthoringEntryDiagnostics.logStarted(workspaceID: workspaceID)
            let capabilities: Set<AuthoringCapability>
            do {
                capabilities = try await policy.authorize(workspaceID)
                guard capabilities.contains(.editContent) else {
                    throw AuthoringPolicyError.editContentDenied
                }
            } catch {
                AuthoringEntryDiagnostics.logFailed(
                    error,
                    stage: "authorization",
                    workspaceID: workspaceID
                )
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Unable to enter authoring.",
                        fallback: "Unable to enter authoring."
                    ),
                    operation: ErrorOperation(rawValue: "authoring.entry.authorization")
                )
                return
            }

            do {
                let workspace = try await preparation.prepare(workspaceID)
                try store.modify {
                    $0.$grant.withLock {
                        $0 = AuthoringGrant(
                            capabilities: capabilities,
                            workspace: workspace
                        )
                    }
                }
                AuthoringEntryDiagnostics.logDone(workspaceID: workspaceID)
            } catch {
                AuthoringEntryDiagnostics.logFailed(
                    error,
                    stage: "preparation",
                    workspaceID: workspaceID
                )
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Unable to enter authoring.",
                        fallback: "Unable to enter authoring."
                    ),
                    operation: ErrorOperation(rawValue: "authoring.entry.preparation")
                )
            }
        }
    }
}

private enum AuthoringEntryDiagnostics {
    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: "fm.woody.openmusicevent",
        category: "Authoring"
    )
    #endif

    static func logStarted(workspaceID: EditingWorkspaceRecord.ID) {
        log("""
        Enter Authoring started
        workspace: \(workspaceID)
        """)
    }

    static func logDone(workspaceID: EditingWorkspaceRecord.ID) {
        log("""
        Enter Authoring done
        workspace: \(workspaceID)
        """)
    }

    static func logFailed(
        _ error: Error,
        stage: String,
        workspaceID: EditingWorkspaceRecord.ID
    ) {
        log("""
        Enter Authoring failed
        workspace: \(workspaceID)
        stage: \(stage)
        error: \(String(describing: error))
        """, isError: true)
    }

    static func log(_ message: String, isError: Bool = false) {
        #if canImport(OSLog)
        if isError {
            logger.error("\(message, privacy: .public)")
        } else {
            logger.notice("\(message, privacy: .public)")
        }
        #else
        print(message)
        #endif
    }
}

private enum AuthoringContextKey: DependencyKey {
    static var liveValue: AuthoringContext? { nil }
    static var testValue: AuthoringContext? { nil }
}

extension AuthoringPolicyClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .attendee }
}

public extension DependencyValues {
    var authoringContext: AuthoringContext? {
        get { self[AuthoringContextKey.self] }
        set { self[AuthoringContextKey.self] = newValue }
    }
}
