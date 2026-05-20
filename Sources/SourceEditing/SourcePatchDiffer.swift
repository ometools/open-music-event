import Dependencies
import Foundation

public struct SourcePatchDiffer: Sendable {
    public var diff: @Sendable (
        _ originalURL: URL,
        _ modifiedURL: URL,
        _ relativeTo: URL
    ) throws -> SourcePatch

    public init(
        diff: @escaping @Sendable (
            _ originalURL: URL,
            _ modifiedURL: URL,
            _ relativeTo: URL
        ) throws -> SourcePatch
    ) {
        self.diff = diff
    }
}

public extension SourcePatchDiffer {
    static var live: Self {
        Self { originalURL, modifiedURL, relativeTo in
            let originalURL = originalURL.standardizedFileURL
            let modifiedURL = modifiedURL.standardizedFileURL
            let relativeTo = relativeTo.standardizedFileURL
            let originalRootPath = try relativePath(of: originalURL, to: relativeTo)
            let originalFiles = try fileContentsByRelativePath(under: originalURL)
            let modifiedFiles = try fileContentsByRelativePath(under: modifiedURL)
            let paths = Set(originalFiles.keys)
                .union(modifiedFiles.keys)
                .sorted()

            let fileChanges = paths.compactMap { path -> SourcePatchFileChange? in
                let oldContents = originalFiles[path]
                let newContents = modifiedFiles[path]
                let patchPath = sourcePatchPath(
                    rootPath: originalRootPath,
                    filePath: path
                )

                switch (oldContents, newContents) {
                case (nil, nil):
                    return nil

                case (nil, let newContents?):
                    return SourcePatchFileChange(
                        path: patchPath,
                        kind: .added,
                        newContents: newContents
                    )

                case (let oldContents?, nil):
                    return SourcePatchFileChange(
                        path: patchPath,
                        kind: .deleted,
                        oldContents: oldContents
                    )

                case (let oldContents?, let newContents?):
                    guard oldContents != newContents else { return nil }
                    return SourcePatchFileChange(
                        path: patchPath,
                        kind: .modified,
                        oldContents: oldContents,
                        newContents: newContents
                    )
                }
            }

            return SourcePatch(fileChanges: fileChanges)
        }
    }
}

public extension DependencyValues {
    var sourcePatchDiffer: SourcePatchDiffer {
        get { self[SourcePatchDifferKey.self] }
        set { self[SourcePatchDifferKey.self] = newValue }
    }
}

public enum SourcePatchDifferError: Equatable, Error, Sendable {
    case urlNotContained(url: URL, rootURL: URL)
}

private enum SourcePatchDifferKey: DependencyKey {
    static var liveValue: SourcePatchDiffer {
        .live
    }

    static var testValue: SourcePatchDiffer {
        .live
    }
}

private func fileContentsByRelativePath(under rootURL: URL) throws -> [String: Data] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
        return [:]
    }

    guard isDirectory.boolValue else {
        return [
            "": try Data(contentsOf: rootURL)
        ]
    }

    guard let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return [:]
    }

    var contentsByPath: [String: Data] = [:]
    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true else { continue }

        contentsByPath[try relativePath(of: fileURL, to: rootURL)] = try Data(contentsOf: fileURL)
    }
    return contentsByPath
}

private func relativePath(of url: URL, to rootURL: URL) throws -> String {
    let urlPath = url.standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path

    if urlPath == rootPath {
        return ""
    }

    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
    guard urlPath.hasPrefix(rootPrefix) else {
        throw SourcePatchDifferError.urlNotContained(
            url: url.standardizedFileURL,
            rootURL: rootURL.standardizedFileURL
        )
    }

    return String(urlPath.dropFirst(rootPrefix.count))
}

private func sourcePatchPath(rootPath: String, filePath: String) -> String {
    [rootPath, filePath]
        .filter { !$0.isEmpty }
        .joined(separator: "/")
}
