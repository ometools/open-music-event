import Foundation

public struct SourcePatch: Codable, Equatable, Sendable {
    public var fileChanges: [SourcePatchFileChange]

    public init(fileChanges: [SourcePatchFileChange] = []) {
        self.fileChanges = fileChanges
    }

    public var isEmpty: Bool {
        fileChanges.isEmpty
    }
}

public struct SourcePatchAttribution: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { filePath }

    public var filePath: String
    public var recordChangeIDs: [SourceRecordChange.ID]

    public init(
        filePath: String,
        recordChangeIDs: [SourceRecordChange.ID]
    ) {
        self.filePath = filePath
        self.recordChangeIDs = recordChangeIDs
    }
}

public struct SourcePatchFileChange: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case added
        case modified
        case deleted
    }

    public var id: String { path }

    public var path: String
    public var kind: Kind
    public var oldContents: Data?
    public var newContents: Data?

    public init(
        path: String,
        kind: Kind,
        oldContents: Data? = nil,
        newContents: Data? = nil
    ) {
        self.path = path
        self.kind = kind
        self.oldContents = oldContents
        self.newContents = newContents
    }
}
