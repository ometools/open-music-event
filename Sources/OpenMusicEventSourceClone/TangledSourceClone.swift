import ArgumentParser
import ATProto
import Crypto
import Dependencies
import Foundation
import Gzip
import HTTPClient
import Tar

public struct TangledSourceCloneCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "clone",
        abstract: "Download a Tangled source repository archive."
    )

    @Argument(help: "Tangled repository reference, such as tangled.org/core or https://tangled.org/tangled.org/core.")
    public var repository: String

    @Option(help: "Destination directory for the downloaded source tree. If omitted, a temporary directory is created.")
    public var output: String?

    @Option(help: "Git ref to download.")
    public var ref = "HEAD"

    public init() {}

    public func run() async throws {
        let repository = try TangledRepositoryReference(parsing: repository)
        let outputURL: URL
        if let output {
            outputURL = try Self.resolvedOutputURL(output)
        } else {
            @Dependency(\.uuid) var uuid
            outputURL = Self.temporaryOutputURL(uuid: uuid())
        }
        try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)

        try await TangledSourceCloner(
            repository: repository,
            ref: ref,
            outputURL: outputURL
        )
        .clone()

        print(
            "Downloaded \(repository.displayName) at \(ref) to \(outputURL.path(percentEncoded: false))"
        )
    }

    public static func resolvedOutputURL(_ output: String) throws -> URL {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw ValidationError("Output path cannot be empty.")
        }

        return URL(filePath: trimmedOutput).standardizedFileURL
    }

    public static func temporaryOutputURL(uuid: UUID) -> URL {
        TangledSourceCloner.temporaryOutputURL(uuid: uuid)
    }
}

public enum SourceRepositoryLocation: Equatable, Sendable {
    case local(URL)
    case tangled(TangledRepositoryReference)
    case tangledRepositoryURI(TangledRepositoryRecordReference)

    public init(parsing rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw ValidationError("Source cannot be empty.")
        }

        let localURL = URL(filePath: trimmedValue).standardizedFileURL
        if FileManager.default.fileExists(atPath: localURL.path(percentEncoded: false)) {
            self = .local(localURL)
            return
        }

        if trimmedValue.looksLikeLocalPath {
            throw ValidationError(
                "Local source path does not exist: \(localURL.path(percentEncoded: false))"
            )
        }

        if trimmedValue.hasPrefix("at://") {
            self = .tangledRepositoryURI(
                try TangledRepositoryRecordReference(parsing: trimmedValue)
            )
            return
        }

        do {
            self = .tangled(try TangledRepositoryReference(parsing: trimmedValue))
        } catch {
            throw ValidationError("Source must be an existing local path, Tangled repository reference, or sh.tangled.repo AT URI.")
        }
    }
}

public struct TangledRepositoryRecordReference: Equatable, Sendable {
    public var uri: ATProto.URI
    public var rkey: ATProto.Record.Key

    public init(uri: ATProto.URI) throws {
        guard uri.collection?.rawValue == "sh.tangled.repo",
              let rkey = uri.rkey
        else {
            throw ValidationError("Tangled repository AT URI must identify a sh.tangled.repo record.")
        }
        self.uri = uri
        self.rkey = rkey
    }

    public init(parsing rawValue: String) throws {
        guard let uri = ATProto.URI(rawValue) else {
            throw ValidationError("Tangled repository AT URI is invalid.")
        }
        try self.init(uri: uri)
    }

    public var normalizedReference: String {
        uri.description
    }

    public var repositoryReference: TangledRepositoryReference {
        TangledRepositoryReference(
            host: "tangled.org",
            owner: uri.authority.description,
            repository: rkey.rawValue
        )
    }

    public func resolvedOwnerDID() async throws -> String {
        switch uri.authority {
        case let .did(did):
            return did.description

        case let .handle(handle):
            do {
                @Dependency(Atmosphere.Account.Client.self) var accountClient
                let (account, _) = try await accountClient.resolveHandle(handle)
                return account.id.rawValue.description
            } catch {
                throw ValidationError("Could not resolve repository owner \(handle.rawValue) to a DID: \(error)")
            }
        }
    }
}

