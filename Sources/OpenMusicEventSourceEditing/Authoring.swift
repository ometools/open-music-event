import ATProto
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventLexicon
#if canImport(OSLog)
import OSLog
#endif
import Sharing

public enum AuthoringPrincipal: Equatable, Hashable, Sendable {
    case local
    case actor(DID)
}

public enum AuthoringAccess: Equatable, Sendable {
    case attendee
    case authoring(OME.WorkspaceRole)

    public var canEditContent: Bool {
        guard case .authoring = self else { return false }
        return true
    }

    public var canManageWorkspace: Bool {
        role?.canManageCollaborators == true
    }

    public var canPropose: Bool {
        role?.canPropose == true
    }

    public var canMerge: Bool {
        role?.canMerge == true
    }

    public var role: OME.WorkspaceRole? {
        guard case let .authoring(role) = self else { return nil }
        return role
    }
}

public struct AuthoringGrant: Equatable, Sendable {
    public var principal: AuthoringPrincipal
    public var role: OME.WorkspaceRole
    public var workspace: WorkspaceContext

    public init(
        principal: AuthoringPrincipal,
        role: OME.WorkspaceRole,
        workspace: WorkspaceContext
    ) {
        self.principal = principal
        self.role = role
        self.workspace = workspace
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.principal == rhs.principal
            && lhs.role == rhs.role
            && lhs.workspace.id == rhs.workspace.id
            && lhs.workspace.sourceEditingSession?.workingDatabasePath
                == rhs.workspace.sourceEditingSession?.workingDatabasePath
            && lhs.workspace.sourceEditingSession?.baselineDatabasePath
                == rhs.workspace.sourceEditingSession?.baselineDatabasePath
    }

    public var access: AuthoringAccess {
        .authoring(role)
    }
}

public struct AuthoringPolicyClient: Sendable {
    public var admission: @Sendable (
        EditingWorkspaceRecord.ID
    ) async throws -> AuthoringAdmission
    public var requestSignIn: @Sendable () async throws -> Void

    public init(
        admission: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) async throws -> AuthoringAdmission,
        requestSignIn: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.admission = admission
        self.requestSignIn = requestSignIn
    }
}

public enum AuthoringAdmission: Equatable, Sendable {
    case granted(principal: AuthoringPrincipal, role: OME.WorkspaceRole)
    case signInRequired
    case denied
}

public enum AuthoringPolicyError: Error, Equatable, Sendable {
    case authorizationRequired
    case admissionDenied
}

public extension AuthoringPolicyClient {
    static var authoring: Self {
        Self { _ in
            .granted(principal: .local, role: .owner)
        }
    }

    static var attendee: Self {
        Self { _ in .denied }
    }

    static var live: Self {
        .attendee
    }
}

public struct AuthoringRequested: FeatureEventKey {
    public typealias Value = Void

    public init() {}
}

public struct AuthoringAccessRevoked: FeatureEventKey {
    public typealias Value = Void

    public init() {}
}

public struct AuthoringExitRequested: FeatureEventKey {
    public typealias Value = Void

    public init() {}
}

