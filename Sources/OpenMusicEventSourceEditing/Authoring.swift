import ATProto
import ComposableArchitecture2
import ComposableAuthoring
import Dependencies
import Foundation
import OpenMusicEventLexicon
import Sharing
import SourceEditing
import SQLiteData

public struct AuthoringPrincipal: Codable, Equatable, Hashable, Sendable {
    public var actorID: DID

    public init(actorID: DID) {
        self.actorID = actorID
    }
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
    public var workspaceID: SourceWorkspace.ID

    public init(
        principal: AuthoringPrincipal,
        role: OME.WorkspaceRole,
        workspaceID: SourceWorkspace.ID
    ) {
        self.principal = principal
        self.role = role
        self.workspaceID = workspaceID
    }

    public var access: AuthoringAccess {
        .authoring(role)
    }
}

public extension DependencyValues {
    mutating func useAuthoringContext(
        _ workspaceID: SourceWorkspace.ID,
        grant: SharedReader<AuthoringGrant?>
    ) {
        if let grantedWorkspaceID = grant.wrappedValue?.workspaceID {
            precondition(
                grantedWorkspaceID == workspaceID,
                "An authoring grant cannot be used for a different workspace."
            )
        }
        self[ComposableAuthoring.AuthoringContext<AuthoringGrant>.self] =
            ComposableAuthoring.AuthoringContext(grant: grant)
    }
}

public final class SourceWorkspaceResource: Sendable {
    public let database: any DatabaseWriter
    public let repositoryURL: URL
    public let sourceEditingSession: SourceEditingSession
    public let workspace: SourceWorkspace

    public init(
        workspace: SourceWorkspace,
        repositoryURL: URL,
        mainDatabase: any DatabaseWriter,
        referenceDatabase: SourceBaselineDatabase
    ) throws {
        let session = try SourceEditingSession(
            mainDatabase: mainDatabase,
            baselineDatabasePath: referenceDatabase.path
        )
        self.workspace = workspace
        self.repositoryURL = repositoryURL.standardizedFileURL
        self.database = session.database
        self.sourceEditingSession = session
    }
}

public struct AuthoringPolicyClient: Sendable {
    public var admission: @Sendable (SourceWorkspace) async throws -> AuthoringAdmission
    public var authorizeEntry: @Sendable (
        SourceWorkspace,
        AuthoringPrincipal
    ) async throws -> Void
    public var requestSignIn: @Sendable () async throws -> Void

    public init(
        admission: @escaping @Sendable (SourceWorkspace) async throws -> AuthoringAdmission,
        authorizeEntry: @escaping @Sendable (
            SourceWorkspace,
            AuthoringPrincipal
        ) async throws -> Void = { _, _ in },
        requestSignIn: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.admission = admission
        self.authorizeEntry = authorizeEntry
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
    static var attendee: Self {
        Self { _ in .denied }
    }

    static var live: Self {
        .attendee
    }
}

extension AuthoringPolicyClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .attendee }
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

public struct SourceWorkspacePreparationRetryRequested: FeatureEventKey {
    public typealias Value = Void

    public init() {}
}
