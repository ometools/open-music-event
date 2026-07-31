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
import SourceEditing
import SQLiteData

public enum AuthoringPrincipal: Codable, Equatable, Hashable, Sendable {
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
    public var workspaceID: EditingWorkspaceRecord.ID

    public init(
        principal: AuthoringPrincipal,
        role: OME.WorkspaceRole,
        workspaceID: EditingWorkspaceRecord.ID
    ) {
        self.principal = principal
        self.role = role
        self.workspaceID = workspaceID
    }

    public var access: AuthoringAccess {
        .authoring(role)
    }
}

private enum AuthoringGrantReaderKey: DependencyKey {
    static var liveValue: SharedReader<AuthoringGrant?> {
        SharedReader(value: nil)
    }

    static var testValue: SharedReader<AuthoringGrant?> {
        SharedReader(value: nil)
    }
}

private enum EditingWorkspaceIDKey: DependencyKey {
    static var liveValue: EditingWorkspaceRecord.ID? { nil }
    static var testValue: EditingWorkspaceRecord.ID? { nil }
}

public struct SourceWorkspaceDatabase: Sendable {
    public var workspaceID: EditingWorkspaceRecord.ID
    public var database: any DatabaseWriter
    public var sourceEditingSession: SourceEditingSession?

    public init(
        workspaceID: EditingWorkspaceRecord.ID,
        database: any DatabaseWriter
    ) {
        self.workspaceID = workspaceID
        self.database = database
    }

    public init(
        workspaceID: EditingWorkspaceRecord.ID,
        mainDatabase: any DatabaseWriter,
        referenceDatabase: SourceBaselineDatabase
    ) throws {
        let session = try SourceEditingSession(
            mainDatabase: mainDatabase,
            baselineDatabasePath: referenceDatabase.path
        )
        self.workspaceID = workspaceID
        self.database = session.database
        self.sourceEditingSession = session
    }
}

public enum SourceWorkspaceDatabaseError: Equatable, Error, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case workspaceNotFound(EditingWorkspaceRecord.ID)
}

public struct SourceWorkspaceDatabaseClient: Sendable {
    public var open: @Sendable (
        EditingWorkspaceRecord.ID
    ) throws -> SourceWorkspaceDatabase?

    public init(
        open: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) throws -> SourceWorkspaceDatabase?
    ) {
        self.open = open
    }
}

public extension SourceWorkspaceDatabaseClient {
    static var live: Self {
        Self { workspaceID in
            @Dependency(\.defaultDatabase) var mainDatabase
            @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase
            let (workspace, sourceBaseline) = try mainDatabase.read { db in
                let workspace = try EditingWorkspaceRecord
                    .where { $0.id.eq(workspaceID) }
                    .fetchOne(db)
                let sourceBaseline = try workspace?.sourceBaselineID.flatMap { sourceBaselineID in
                    try SourceBaselineRecord
                        .where { $0.id.eq(sourceBaselineID) }
                        .fetchOne(db)
                }
                return (workspace, sourceBaseline)
            }
            guard let workspace else {
                throw SourceWorkspaceDatabaseError.workspaceNotFound(workspaceID)
            }
            if let sourceBaselineID = workspace.sourceBaselineID,
               sourceBaseline == nil {
                throw SourceWorkspaceDatabaseError.sourceBaselineNotFound(sourceBaselineID)
            }
            let referenceDatabase = try workspaceReferenceDatabase.existing(
                workspace,
                sourceBaseline: sourceBaseline
            )
            guard let referenceDatabase else {
                return SourceWorkspaceDatabase(
                    workspaceID: workspaceID,
                    database: mainDatabase
                )
            }
            return try SourceWorkspaceDatabase(
                workspaceID: workspaceID,
                mainDatabase: mainDatabase,
                referenceDatabase: referenceDatabase
            )
        }
    }

    static var passthrough: Self {
        Self { _ in nil }
    }
}

extension SourceWorkspaceDatabaseClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .passthrough }
}

public extension DependencyValues {
    var authoringGrant: SharedReader<AuthoringGrant?> {
        get { self[AuthoringGrantReaderKey.self] }
        set { self[AuthoringGrantReaderKey.self] = newValue }
    }

    var editingWorkspaceID: EditingWorkspaceRecord.ID? {
        get { self[EditingWorkspaceIDKey.self] }
        set { self[EditingWorkspaceIDKey.self] = newValue }
    }

    mutating func useAuthoringContext(
        _ workspaceID: EditingWorkspaceRecord.ID,
        grant: SharedReader<AuthoringGrant?>
    ) {
        if let grantedWorkspaceID = grant.wrappedValue?.workspaceID {
            precondition(
                grantedWorkspaceID == workspaceID,
                "An authoring grant cannot be used for a different workspace."
            )
        }
        authoringGrant = grant
        editingWorkspaceID = workspaceID
    }

