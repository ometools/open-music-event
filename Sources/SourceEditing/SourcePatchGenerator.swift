import Dependencies
import Foundation

public struct SourcePatchSource<SourceValue: Sendable>: Sendable {
    public var repositoryURL: URL
    public var relativePath: String?
    public var value: SourceValue

    public init(
        repositoryURL: URL,
        relativePath: String? = nil,
        value: SourceValue
    ) {
        self.repositoryURL = repositoryURL
        self.relativePath = relativePath
        self.value = value
    }
}

public struct SourcePatchGenerator<Request: Sendable>: Sendable {
    public var generate: @Sendable (Request) async throws -> SourcePatch

    public init(
        generate: @escaping @Sendable (Request) async throws -> SourcePatch
    ) {
        self.generate = generate
    }
}

public extension SourcePatchGenerator {
    static func live<SourceValue: Sendable>(
        resolve: @escaping @Sendable (Request) async throws -> SourcePatchSource<SourceValue>,
        rewrite: @escaping @Sendable (SourceValue, URL) throws -> Void
    ) -> Self {
        Self { request in
            @Dependency(\.sourceWorkingTreeMaterializer) var sourceWorkingTreeMaterializer
            @Dependency(\.sourcePatchDiffer) var sourcePatchDiffer

            let source = try await resolve(request)
            let workingTree = try sourceWorkingTreeMaterializer.materialize(
                source.repositoryURL,
                source.relativePath
            )
            defer {
                try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
            }

            try rewrite(source.value, workingTree.workingURL)

            return try sourcePatchDiffer.diff(
                workingTree.originalURL,
                workingTree.workingURL,
                workingTree.originalRepositoryURL
            )
        }
    }
}

public enum SourcePatchGeneratorKey<Request: Sendable>: DependencyKey {
    public static var liveValue: SourcePatchGenerator<Request> {
        .unconfigured(requestType: Request.self)
    }

    public static var testValue: SourcePatchGenerator<Request> {
        .unconfigured(requestType: Request.self)
    }
}

public enum SourcePatchGeneratorError: Equatable, Error, Sendable {
    case notConfigured(requestType: String)
}

public extension SourcePatchGenerator {
    static func unconfigured(requestType: Any.Type = Request.self) -> Self {
        Self { _ in
            throw SourcePatchGeneratorError.notConfigured(
                requestType: String(reflecting: requestType)
            )
        }
    }
}