public struct TangledRepositoryReference: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var owner: String
    public var repository: String

    public init(host: String, port: Int? = nil, owner: String, repository: String) {
        self.host = host
        self.port = port
        self.owner = owner
        self.repository = repository
    }

    public init(sourceReference rawValue: String) throws {
        switch try SourceRepositoryLocation(parsing: rawValue) {
        case .local:
            throw ValidationError("Tangled source reference must be a Tangled repository reference or sh.tangled.repo AT URI.")

        case let .tangled(repository):
            self = repository

        case let .tangledRepositoryURI(repository):
            self = repository.repositoryReference
        }
    }

    public init(parsing rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmedValue.isEmpty else {
            throw ValidationError("Repository reference cannot be empty.")
        }
        guard !trimmedValue.hasPrefix("git@") else {
            throw ValidationError("SSH repository references are not supported. Use an HTTPS Tangled URL or owner/repo.")
        }

        if let url = URL(string: trimmedValue), let scheme = url.scheme {
            guard scheme == "http" || scheme == "https" else {
                throw ValidationError("Unsupported repository URL scheme: \(scheme). Use HTTP or HTTPS.")
            }
            guard let host = url.host(percentEncoded: false) else {
                throw ValidationError("Repository URL is missing a host.")
            }

            let components = url.pathComponents
                .filter { $0 != "/" }
            try self.init(host: host, port: url.port, pathComponents: components)
        } else {
            let components = trimmedValue
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            if components.count == 3 {
                let hostComponents = components[0].split(
                    separator: ":",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard let hostSubstring = hostComponents.first, !hostSubstring.isEmpty else {
                    throw ValidationError("Repository reference is missing a host.")
                }
                let host = String(hostSubstring)
                let port: Int?
                if hostComponents.count == 2 {
                    port = try Self.port(String(hostComponents[1]))
                } else {
                    port = nil
                }
                try self.init(
                    host: host,
                    port: port,
                    pathComponents: Array(components.dropFirst())
                )
            } else {
                try self.init(host: "tangled.org", port: nil, pathComponents: components)
            }
        }
    }

    private static func port(_ rawValue: String) throws -> Int {
        guard let port = Int(rawValue), port > 0 else {
            throw ValidationError("Repository reference host port is invalid.")
        }
        return port
    }

    private init(host: String, port: Int?, pathComponents: [String]) throws {
        guard pathComponents.count == 2 else {
            throw ValidationError("Repository reference must be shaped like owner/repo.")
        }

        let owner = pathComponents[0]
        let repository = pathComponents[1].droppingGitSuffix

        guard !owner.isEmpty, !repository.isEmpty else {
            throw ValidationError("Repository reference must include both owner and repository name.")
        }

        self.host = host
        self.port = port
        self.owner = owner
        self.repository = repository
    }

    public var displayName: String {
        "\(owner)/\(repository)"
    }

    public var normalizedReference: String {
        let hostReference = if let port {
            "\(host):\(port)"
        } else {
            host
        }
        return "\(hostReference)/\(owner)/\(repository)"
    }

    public func resolvedOwnerDID() async throws -> String {
        if let did = DID(owner) {
            return did.description
        }

        let handle = owner.hasPrefix("@") ? String(owner.dropFirst()) : owner
        guard !handle.isEmpty else {
            throw ValidationError("Repository owner is not a valid handle.")
        }

        do {
            @Dependency(Atmosphere.Account.Client.self) var accountClient
            let (account, _) = try await accountClient.resolveHandle(
                Atmosphere.Account.Handle(handle)
            )
            return account.id.rawValue.description
        } catch {
            throw ValidationError("Could not resolve repository owner \(owner) to a DID: \(error)")
        }
    }

    public func archiveURL(ref: String) throws -> URL {
        guard !ref.isEmpty else {
            throw ValidationError("Ref cannot be empty.")
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.percentEncodedPath = [
            "",
            try owner.tangledPercentEncodedPathComponent(),
            try repository.tangledPercentEncodedPathComponent(),
            "archive",
            "\(try ref.tangledPercentEncodedPathComponent()).tar.gz"
        ].joined(separator: "/")

        guard let url = components.url else {
            throw ValidationError("Could not construct Tangled archive URL.")
        }
        return url
    }
}

public struct SourceArchiveReference: Equatable, Sendable {
    public var byteCount: Int
    public var checksumSHA256: String
    public var url: URL

    public init(
        url: URL,
        checksumSHA256: String,
        byteCount: Int
    ) {
        self.url = url
        self.checksumSHA256 = checksumSHA256
        self.byteCount = byteCount
    }

    func validate(_ data: Data) throws {
        guard data.count == byteCount else {
            throw SourceArchiveIntegrityError.byteCount(
                expected: byteCount,
                actual: data.count
            )
        }
        let checksumSHA256 = Data(SHA256.hash(data: data)).base64EncodedString()
        guard checksumSHA256 == self.checksumSHA256 else {
            throw SourceArchiveIntegrityError.checksumSHA256(
                expected: self.checksumSHA256,
                actual: checksumSHA256
            )
        }
    }
}

public enum SourceArchiveIntegrityError: Equatable, Error, Sendable {
    case byteCount(expected: Int, actual: Int)
    case checksumSHA256(expected: String, actual: String)
}

public struct TangledSourceCloner: Sendable {
    public var repository: TangledRepositoryReference
    public var ref: String
    public var archive: SourceArchiveReference?
    public var outputURL: URL

    public static func temporaryOutputURL(uuid: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
    }

    public init(
        repository: TangledRepositoryReference,
        ref: String = "HEAD",
        archive: SourceArchiveReference? = nil,
        outputURL: URL
    ) {
        self.repository = repository
        self.ref = ref
        self.archive = archive
        self.outputURL = outputURL
    }

    public func clone() async throws {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.tangledSourceArchiveExtractor) var extractor

        let archiveURL = try archive?.url ?? repository.archiveURL(ref: ref)
        let archiveData: Data = try await withDependencies {
            $0.logBody = false
        } operation: {
            try await httpClient.get(archiveURL, decodingTo: Data.self)
        }
        try archive?.validate(archiveData)
        try await extractor.extract(archiveData, outputURL)
    }
}

