import ComposableWorkspace
import Dependencies
import SourceEditing

public struct PreparedWorkspacePublishedUpdate: Sendable {
    public var apply: @Sendable (
        WorkspaceBranchReference
    ) async throws -> WorkspaceBranchReference

    public init(
        apply: @escaping @Sendable (
            WorkspaceBranchReference
        ) async throws -> WorkspaceBranchReference
    ) {
        self.apply = apply
    }
}

/// The published snapshot is mounted locally, but its main-database baseline marker needs repair.
public struct WorkspaceReferenceUpdateIncomplete: Error, Equatable, Sendable {
    public var mountedBaseline: WorkspaceBranchReference
    public var message: String

    public init(mountedBaseline: WorkspaceBranchReference, message: String) {
        self.mountedBaseline = mountedBaseline
        self.message = message
    }
}

/// Database-layer context installation. Preparing a publication replacement happens before the
/// PDS write; applying it happens afterward and is safe to repair independently.
public struct WorkspaceReferenceUpdateClient: Sendable {
    public var preparePublishedUpdate: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspacePublicationAttempt<SourcePatch>
    ) async throws -> PreparedWorkspacePublishedUpdate
    public var refresh: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspaceBranchReference
    ) async throws -> WorkspaceBranchReference
    public var select: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspaceBranch
    ) async throws -> WorkspaceBranchReference

    public init(
        preparePublishedUpdate: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspacePublicationAttempt<SourcePatch>
        ) async throws -> PreparedWorkspacePublishedUpdate,
        refresh: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspaceBranchReference
        ) async throws -> WorkspaceBranchReference,
        select: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspaceBranch
        ) async throws -> WorkspaceBranchReference
    ) {
        self.preparePublishedUpdate = preparePublishedUpdate
        self.refresh = refresh
        self.select = select
    }
}

extension WorkspaceReferenceUpdateClient: DependencyKey {
    public static var liveValue: Self { .unconfigured }
    public static var testValue: Self { .unconfigured }

    private static let unconfigured = Self(
        preparePublishedUpdate: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        refresh: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        select: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() }
    )
}

private struct WorkspaceReferenceUpdateUnavailable: Error {}
