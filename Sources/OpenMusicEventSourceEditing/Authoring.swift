import ATProto
import ComposableArchitecture2
import ComposableAuthoring
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SourceEditing
import Sharing
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

public extension DependencyValues {
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
        self[ComposableAuthoring.AuthoringContext<AuthoringGrant>.self] =
            ComposableAuthoring.AuthoringContext(grant: grant)
    }
}

/// The single database resource owned by an editable workspace.
///
/// `database` is the writable application database with `source_baseline` already attached as a
/// read-only schema. No descendant may reopen or independently attach that baseline.
public final class SourceWorkspaceDatabase: Sendable {
    public let workspaceID: EditingWorkspaceRecord.ID
    public let database: any DatabaseWriter
    public let sourceEditingSession: SourceEditingSession

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

public struct AuthoringPolicyClient: Sendable {
    public var admission: @Sendable (
        EditingWorkspaceRecord.ID
    ) async throws -> AuthoringAdmission
    public var authorizeEntry: @Sendable (
        EditingWorkspaceRecord.ID,
        AuthoringPrincipal
    ) async throws -> Void
    public var requestSignIn: @Sendable () async throws -> Void

    public init(
        admission: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) async throws -> AuthoringAdmission,
        authorizeEntry: @escaping @Sendable (
            EditingWorkspaceRecord.ID,
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
