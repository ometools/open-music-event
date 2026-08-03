import Dependencies
import OpenMusicEventSourceClone
import SourceControlClient

/// Fetches remote refs into the durable repository without changing HEAD, the reference database,
/// or writable application rows. Reconciliation remains an explicit Workspace transition.
public struct SourceWorkspaceFetchClient: Sendable {
    public var fetch: @Sendable (SourceWorkspaceResource) async throws -> Void

    public init(
        fetch: @escaping @Sendable (SourceWorkspaceResource) async throws -> Void
    ) {
        self.fetch = fetch
    }
}

public extension SourceWorkspaceFetchClient {
    static var live: Self {
        Self { resource in
            @Dependency(\.sourceControl) var sourceControl
            @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
            let reference = try TangledRepositoryReference(
                sourceReference: resource.workspace.repository
            )
            let target = try await reference.resolvedTangledRepositoryTarget()
            let credentials = try await tangledSSHCredentials.readyCredentials(
                target.knotHost
            )
            let repository = try await sourceControl.open(resource.repositoryURL)
            try await sourceControl.fetch(
                reference.sourceControlFetchRequest(
                    repository: repository,
                    credentials: credentials
                )
            )
        }
    }
}

extension SourceWorkspaceFetchClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { Self { _ in } }
}