@Feature
public struct Authoring<Content: FeatureProtocol> {
    public typealias Access = AuthoringAccess
    public typealias Capability = OME.WorkspaceRole.Capability
    public typealias Context = WorkspaceContext
    public typealias Grant = AuthoringGrant
    public typealias Role = OME.WorkspaceRole

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
            self.admission = grant.wrappedValue.map {
                .granted(principal: $0.principal, role: $0.role)
            }
            self.initiallyRequestsEntry = initiallyRequestsEntry
            let workspace = grant.wrappedValue?.workspace ?? attendeeWorkspace
            self.content = withDependencies {
                $0.useWorkspaceContext(
                    workspace.mounting(grant: SharedReader(grant))
                )
            } operation: {
                makeContentState()
            }
        }

        @Shared public var grant: AuthoringGrant?
        public var admission: AuthoringAdmission?
        public var content: Content.State
        @StoreTaskID public var admissionCheck
        @StoreTaskID public var entry
        @StoreTaskID public var sourcePreparation
        @DebugSnapshotIgnored public var attendeeWorkspace: WorkspaceContext
        @DebugSnapshotIgnored var initiallyRequestsEntry: Bool

        var grantReference: Shared<AuthoringGrant?> {
            get { $grant }
            set { $grant = newValue }
        }

        public var access: AuthoringAccess {
            grant?.access ?? .attendee
        }

        public var canEnterAuthoring: Bool {
            guard !access.canEditContent,
                  case .granted = admission
            else { return false }
            return true
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
            admission = nil
        }
    }

    public enum Action {
        case authoringEntryPrepared(AuthoringGrant)
        case content(Content.Action)
        case enterButtonTapped
        case exitButtonTapped
        case refreshAdmission
    }

    @Dependency(AuthoringPolicyClient.self) var policy
    @Dependency(WorkspacePreparationClient.self) var preparation

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .authoringEntryPrepared(grant):
                state.admission = .granted(
                    principal: grant.principal,
                    role: grant.role
                )
                state.$grant.withLock { $0 = grant }
                AuthoringEntryDiagnostics.logDone(workspaceID: grant.workspace.id)
                prepareSource(state: &state, workspaceID: grant.workspace.id)

            case .content:
                break

            case .enterButtonTapped:
                enterAuthoring(state: &state)

            case .exitButtonTapped:
                state.invalidateAuthoring()
                refreshAdmission(state: &state)

            case .refreshAdmission:
                state.invalidateAuthoring()
                refreshAdmission(state: &state)
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
                        workspace.mounting(
                            grant: SharedReader(store.grantReference)
                        )
                    )
                }
        }
        .onEvent(AuthoringRequested.self) { _, state in
            enterAuthoring(state: &state)
        }
        .onEvent(AuthoringAccessRevoked.self) { _, state in
            state.invalidateAuthoring()
            state.admission = .denied
        }
        .onEvent(AuthoringExitRequested.self) { _, state in
            state.invalidateAuthoring()
        }
        .onMount { state in
            if state.initiallyRequestsEntry {
                state.initiallyRequestsEntry = false
                enterAuthoring(state: &state)
            } else {
                refreshAdmission(state: &state)
            }
        }
    }

    private func refreshAdmission(state: inout State) {
        guard !state.access.canEditContent else { return }

        state.admission = nil
        let workspaceID = state.workspaceID
        store.addTask(id: state.admissionCheck) {
            do {
                let admission = try await policy.admission(workspaceID)
                try store.modify {
                    $0.admission = admission
                }
            } catch {
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Unable to check authoring access.",
                        fallback: "Unable to check authoring access."
                    ),
                    operation: ErrorOperation(rawValue: "authoring.admission")
                )
            }
        }
    }

    private func enterAuthoring(state: inout State) {
        guard !state.access.canEditContent, !state.entry.isRunning else { return }

        let admissionCheck = state.admissionCheck
        state.admission = nil
        let workspaceID = state.workspaceID
        store.addTask(id: state.entry) {
            await admissionCheck.cancel()?.value
            try store.modify {
                $0.admission = nil
            }
            AuthoringEntryDiagnostics.logStarted(workspaceID: workspaceID)
            let principal: AuthoringPrincipal
            let role: OME.WorkspaceRole
            do {
                var admission = try await policy.admission(workspaceID)
                if case .signInRequired = admission {
                    try await policy.requestSignIn()
                    admission = try await policy.admission(workspaceID)
                }
                switch admission {
                case let .granted(grantedPrincipal, grantedRole):
                    principal = grantedPrincipal
                    role = grantedRole
                case .signInRequired:
                    try store.modify {
                        $0.admission = admission
                    }
                    throw AuthoringPolicyError.authorizationRequired
                case .denied:
                    try store.modify {
                        $0.admission = admission
                    }
                    throw AuthoringPolicyError.admissionDenied
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
                let workspace = try preparation.open(workspaceID)
                try store.send(
                    .authoringEntryPrepared(
                        AuthoringGrant(
                            principal: principal,
                            role: role,
                            workspace: workspace
                        )
                    )
                )
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

    private func prepareSource(
        state: inout State,
        workspaceID: EditingWorkspaceRecord.ID
    ) {
        store.addTask(id: state.sourcePreparation) {
            do {
                try await preparation.prepareSource(workspaceID)
            } catch {
                AuthoringEntryDiagnostics.logFailed(
                    error,
                    stage: "source preparation",
                    workspaceID: workspaceID
                )
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Editing is available, but the source repository is not ready.",
                        fallback: "Editing is available, but the source repository is not ready."
                    ),
                    operation: ErrorOperation(
                        rawValue: "authoring.source-preparation"
                    )
                )
            }
        }
    }
}

extension Authoring.State: Identifiable where Content.State: Identifiable {
    public var id: Content.State.ID {
        content.id
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

extension AuthoringPolicyClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .attendee }
}
