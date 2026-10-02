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

public struct EventWorkspaceSession: Equatable, Sendable {
    public let eventID: Event.ID
    public let actorID: DID
    public let baseline: SourceBaselineDatabase

    public init(
        eventID: Event.ID,
        actorID: DID,
        baseline: SourceBaselineDatabase
    ) {
        self.eventID = eventID
        self.actorID = actorID
        self.baseline = baseline
    }

    public func authorizes(
        eventID: Event.ID,
        selectedActorID: DID
    ) -> Bool {
        self.eventID == eventID
            && actorID == selectedActorID
            && eventID.authority == .did(selectedActorID)
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

/// OME's complete evidence that the current principal may request authoring for a workspace.
///
/// The generic authoring boundary carries this exact value from admission through entry, making it
/// OME's sole entry evidence.
public struct AuthoringEligibility: Equatable, Sendable {
    public var principal: AuthoringPrincipal
    public var role: OME.WorkspaceRole

    public init(
        principal: AuthoringPrincipal,
        role: OME.WorkspaceRole
    ) {
        self.principal = principal
        self.role = role
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
    package let applicationDatabaseID: ObjectIdentifier
    package let referenceDatabase: SourceBaselineDatabase
    package let repositoryURL: URL
    package let workspace: SourceWorkspace

    package init(
        workspace: SourceWorkspace,
        repositoryURL: URL,
        mainDatabase: any DatabaseWriter,
        referenceDatabase: SourceBaselineDatabase
    ) {
        self.workspace = workspace
        self.repositoryURL = repositoryURL.standardizedFileURL
        self.applicationDatabaseID = ObjectIdentifier(mainDatabase)
        self.referenceDatabase = referenceDatabase
    }
}

public struct AuthoringRequested: FeatureEventKey {
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
