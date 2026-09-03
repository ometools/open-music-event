import ComposableWorkspace
import Dependencies
import SourceEditing

public struct PreparedWorkspaceReferenceUpdate: Sendable {
    public var apply: @Sendable (WorkspaceProposal) async throws -> WorkspaceEditingContext

    public init(
        apply: @escaping @Sendable (WorkspaceProposal) async throws -> WorkspaceEditingContext
    ) {
        self.apply = apply
    }
}

public struct PreparedWorkspacePublishedUpdate: Sendable {
    public var apply: @Sendable (
        WorkspaceBranchReference
    ) async throws -> WorkspaceEditingContext

    public init(
        apply: @escaping @Sendable (
            WorkspaceBranchReference
        ) async throws -> WorkspaceEditingContext
    ) {
        self.apply = apply
    }
}

/// The proposed snapshot is already mounted locally, but its durable main-database context still
/// needs repair. Publication has succeeded and callers should expose `mountedContext` immediately.
public struct WorkspaceReferenceUpdateIncomplete: Error, Equatable, Sendable {
    public var mountedContext: WorkspaceEditingContext
    public var message: String

    public init(mountedContext: WorkspaceEditingContext, message: String) {
        self.mountedContext = mountedContext
        self.message = message
    }
}

/// Database-layer context installation. Preparing a publication replacement happens before the
/// PDS write; applying it happens afterward and is safe to repair independently.
public struct WorkspaceReferenceUpdateClient: Sendable {
    public var preparePublication: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspaceProposalAttempt<SourcePatch>
    ) async throws -> PreparedWorkspaceReferenceUpdate
    public var preparePublishedUpdate: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspacePublicationAttempt<SourcePatch>
    ) async throws -> PreparedWorkspacePublishedUpdate
    public var refresh: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspaceEditingContext
    ) async throws -> WorkspaceEditingContext
    public var select: @Sendable (
        SourceWorkspaceResource,
        SourceWorkspace.ID,
        WorkspaceContextSelection
    ) async throws -> WorkspaceEditingContext

    public init(
        preparePublication: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspaceProposalAttempt<SourcePatch>
        ) async throws -> PreparedWorkspaceReferenceUpdate,
        preparePublishedUpdate: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspacePublicationAttempt<SourcePatch>
        ) async throws -> PreparedWorkspacePublishedUpdate,
        refresh: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspaceEditingContext
        ) async throws -> WorkspaceEditingContext,
        select: @escaping @Sendable (
            SourceWorkspaceResource,
            SourceWorkspace.ID,
            WorkspaceContextSelection
        ) async throws -> WorkspaceEditingContext
    ) {
        self.preparePublication = preparePublication
        self.preparePublishedUpdate = preparePublishedUpdate
        self.refresh = refresh
        self.select = select
    }
}

extension WorkspaceReferenceUpdateClient: DependencyKey {
    public static var liveValue: Self { .unconfigured }
    public static var testValue: Self { .unconfigured }

    private static let unconfigured = Self(
        preparePublication: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        preparePublishedUpdate: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        refresh: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        select: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() }
    )
}

private struct WorkspaceReferenceUpdateUnavailable: Error {}
