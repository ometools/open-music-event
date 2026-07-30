import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SQLiteData
import TangledLexicon
import TangledXRPC
import XRPCClient

public struct TangledWorkspaceBootstrapClient: Sendable {
    public var bootstrap: @Sendable (TangledWorkspaceBootstrapRequest) async throws -> TangledWorkspaceBootstrapResult

    public init(
        bootstrap: @escaping @Sendable (TangledWorkspaceBootstrapRequest) async throws -> TangledWorkspaceBootstrapResult
    ) {
        self.bootstrap = bootstrap
    }
}

public struct TangledWorkspaceBootstrapRequest: Equatable, Sendable {
    public var sourceBaselineID: SourceBaselineRecord.ID
    public var repositoryName: String
    public var description: String?
    public var knotHost: String
    public var defaultBranch: String

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        repositoryName: String,
        description: String? = nil,
        knotHost: String = "tangled.org",
        defaultBranch: String = "main"
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.repositoryName = repositoryName
        self.description = description
        self.knotHost = knotHost
        self.defaultBranch = defaultBranch
    }
}

public struct TangledWorkspaceBootstrapResult: Equatable, Sendable {
    public var sourceBaselineID: SourceBaselineRecord.ID
    public var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance
    public var repositoryReference: TangledRepositoryReference
    public var repoDID: String

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance,
        repositoryReference: TangledRepositoryReference,
        repoDID: String
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.sourceProvenance = sourceProvenance
        self.repositoryReference = repositoryReference
        self.repoDID = repoDID
    }
}

public struct TangledRepositoryName: Equatable, Sendable {
    public var name: String
    public var rkey: String

    public init(_ rawValue: String) throws {
        let name = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .droppingGitSuffix
        try Self.validate(name)
        self.name = name
        self.rkey = name.lowercased()
    }

    private static func validate(_ name: String) throws {
        guard !name.isEmpty else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
        guard name.count <= 100 else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
        guard name.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
        guard !name.contains("/") && !name.contains("\\") else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
        guard !name.hasPrefix("."), !name.hasSuffix("."), !name.contains("..") else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
        guard name.caseInsensitiveCompare("self") != .orderedSame else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(name)
        }
    }
}

public struct TangledCreateRepositoryInput: Encodable, Equatable, Sendable {
    public var rkey: String
    public var name: String
    public var defaultBranch: String?
    public var source: String?
    public var repoDid: String?

    public init(
        rkey: String,
        name: String,
        defaultBranch: String? = nil,
        source: String? = nil,
        repoDid: String? = nil
    ) {
        self.rkey = rkey
        self.name = name
        self.defaultBranch = defaultBranch
        self.source = source
        self.repoDid = repoDid
    }
}

public struct TangledCreateRepositoryOutput: Decodable, Equatable, Sendable {
    public var repoDid: String?

    public init(repoDid: String? = nil) {
        self.repoDid = repoDid
    }
}

public struct TangledCreateRepositoryRequest: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { "sh.tangled.repo.create" }
    public static var type: XRPC.RequestType { .procedure }

    public typealias Input = TangledCreateRepositoryInput
    public typealias Output = TangledCreateRepositoryOutput
    public typealias Parameters = Never

    public var input: TangledCreateRepositoryInput
    public var knotHost: ATProto.PDSHost
    public var authorizationPolicy: XRPC.AuthorizationPolicy

    public init(
        input: TangledCreateRepositoryInput,
        knotHost: ATProto.PDSHost,
        authorizationPolicy: XRPC.AuthorizationPolicy? = nil
    ) {
        self.input = input
        self.knotHost = knotHost
        self.authorizationPolicy = authorizationPolicy ?? .required(
            TangledOAuthRequirements.repositoryBootstrapAuthRequirement(knotHost: knotHost.rawValue)
        )
    }

    public var routing: XRPC.Routing {
        XRPC.Routing(
            unauthenticated: .host(knotHost),
            authenticated: .host(knotHost)
        )
    }
}