    mutating func useAuthoringContext(
        _ workspaceDatabase: SourceWorkspaceDatabase,
        grant: SharedReader<AuthoringGrant?>
    ) {
        useAuthoringContext(workspaceDatabase.workspaceID, grant: grant)
        defaultDatabase = workspaceDatabase.database
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
            @Dependency(WorkspaceAuthoringActivationClient.self) var activations
            let restoration = Result {
                try activations.current(workspaceID)
            }
            let activation = try? restoration.get()
            self.init(
                workspaceID: workspaceID,
                grant: Shared(
                    value: activation.map {
                        AuthoringGrant(
                            principal: $0.principal,
                            role: $0.role,
                            workspaceID: workspaceID
                        )
                    }
                ),
                initiallyRequestsEntry: initiallyRequestsEntry,
                makeContentState: makeContentState
            )
            if case let .failure(error) = restoration {
                activationRestorationErrorDescription = String(reflecting: error)
            }
        }

        public init(
            workspaceID: EditingWorkspaceRecord.ID,
            grant: Shared<AuthoringGrant?>,
            initiallyRequestsEntry: Bool = false,
            makeContentState: () -> Content.State
        ) {
            @Dependency(SourceWorkspaceDatabaseClient.self) var sourceWorkspaceDatabaseClient
            if let grantedWorkspaceID = grant.wrappedValue?.workspaceID {
                precondition(
                    grantedWorkspaceID == workspaceID,
                    "An authoring grant cannot be used for a different workspace."
                )
            }
            self._grant = grant
            self.workspaceID = workspaceID
            self.admission = grant.wrappedValue.map {
                .granted(principal: $0.principal, role: $0.role)
            }
            self.initiallyRequestsEntry = initiallyRequestsEntry
            let sourceWorkspaceDatabaseResult = Result {
                try sourceWorkspaceDatabaseClient.open(workspaceID)
            }
            let sourceWorkspaceDatabase = try? sourceWorkspaceDatabaseResult.get()
            self.sourceWorkspaceDatabase = sourceWorkspaceDatabase
            self.content = withDependencies {
                if let sourceWorkspaceDatabase {
                    $0.useAuthoringContext(sourceWorkspaceDatabase, grant: SharedReader(grant))
                } else {
                    $0.useAuthoringContext(workspaceID, grant: SharedReader(grant))
                }
            } operation: {
                makeContentState()
            }
            if case let .failure(error) = sourceWorkspaceDatabaseResult {
                sourceWorkspaceDatabaseErrorDescription = String(reflecting: error)
            }
        }

        @Shared public var grant: AuthoringGrant?
        public var admission: AuthoringAdmission?
        public var content: Content.State
        @StoreTaskID public var admissionCheck
        @StoreTaskID public var activationPersistence
        @StoreTaskID public var entry
        @StoreTaskID public var sourcePreparation
        @DebugSnapshotIgnored var activationRestorationErrorDescription: String?
        @DebugSnapshotIgnored var initiallyRequestsEntry: Bool
        @DebugSnapshotIgnored var sourceWorkspaceDatabaseErrorDescription: String?
        @DebugSnapshotIgnored public var sourceWorkspaceDatabase: SourceWorkspaceDatabase?
        @DebugSnapshotIgnored public var workspaceID: EditingWorkspaceRecord.ID

        public var access: AuthoringAccess {
            grant?.access ?? .attendee
        }

        public var canEnterAuthoring: Bool {
            guard !access.canEditContent,
                  case .granted = admission
            else { return false }
            return true
        }

