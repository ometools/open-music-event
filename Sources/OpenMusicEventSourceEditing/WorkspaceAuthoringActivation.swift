import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData

@Table("sourceWorkspaceAuthoringActivations")
public struct WorkspaceAuthoringActivationRecord: Equatable, Sendable, Identifiable {
    public var id: SourceWorkspace.ID
    @Column(as: AuthoringPrincipal.JSONRepresentation.self)
    public var principal: AuthoringPrincipal
    @Column(as: OME.WorkspaceRole.JSONRepresentation.self)
    public var role: OME.WorkspaceRole
    public var activatedAt: Date

    public init(
        id: SourceWorkspace.ID,
        principal: AuthoringPrincipal,
        role: OME.WorkspaceRole,
        activatedAt: Date
    ) {
        self.id = id
        self.principal = principal
        self.role = role
        self.activatedAt = activatedAt
    }
}

public struct WorkspaceAuthoringActivationClient: Sendable {
    public var current: @Sendable (
        SourceWorkspace.ID
    ) throws -> WorkspaceAuthoringActivationRecord?
    public var activate: @Sendable (
        SourceWorkspace.ID,
        AuthoringPrincipal,
        OME.WorkspaceRole
    ) async throws -> Void
    public var deactivate: @Sendable (
        SourceWorkspace.ID
    ) async throws -> Void

    public init(
        current: @escaping @Sendable (
            SourceWorkspace.ID
        ) throws -> WorkspaceAuthoringActivationRecord?,
        activate: @escaping @Sendable (
            SourceWorkspace.ID,
            AuthoringPrincipal,
            OME.WorkspaceRole
        ) async throws -> Void,
        deactivate: @escaping @Sendable (
            SourceWorkspace.ID
        ) async throws -> Void
    ) {
        self.current = current
        self.activate = activate
        self.deactivate = deactivate
    }
}

public extension WorkspaceAuthoringActivationClient {
    static var live: Self {
        Self(
            current: { workspaceID in
                @Dependency(\.defaultDatabase) var database
                return try database.read { db in
                    try WorkspaceAuthoringActivationRecord
                        .find(workspaceID)
                        .fetchOne(db)
                }
            },
            activate: { workspaceID, principal, role in
                @Dependency(\.defaultDatabase) var database
                @Dependency(\.date.now) var now
                let activation = WorkspaceAuthoringActivationRecord(
                    id: workspaceID,
                    principal: principal,
                    role: role,
                    activatedAt: now
                )
                try await database.write { db in
                    try WorkspaceAuthoringActivationRecord.insert {
                        activation
                    } onConflict: {
                        $0.id
                    } doUpdate: { activation, excluded in
                        activation.principal = excluded.principal
                        activation.role = excluded.role
                        activation.activatedAt = excluded.activatedAt
                    }
                    .execute(db)
                }
            },
            deactivate: { workspaceID in
                @Dependency(\.defaultDatabase) var database
                try await database.write { db in
                    try WorkspaceAuthoringActivationRecord
                        .find(workspaceID)
                        .delete()
                        .execute(db)
                }
            }
        )
    }

    static let inactive = Self(
        current: { _ in nil },
        activate: { _, _, _ in },
        deactivate: { _ in }
    )
}

extension WorkspaceAuthoringActivationClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .inactive }
}