public enum TangledWorkspaceBootstrapError: Equatable, Error, Sendable {
    case invalidDefaultBranch(String)
    case invalidKnotHost(String)
    case invalidRepositoryName(String)
    case missingCreatedRepositoryDID
    case sourceBaselineHasNoEvents(SourceBaselineRecord.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case sourceBaselineNotLocal(SourceBaselineRecord.ID)
}

public extension TangledOAuthRequirements {
    static func repositoryBootstrapAuthRequirement(knotHost _: String) -> OAuth.AuthRequirement {
        OAuth.AuthRequirement(
            permissions: [
                repositoryCreatePermission,
                repositoryRecordCreatePermission,
                OpenMusicEventOAuth.sourceRecordCreatePermission,
                OpenMusicEventOAuth.sourceRecordUpdatePermission,
                publicKeyCreatePermission,
            ]
        )
    }
}

public extension TangledWorkspaceBootstrapClient {
    static var live: Self {
        Self { request in
            @Dependency(\.date.now) var now
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.getDefaultSession) var getDefaultSession
            @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
            @Dependency(\.sourceControl) var sourceControl
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
            @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
            @Dependency(\.uuid) var uuid
            @Dependency(XRPC.Client.self) var xrpcClient

            let repositoryName = try TangledRepositoryName(request.repositoryName)
            let knotHost = try validatedKnotHost(request.knotHost)
            let defaultBranch = try validatedBranch(request.defaultBranch)
            let requirement = TangledOAuthRequirements
                .repositoryBootstrapAuthRequirement(knotHost: knotHost.rawValue)
            try await authorizationBroker.authorize(requirement)

            let oldSourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(request.sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let oldSourceBaseline else {
                throw TangledWorkspaceBootstrapError
                    .sourceBaselineNotFound(request.sourceBaselineID)
            }
            guard oldSourceBaseline.sourceKind == .local else {
                throw TangledWorkspaceBootstrapError
                    .sourceBaselineNotLocal(request.sourceBaselineID)
            }
            let organizerID = try await canonicalOrganizerID(
                forSourceBaselineID: oldSourceBaseline.id
            )

            let localSourceProvenance = oldSourceBaseline.sourceProvenance
            let localRepositoryURL = try sourceRepositoryStorage.repositoryURL(
                localSourceProvenance
            )

            let createRepositoryOutput = try await xrpcClient.run(
                TangledCreateRepositoryRequest(
                    input: TangledCreateRepositoryInput(
                        rkey: repositoryName.rkey,
                        name: repositoryName.rkey,
                        defaultBranch: defaultBranch
                    ),
                    knotHost: knotHost,
                    authorizationPolicy: .required(requirement)
                )
            )
            guard let repoDID = createRepositoryOutput.repoDid, !repoDID.isEmpty else {
                throw TangledWorkspaceBootstrapError.missingCreatedRepositoryDID
            }
            guard let repoDIDValue = DID(repoDID) else {
                throw TangledWorkspaceBootstrapError.missingCreatedRepositoryDID
            }

            let session = getDefaultSession()
            let ownerDID = session.accountID.rawValue.description
            let repositoryReference = TangledRepositoryReference(
                host: knotHost.rawValue,
                owner: ownerDID,
                repository: repositoryName.rkey
            )
            let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
                kind: .tangled,
                reference: repositoryReference.normalizedReference,
                ref: defaultBranch
            )

            _ = try await xrpcClient.run(
                TangledRepositoryRequests.createRecord(
                    repo: ownerDID,
                    collection: .repo,
                    rkey: ATProto.Record.Key(rawValue: repositoryName.rkey),
                    record: TangledRepoRecord(
                        name: repositoryName.rkey,
                        knot: knotHost.rawValue,
                        description: request.description?.nonEmptyTrimmed,
                        repoDid: repoDIDValue,
                        createdAt: iso8601String(now)
                    ),
                    authorizationPolicy: .required(requirement)
                )
            )

            let credentials = try await tangledSSHCredentials.readyCredentials(knotHost)
            let checkoutURL = SourceRepositoryStorageClient
                .temporaryDownloadURL(uuid: uuid())
            do {
                _ = try await sourceControl.clone(
                    repositoryReference.sourceControlCloneRequest(
                        repoDID: repoDID,
                        destinationURL: checkoutURL,
                        ref: "HEAD",
                        credentials: credentials
                    )
                )
                let stagedPaths = try SourceRepositoryTreeCopier.copyContents(
                    from: localRepositoryURL,
                    to: checkoutURL
                )
                let repository = try await sourceControl.open(checkoutURL)
                try await sourceControl.stage(
                    StageRequest(repository: repository, paths: stagedPaths)
                )
                _ = try await sourceControl.commit(
                    CommitRequest(
                        repository: repository,
                        message: "Initial Open Music Event source",
                        author: Author(
                            name: "Open Music Event",
                            email: "noreply@openmusicevent.app"
                        )
                    )
                )
                try await sourceControl.push(
                    PushRequest(
                        repository: repository,
                        localBranch: BranchName(rawValue: defaultBranch),
                        remoteBranch: BranchName(rawValue: defaultBranch),
                        credentials: repositoryReference
                            .sourceControlCredentials(credentials)
                    )
                )
                _ = try await xrpcClient.putRecord(
                    repo: organizerID.description,
                    collection: OpenMusicEvent.SourceRecord.nsid,
                    rkey: ATProto.Record.Key(
                        rawValue: OpenMusicEvent.SourceRecord.canonicalRecordKey
                    ),
                    record: OpenMusicEvent.SourceRecord(
                        kind: .tangled,
                        reference: repositoryReference.normalizedReference,
                        ref: defaultBranch,
                        createdAt: iso8601String(now)
                    ),
                    authorizationPolicy: .required(requirement)
                )
                let storedRepositoryURL = try sourceRepositoryStorage.store(
                    checkoutURL,
                    sourceProvenance
                )
                try await prepareReferenceDatabase(
                    repositoryURL: storedRepositoryURL,
                    sourceProvenance: sourceProvenance,
                    oldSourceBaselineID: oldSourceBaseline.id,
                    importedAt: now
                )

                let newSourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
                return TangledWorkspaceBootstrapResult(
                    sourceBaselineID: newSourceBaselineID,
                    sourceProvenance: sourceProvenance,
                    repositoryReference: repositoryReference,
                    repoDID: repoDID
                )
            } catch {
                try? FileManager.default.removeItem(at: checkoutURL)
                throw error
            }
        }
    }
}

