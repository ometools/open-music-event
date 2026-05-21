import Dependencies
import Foundation

public struct SourcePatchApplier: Sendable {
    public var apply: @Sendable (
        _ patch: SourcePatch,
        _ repositoryURL: URL
    ) throws -> Void

    public init(
        apply: @escaping @Sendable (
            _ patch: SourcePatch,
            _ repositoryURL: URL
        ) throws -> Void
    ) {
        self.apply = apply
    }
}

public extension SourcePatchApplier {
    static var live: Self {
        Self { patch, repositoryURL in
            let fileManager = FileManager.default
            let rootURL = repositoryURL.standardizedFileURL
            let operations = try patch.fileChanges.map { change in
                try SourcePatchApplyOperation(
                    change: change,
                    rootURL: rootURL,
                    fileManager: fileManager
                )
            }

            for operation in operations {
                try operation.apply(fileManager: fileManager)
            }
        }
    }
}

public extension DependencyValues {
    var sourcePatchApplier: SourcePatchApplier {
        get { self[SourcePatchApplierKey.self] }
        set { self[SourcePatchApplierKey.self] = newValue }
    }
}

public enum SourcePatchApplierError: Equatable, Error, Sendable {
    case fileAlreadyExists(path: String)
    case fileMissing(path: String)
    case invalidPatchPath(String)
    case missingNewContents(path: String)
    case missingOldContents(path: String)
    case staleFile(path: String)
}

private enum SourcePatchApplierKey: DependencyKey {
    static var liveValue: SourcePatchApplier {
        .live
    }

    static var testValue: SourcePatchApplier {
        .live
    }
}

private enum SourcePatchApplyOperation {
    case remove(path: String, url: URL)
    case write(path: String, url: URL, contents: Data)

    init(
        change: SourcePatchFileChange,
        rootURL: URL,
        fileManager: FileManager
    ) throws {
        let url = try fileURL(for: change.path, under: rootURL)

        switch change.kind {
        case .added:
            guard let newContents = change.newContents else {
                throw SourcePatchApplierError.missingNewContents(path: change.path)
            }
            guard !fileManager.fileExists(atPath: url.path) else {
                throw SourcePatchApplierError.fileAlreadyExists(path: change.path)
            }
            self = .write(path: change.path, url: url, contents: newContents)

        case .modified:
            guard let oldContents = change.oldContents else {
                throw SourcePatchApplierError.missingOldContents(path: change.path)
            }
            guard let newContents = change.newContents else {
                throw SourcePatchApplierError.missingNewContents(path: change.path)
            }
            try Self.requireCurrentContents(
                oldContents,
                at: url,
                path: change.path,
                fileManager: fileManager
            )
            self = .write(path: change.path, url: url, contents: newContents)

        case .deleted:
            guard let oldContents = change.oldContents else {
                throw SourcePatchApplierError.missingOldContents(path: change.path)
            }
            try Self.requireCurrentContents(
                oldContents,
                at: url,
                path: change.path,
                fileManager: fileManager
            )
            self = .remove(path: change.path, url: url)
        }
    }

    func apply(fileManager: FileManager) throws {
        switch self {
        case let .remove(_, url):
            try fileManager.removeItem(at: url)

        case let .write(_, url, contents):
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, options: .atomic)
        }
    }

    private static func requireCurrentContents(
        _ expectedContents: Data,
        at url: URL,
        path: String,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw SourcePatchApplierError.fileMissing(path: path)
        }

        guard try Data(contentsOf: url) == expectedContents else {
            throw SourcePatchApplierError.staleFile(path: path)
        }
    }
}

private func fileURL(for path: String, under rootURL: URL) throws -> URL {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.hasPrefix("/")
    else {
        throw SourcePatchApplierError.invalidPatchPath(path)
    }

    let components = trimmed
        .split(separator: "/", omittingEmptySubsequences: true)
        .map(String.init)
    guard components.joined(separator: "/") == trimmed,
          !components.contains("."),
          !components.contains("..")
    else {
        throw SourcePatchApplierError.invalidPatchPath(path)
    }

    return components.reduce(rootURL.standardizedFileURL) { url, component in
        url.appending(path: component)
    }
    .standardizedFileURL
}