        public mutating func invalidateAuthoring() {
            $grant.withLock { $0 = nil }
            admission = nil
        }
    }

    public enum Action {
        case authoringEntryPrepared(AuthoringGrant)
        case authoringExitPersisted
        case content(Content.Action)
        case enterButtonTapped
        case exitButtonTapped
        case refreshAdmission
        case sourceWorkspaceDatabasePrepared(SourceWorkspaceDatabase)
    }

    @Dependency(WorkspaceAuthoringActivationClient.self) var activations
    @Dependency(AuthoringPolicyClient.self) var policy
    @Dependency(SourceWorkspaceDatabaseClient.self) var sourceWorkspaceDatabaseClient
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
                AuthoringEntryDiagnostics.logDone(workspaceID: grant.workspaceID)
                prepareSource(state: &state, workspaceID: grant.workspaceID)

            case .authoringExitPersisted:
                state.invalidateAuthoring()
                refreshAdmission(state: &state)

            case .content:
                break

            case .enterButtonTapped:
                enterAuthoring(state: &state)

            case .exitButtonTapped:
                exitAuthoring(state: &state)

            case .refreshAdmission:
                refreshAdmission(state: &state)

            case let .sourceWorkspaceDatabasePrepared(sourceWorkspaceDatabase):
                guard sourceWorkspaceDatabase.workspaceID == state.workspaceID else { return }
                state.sourceWorkspaceDatabase = sourceWorkspaceDatabase

            }
        }
        Scope(\.content, action: \.content) {
            makeContent()
                .transformDependency(\.self) { dependencies in
                    if let sourceWorkspaceDatabase = store.sourceWorkspaceDatabase {
                        dependencies.useAuthoringContext(
                            sourceWorkspaceDatabase,
                            grant: SharedReader(store.$grant)
                        )
                    } else {
                        dependencies.useAuthoringContext(
                            store.workspaceID,
                            grant: SharedReader(store.$grant)
                        )
                    }
                }
        }
        .onEvent(AuthoringRequested.self) { _, state in
            enterAuthoring(state: &state)
        }
        .onEvent(AuthoringAccessRevoked.self) { _, state in
            state.admission = .denied
        }
        .onEvent(AuthoringExitRequested.self) { _, state in
            exitAuthoring(state: &state)
        }
        .onMount { state in
            reportActivationRestorationFailure(state: &state)
            reportSourceWorkspaceDatabaseFailure(state: &state)
            if state.access.canEditContent {
                prepareSource(state: &state, workspaceID: state.workspaceID)
            } else if state.initiallyRequestsEntry {
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
                try await activations.activate(workspaceID, principal, role)
                try store.send(
                    .authoringEntryPrepared(
                        AuthoringGrant(
                            principal: principal,
                            role: role,
                            workspaceID: workspaceID
                        )
                    )
                )
            } catch {
                AuthoringEntryDiagnostics.logFailed(
                    error,
                    stage: "activation persistence",
                    workspaceID: workspaceID
                )
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Unable to save authoring access.",
                        fallback: "Unable to save authoring access."
                    ),
                    operation: ErrorOperation(rawValue: "authoring.entry.persistence")
                )
            }
        }
    }

    private func exitAuthoring(state: inout State) {
        guard state.access.canEditContent,
              !state.activationPersistence.isRunning
        else { return }

        let workspaceID = state.workspaceID
        store.addTask(id: state.activationPersistence) {
            do {
                try await activations.deactivate(workspaceID)
                try store.send(.authoringExitPersisted)
            } catch {
                await store.reportError(
                    error,
                    fallbackMessage: UserFacingText(
                        "Unable to exit authoring.",
                        fallback: "Unable to exit authoring."
                    ),
                    operation: ErrorOperation(rawValue: "authoring.exit.persistence")
                )
            }
        }
    }

    private func prepareSource(
        state: inout State,
        workspaceID: EditingWorkspaceRecord.ID
    ) {
        guard !state.sourcePreparation.isRunning else { return }
        store.addTask(id: state.sourcePreparation) {
            do {
                try await preparation.prepareSource(workspaceID)
                guard let sourceWorkspaceDatabase = try sourceWorkspaceDatabaseClient.open(
                    workspaceID
                ) else { return }
                try store.send(
                    .sourceWorkspaceDatabasePrepared(sourceWorkspaceDatabase)
                )
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

    private func reportSourceWorkspaceDatabaseFailure(state: inout State) {
        guard let description = state.sourceWorkspaceDatabaseErrorDescription else { return }
        state.sourceWorkspaceDatabaseErrorDescription = nil
        store.addTask {
            await store.reportError(
                WorkspaceAuthoringDatabaseError(description: description),
                fallbackMessage: UserFacingText(
                    "Unable to open the source comparison database.",
                    fallback: "Unable to open the source comparison database."
                ),
                operation: ErrorOperation(rawValue: "authoring.database")
            )
        }
    }

    private func reportActivationRestorationFailure(state: inout State) {
        guard let description = state.activationRestorationErrorDescription else { return }
        state.activationRestorationErrorDescription = nil
        store.addTask {
            await store.reportError(
                WorkspaceAuthoringActivationRestorationError(description: description),
                fallbackMessage: UserFacingText(
                    "Unable to restore authoring access.",
                    fallback: "Unable to restore authoring access."
                ),
                operation: ErrorOperation(rawValue: "authoring.restoration")
            )
        }
    }
}

private struct WorkspaceAuthoringActivationRestorationError: Error, Sendable {
    var description: String
}

private struct WorkspaceAuthoringDatabaseError: Error, Sendable {
    var description: String
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