private func canonicalOrganizerID(
    forSourceBaselineID sourceBaselineID: SourceBaselineRecord.ID
) async throws -> OME.Organizer.ID {
    @Dependency(\.defaultDatabase) var database

    let organizerID = try await database.read { db in
        try EventSourceProvenanceRecord
            .where { $0.sourceBaselineID.eq(sourceBaselineID) }
            .fetchOne(db)?
            .id
            .organizerID
    }
    guard let organizerID else {
        throw TangledWorkspaceBootstrapError.sourceBaselineHasNoEvents(sourceBaselineID)
    }
    return organizerID
}

private struct SourceRepositoryTreeCopier {
    static func copyContents(from sourceURL: URL, to destinationURL: URL) throws -> [RepositoryPath] {
        let fileManager = FileManager.default
        let sourceRoot = sourceURL.standardizedFileURL
        let destinationRoot = destinationURL.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var stagedPaths: [RepositoryPath] = []
        for case let sourceFileURL as URL in enumerator {
            let relativePath = try relativePath(of: sourceFileURL, under: sourceRoot)
            let values = try sourceFileURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            let isDirectory = values.isDirectory == true
            guard shouldCopy(relativePath) else {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            let destinationFileURL = destinationRoot.appending(path: relativePath)
            if isDirectory {
                try fileManager.createDirectory(
                    at: destinationFileURL,
                    withIntermediateDirectories: true
                )
                continue
            }

            try fileManager.createDirectory(
                at: destinationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationFileURL.path()) {
                try fileManager.removeItem(at: destinationFileURL)
            }
            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
            stagedPaths.append(RepositoryPath(rawValue: relativePath))
        }
        return stagedPaths.sorted { $0.rawValue < $1.rawValue }
    }

    private static func shouldCopy(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let firstComponent = components.first else { return false }
        guard firstComponent != ".git", firstComponent != ".jj" else { return false }
        guard relativePath != ".ome/reference.sqlite",
              relativePath != ".ome/reference.sqlite-shm",
              relativePath != ".ome/reference.sqlite-wal"
        else { return false }
        guard !relativePath.hasSuffix("/.DS_Store"), relativePath != ".DS_Store" else {
            return false
        }
        return true
    }

    private static func relativePath(of url: URL, under root: URL) throws -> String {
        let rootPath = root.path().hasSuffix("/") ? root.path() : root.path() + "/"
        let filePath = url.standardizedFileURL.path()
        guard filePath.hasPrefix(rootPath) else {
            throw TangledWorkspaceBootstrapError.invalidRepositoryName(filePath)
        }
        return String(filePath.dropFirst(rootPath.count))
    }
}

private func prepareReferenceDatabase(
    repositoryURL: URL,
    sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance,
    oldSourceBaselineID: SourceBaselineRecord.ID,
    importedAt: Date
) async throws {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase

    let provenanceRecords = try await database.read { db in
        try EventSourceProvenanceRecord
            .where { $0.sourceBaselineID.eq(oldSourceBaselineID) }
            .fetchAll(db)
    }
    guard let organizerID = provenanceRecords.first?.id.organizerID else {
        throw TangledWorkspaceBootstrapError.sourceBaselineHasNoEvents(oldSourceBaselineID)
    }

    let sourceResult = try OpenMusicEventSourceRepositoryFileTree()
        .read(from: repositoryURL)
    let source = try sourceResult.output.requiredValue
    let insertion = try OME.SourceDatabaseInsertion(
        OME.SourceDatabaseInsertion.Configuration(
            source: source,
            organizerID: organizerID,
            sourceProvenance: sourceProvenance,
            sourceRootURL: repositoryURL
        )
    )
    try await insertion.prepareSourceReferenceDatabases()

    let newSourceBaseline = SourceBaselineRecord(
        source: sourceProvenance,
        databaseFileName: URL(
            fileURLWithPath: try sourceReferenceDatabase.url(sourceProvenance).path()
        )
        .lastPathComponent,
        importedAt: importedAt
    )
    let newWorkspace = EditingWorkspaceRecord(
        teamSourceBaseline: newSourceBaseline,
        organizerID: organizerID
    )
    let oldWorkspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: oldSourceBaselineID)
    let newWorkspaceID = newWorkspace.id