public struct TangledSourceArchiveExtractor: Sendable {
    public init() {}

    public static func validateOutputDoesNotExist(_ outputURL: URL) throws {
        let outputPath = outputURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: outputPath) else {
            throw ValidationError("Output path already exists: \(outputPath)")
        }
    }

    public func extract(_ archiveData: Data, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "ome-source-clone-\(UUID().uuidString)")

        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
        }

        do {
            let tarPayloads = try candidateTarPayloads(from: archiveData)
            var lastError: Error?

            for (index, tarData) in tarPayloads.enumerated() {
                let extractionURL = temporaryRoot.appending(path: "extract-\(index)")
                try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)

                if let responseBody = archiveErrorResponse(in: tarData) {
                    lastError = ValidationError("Tangled did not return an archive: \(responseBody)")
                    continue
                }

                do {
                    let archive = Archive(data: Array(tarData))
                    let result = try TarExtractor().extract(
                        archive,
                        to: extractionURL.path(percentEncoded: false)
                    )
                    guard result.extractedEntries > 0 else {
                        lastError = ValidationError("Downloaded archive did not contain any files.")
                        continue
                    }
                } catch {
                    lastError = error
                    continue
                }

                try moveExtractedContents(from: extractionURL, to: outputURL)
                return
            }

            if let responseBody = archiveErrorResponse(in: archiveData) {
                throw ValidationError("Tangled did not return an archive: \(responseBody)")
            }

            if let lastError {
                throw lastError
            }

            throw ValidationError("Downloaded archive did not contain any files.")
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError("Failed to extract Tangled source archive: \(error)")
        }
    }

    private func moveExtractedContents(from extractionURL: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: extractionURL,
            includingPropertiesForKeys: nil
        )

        guard !contents.isEmpty else {
            throw ValidationError("Downloaded archive did not contain any files.")
        }

        let eventsURL = extractionURL.appending(path: "events")
        let sourceRoot: URL
        if directoryExists(at: eventsURL) {
            sourceRoot = extractionURL
        } else if contents.count == 1, try contents[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            sourceRoot = contents[0]
        } else {
            sourceRoot = extractionURL
        }

        try fileManager.moveItem(at: sourceRoot, to: outputURL)
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
            && isDirectory.boolValue
    }

    private func candidateTarPayloads(from archiveData: Data) throws -> [Data] {
        // Some HTTP clients transparently decode `Content-Encoding: gzip`,
        // even when the archive path ends in `.tar.gz`. Try plain tar when
        // the payload is already decoded, but do not feed raw gzip bytes into
        // the tar parser when the gzip magic is still present.
        if archiveData.isGzipped {
            return [try archiveData.gunzipped()]
        }

        var payloads: [Data] = [archiveData]
        if let gunzipped = try? archiveData.gunzipped(), gunzipped != archiveData {
            payloads.append(gunzipped)
        }

        return payloads
    }

    private func archiveErrorResponse(in archiveData: Data) -> String? {
        guard archiveData.count <= 4_096 else { return nil }
        guard let string = String(data: archiveData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        else { return nil }

        let printableScalars = string.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard printableScalars.allSatisfy({ $0.isASCII && $0.value >= 0x20 && $0.value != 0x7F }) else {
            return nil
        }

        return string
    }
}

private extension Bool {
    var not: Bool { !self }
}

public struct TangledSourceArchiveExtractorClient: Sendable {
    public var extract: @Sendable (_ archiveData: Data, _ outputURL: URL) async throws -> Void

    public init(
        extract: @Sendable @escaping (_ archiveData: Data, _ outputURL: URL) async throws -> Void
    ) {
        self.extract = extract
    }
}

public extension TangledSourceArchiveExtractorClient {
    static var live: Self {
        Self { archiveData, outputURL in
            try TangledSourceArchiveExtractor().extract(archiveData, to: outputURL)
        }
    }
}

private enum TangledSourceArchiveExtractorKey: DependencyKey {
    static var liveValue: TangledSourceArchiveExtractorClient {
        .live
    }
}

extension DependencyValues {
    public var tangledSourceArchiveExtractor: TangledSourceArchiveExtractorClient {
        get { self[TangledSourceArchiveExtractorKey.self] }
        set { self[TangledSourceArchiveExtractorKey.self] = newValue }
    }
}

private extension String {
    var looksLikeLocalPath: Bool {
        hasPrefix("/") || hasPrefix(".") || hasPrefix("~")
    }

    var droppingGitSuffix: String {
        if hasSuffix(".git") {
            String(dropLast(4))
        } else {
            self
        }
    }

    func tangledPercentEncodedPathComponent() throws -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#[]")

        guard let encoded = addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw ValidationError("Could not encode URL path component: \(self)")
        }
        return encoded
    }
}
