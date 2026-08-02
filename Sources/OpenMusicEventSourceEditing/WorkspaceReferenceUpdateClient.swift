import ComposableWorkspace
import Dependencies
import SourceEditing

/// The database-layer operation that advances OME's workspace-owned reference copy.
///
/// This seam exists because source parsing owns no SQLite insertion policy. It carries no state;
/// the durable workflow state remains in `workspacePublications`.
public struct WorkspaceReferenceUpdateClient: Sendable {
    public var advance: @Sendable (
        SourceWorkspaceDatabase,
        EditingWorkspaceRecord.ID,
        WorkspaceSubmission<SourcePatch>,
        WorkspaceProposal
    ) async throws -> Void
    public var reconcile: @Sendable (
        SourceWorkspaceDatabase,
        EditingWorkspaceRecord.ID,
        WorkspaceReconciliation
    ) async throws -> WorkspaceEditingLine

    public init(
        advance: @escaping @Sendable (
            SourceWorkspaceDatabase,
            EditingWorkspaceRecord.ID,
            WorkspaceSubmission<SourcePatch>,
            WorkspaceProposal
        ) async throws -> Void,
        reconcile: @escaping @Sendable (
            SourceWorkspaceDatabase,
            EditingWorkspaceRecord.ID,
            WorkspaceReconciliation
        ) async throws -> WorkspaceEditingLine
    ) {
        self.advance = advance
        self.reconcile = reconcile
    }
}

extension WorkspaceReferenceUpdateClient: DependencyKey {
    public static var liveValue: Self { .unconfigured }
    public static var testValue: Self { .unconfigured }

    private static let unconfigured = Self(
        advance: { _, _, _, _ in throw WorkspaceReferenceUpdateUnavailable() },
        reconcile: { _, _, _ in throw WorkspaceReferenceUpdateUnavailable() }
    )
}

private struct WorkspaceReferenceUpdateUnavailable: Error {}
