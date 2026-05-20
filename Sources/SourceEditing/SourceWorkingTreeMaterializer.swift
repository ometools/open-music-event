import Dependencies
import Foundation

public struct SourceWorkingTree: Equatable, Sendable {
    public var originalRepositoryURL: URL
    public var originalURL: URL
    public var relativePath: String?
    public var workingRepositoryURL: URL
    public var workingURL: URL

    public init(
        originalRepositoryURL: URL,
        originalURL: URL,
        relativePath: String?,
        workingRepositoryURL: URL,
        workingURL: URL
    ) {
        self.originalRepositoryURL = originalRepositoryURL
        self.originalURL = originalURL
        self.relativePath = relativePath
        self.workingRepositoryURL = workingRepositoryURL
        self.workingURL = workingURL
    }
}

public struct SourceWorkingTreeMaterializer: Sendable {
    public var materialize: @Sendable (
        _ sourceRepositoryURL: URL,
        _ relativePath: String?
    ) throws -> SourceWorkingTree

    public init(
        materialize: @escaping @Sendable (
            _ sourceRepositoryURL: URL,
            _ relativePath: String?
        ) throws -> SourceWorkingTree
    ) {
        self.materialize = materialize
    }
}

public extension SourceWorkingTreeMaterializer {
    static func live(
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory
    ) -> Self {
        Self { sourceRepositoryURL, relativePath in
            @Dependency(\.uuid) var uuid

            let fileManager = FileManager.default
            let sourceRepositoryURL = sourceRepositoryURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: sourceRepositoryURL.path,
                isDirectory: &isDirectory
            ) else {
                throw SourceWorkingTreeMaterializerError.sourceRepositoryMissing(sourceRepositoryURL)
            }
            guard isDirectory.boolValue else {
                throw SourceWorkingTreeMaterializerError.sourceRepositoryNotDirectory(sourceRepositoryURL)
            }

            let relativePath = try normalizedRelativePath(relativePath)
            let workingRepositoryURL = temporaryDirectoryURL
                .appending(path: "SourceWorkingTree-\(uuid().uuidString)")
                .standardizedFileURL
            try fileManager.copyItem(at: sourceRepositoryURL, to: workingRepositoryURL)

            let originalURL = if let relativePath {
                sourceRepositoryURL.appending(relativePath: relativePath)
            } else {
                sourceRepositoryURL
            }
            let workingURL = if let relativePath {
                workingRepositoryURL.appending(relativePath: relativePath)
            } else {
                workingRepositoryURL
            }
            return SourceWorkingTree(
                originalRepositoryURL: sourceRepositoryURL,
                originalURL: originalURL,
                relativePath: relativePath,
                workingRepositoryURL: workingRepositoryURL,
                workingURL: workingURL
            )
        }
    }
}

public extension DependencyValues {
    var sourceWorkingTreeMaterializer: SourceWorkingTreeMaterializer {
        get { self[SourceWorkingTreeMaterializerKey.self] }
        set { self[SourceWorkingTreeMaterializerKey.self] = newValue }
    }
}

public enum SourceWorkingTreeMaterializerError: Equatable, Error, Sendable {
    case invalidRelativePath(String)
    case sourceRepositoryMissing(URL)
    case sourceRepositoryNotDirectory(URL)
}

private enum SourceWorkingTreeMaterializerKey: DependencyKey {
    static var liveValue: SourceWorkingTreeMaterializer {
        .live()
    }

    static var testValue: SourceWorkingTreeMaterializer {
        .live()
    }
}

private func normalizedRelativePath(_ relativePath: String?) throws -> String? {
    guard let relativePath else { return nil }

    let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard !trimmed.hasPrefix("/") else {
        throw SourceWorkingTreeMaterializerError.invalidRelativePath(relativePath)
    }

    let components = trimmed
        .split(separator: "/", omittingEmptySubsequences: true)
        .map(String.init)
    guard !components.isEmpty else { return nil }
    guard !components.contains("."), !components.contains("..") else {
        throw SourceWorkingTreeMaterializerError.invalidRelativePath(relativePath)
    }

    return components.joined(separator: "/")
}

private extension URL {
    func appending(relativePath: String?) -> URL {
        guard let relativePath else { return standardizedFileURL }

        return relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(self) { url, component in
                url.appending(path: String(component))
            }
            .standardizedFileURL
    }
}
