import ComposableWorkspace
import Dependencies
import Foundation

/// Performs the one authoritative transition from an authorized source locator to an editable
/// workspace resource.
///
/// The implementation owns clone/open, complete source installation, reference construction, and
/// the exact checked-out Git revision. Callers do not perform any of those steps independently.
public struct SourceWorkspacePreparationClient: Sendable {
    public var prepare: @Sendable (
        _ workspace: SourceWorkspace
    ) async throws -> WorkspaceSession<SourceWorkspaceResource>

    public init(
        prepare: @escaping @Sendable (
            _ workspace: SourceWorkspace
        ) async throws -> WorkspaceSession<SourceWorkspaceResource>
    ) {
        self.prepare = prepare
    }
}

extension SourceWorkspacePreparationClient: DependencyKey {
    public static var liveValue: Self {
        Self { _ in throw SourceWorkspacePreparationUnavailable() }
    }

    public static var testValue: Self { liveValue }
}

private struct SourceWorkspacePreparationUnavailable: Error {}
