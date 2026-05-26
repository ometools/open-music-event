import Dependencies
import Foundation

public struct SourcePatchPublishRequest: Equatable, Sendable {
    public var description: String?
    public var location: SourcePatchLocation
    public var patch: SourcePatch

    public init(
        description: String? = nil,
        location: SourcePatchLocation,
        patch: SourcePatch
    ) {
        self.description = description
        self.location = location
        self.patch = patch
    }
}

public struct PreparedSourcePatch: Equatable, Sendable {
    public var request: SourcePatchPublishRequest
    public var workingTree: SourceWorkingTree

    public init(
        request: SourcePatchPublishRequest,
        workingTree: SourceWorkingTree
    ) {
        self.request = request
        self.workingTree = workingTree
    }
}

public struct SourcePatchPublication: Equatable, Sendable {
    public var sourceChangeURL: URL?
    public var workingTree: SourceWorkingTree?

    public init(
        sourceChangeURL: URL? = nil,
        workingTree: SourceWorkingTree? = nil
    ) {
        self.sourceChangeURL = sourceChangeURL
        self.workingTree = workingTree
    }
}

public struct SourcePatchPublisher: Sendable {
    public var publish: @Sendable (SourcePatchPublishRequest) async throws -> SourcePatchPublication

    public init(
        publish: @escaping @Sendable (SourcePatchPublishRequest) async throws -> SourcePatchPublication
    ) {
        self.publish = publish
    }
}

public extension SourcePatchPublisher {
    static func live(
        cleanupWorkingTree: Bool = true,
        publishPreparedPatch: @escaping @Sendable (PreparedSourcePatch) async throws -> SourcePatchPublication
    ) -> Self {
        Self { request in
            @Dependency(\.sourcePatchApplier) var sourcePatchApplier
            @Dependency(\.sourceWorkingTreeMaterializer) var sourceWorkingTreeMaterializer

            let workingTree = try sourceWorkingTreeMaterializer.materialize(
                request.location.repositoryURL,
                request.location.relativePath
            )
            defer {
                if cleanupWorkingTree {
                    try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
                }
            }

            try sourcePatchApplier.apply(
                request.patch,
                workingTree.workingRepositoryURL
            )

            return try await publishPreparedPatch(
                PreparedSourcePatch(
                    request: request,
                    workingTree: workingTree
                )
            )
        }
    }

    static var preparedWorkingTree: Self {
        .live(cleanupWorkingTree: false) { preparedPatch in
            SourcePatchPublication(workingTree: preparedPatch.workingTree)
        }
    }

    static var unconfigured: Self {
        Self { _ in
            throw SourcePatchPublisherError.notConfigured
        }
    }
}

public extension DependencyValues {
    var sourcePatchPublisher: SourcePatchPublisher {
        get { self[SourcePatchPublisherKey.self] }
        set { self[SourcePatchPublisherKey.self] = newValue }
    }
}

public enum SourcePatchPublisherError: Equatable, Error, Sendable {
    case notConfigured
}

private enum SourcePatchPublisherKey: DependencyKey {
    static var liveValue: SourcePatchPublisher {
        .unconfigured
    }

    static var testValue: SourcePatchPublisher {
        .unconfigured
    }
}