    try await database.write { db in
        try SourceBaselineRecord.insert {
            newSourceBaseline
        } onConflict: {
            $0.id
        }
        .execute(db)
        try EditingWorkspaceRecord.insert {
            newWorkspace
        } onConflict: {
            $0.id
        }
        .execute(db)

        try db.execute(
            sql: #"""
            UPDATE "eventSourceProvenances"
            SET "sourceBaselineID" = ?,
                "sourceKind" = ?,
                "sourceReference" = ?,
                "ref" = ?
            WHERE "sourceBaselineID" = ?
            """#,
            arguments: [
                newSourceBaseline.id.rawValue,
                sourceProvenance.kind.rawValue,
                sourceProvenance.reference,
                sourceProvenance.ref,
                oldSourceBaselineID.rawValue,
            ]
        )
        try db.execute(
            sql: #"""
            UPDATE "eventEditingWorkspaces"
            SET "workspaceID" = ?
            WHERE "workspaceID" = ?
            """#,
            arguments: [
                newWorkspaceID.rawValue,
                oldWorkspaceID.rawValue,
            ]
        )

        if oldWorkspaceID != newWorkspaceID {
            let oldWorkspaceLinkCount = try EventEditingWorkspaceRecord
                .where { $0.workspaceID.eq(oldWorkspaceID) }
                .fetchCount(db)
            if oldWorkspaceLinkCount == 0 {
                try EditingWorkspaceRecord
                    .where { $0.id.eq(oldWorkspaceID) }
                    .delete()
                    .execute(db)
            }
        }

        if oldSourceBaselineID != newSourceBaseline.id {
            let oldBaselineProvenanceCount = try EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(oldSourceBaselineID) }
                .fetchCount(db)
            let oldBaselineWorkspaceCount = try EditingWorkspaceRecord
                .where { $0.sourceBaselineID.eq(oldSourceBaselineID) }
                .fetchCount(db)
            if oldBaselineProvenanceCount == 0 && oldBaselineWorkspaceCount == 0 {
                try SourceBaselineRecord
                    .where { $0.id.eq(oldSourceBaselineID) }
                    .delete()
                    .execute(db)
            }
        }
    }
}

private func validatedKnotHost(_ rawValue: String) throws -> ATProto.PDSHost {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.range(of: #"\s"#, options: .regularExpression) == nil else {
        throw TangledWorkspaceBootstrapError.invalidKnotHost(rawValue)
    }
    return ATProto.PDSHost(trimmed)
}

private func validatedBranch(_ rawValue: String) throws -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.contains(" "),
          !trimmed.contains(".."),
          !trimmed.hasPrefix("/"),
          !trimmed.hasSuffix("/"),
          !trimmed.hasSuffix(".")
    else {
        throw TangledWorkspaceBootstrapError.invalidDefaultBranch(rawValue)
    }
    return trimmed
}

private func iso8601String(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}


private extension String {
    var droppingGitSuffix: String {
        if hasSuffix(".git") {
            return String(dropLast(4))
        }
        return self
    }

    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum TangledWorkspaceBootstrapClientKey: DependencyKey {
    static var liveValue: TangledWorkspaceBootstrapClient {
        .live
    }

    static var testValue: TangledWorkspaceBootstrapClient {
        TangledWorkspaceBootstrapClient { _ in
            throw TangledWorkspaceBootstrapError.missingCreatedRepositoryDID
        }
    }
}

public extension DependencyValues {
    var tangledWorkspaceBootstrap: TangledWorkspaceBootstrapClient {
        get { self[TangledWorkspaceBootstrapClientKey.self] }
        set { self[TangledWorkspaceBootstrapClientKey.self] = newValue }
    }
}
