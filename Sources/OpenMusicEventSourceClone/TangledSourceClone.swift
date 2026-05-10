import ArgumentParser
import Dependencies
import Foundation
import HTTPClient

#if os(macOS)
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

        @Dependency(\.httpClient) var httpClient
        @Dependency(\.tangledSourceArchiveExtractor) var extractor

        let archiveData: Data = try await httpClient.get(
            try repository.archiveURL(ref: ref),
            decodingTo: Data.self
        )
        try await extractor.extract(archiveData, outputURL)

        print("Downloaded \(repository.displayName) at \(ref) to \(outputURL.path())")
    }

    public static func resolvedOutputURL(_ output: String) throws -> URL {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw ValidationError("Output path cannot be empty.")
        }

        return URL(filePath: trimmedOutput).standardizedFileURL
    }

    public static func temporaryOutputURL(uuid: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
    }
}
#endif

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
            try self.init(host: "tangled.org", port: nil, pathComponents: components)
        }
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

#if os(macOS)
public struct TangledSourceArchiveExtractor: Sendable {
    public init() {}

    public static func validateOutputDoesNotExist(_ outputURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: outputURL.path()) else {
            throw ValidationError("Output path already exists: \(outputURL.path())")
        }
    }

    public func extract(_ archiveData: Data, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "ome-source-clone-\(UUID().uuidString)")
        let archiveURL = temporaryRoot.appending(path: "source.tar.gz")
        let extractionURL = temporaryRoot.appending(path: "extract")

        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
        }

        try archiveData.write(to: archiveURL, options: [.atomic])
        try runTarExtracting(archiveURL: archiveURL, destinationURL: extractionURL)
        try moveExtractedContents(from: extractionURL, to: outputURL)
    }

    private func runTarExtracting(archiveURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = [
            "-xzf",
            archiveURL.path(),
            "-C",
            destinationURL.path()
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError("Failed to extract Tangled source archive.")
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

        let sourceRoot: URL
        if contents.count == 1, try contents[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            sourceRoot = contents[0]
        } else {
            sourceRoot = extractionURL
        }

        try fileManager.moveItem(at: sourceRoot, to: outputURL)
    }
}

public struct TangledSourceArchiveExtractorClient: Sendable {
    public var extract: @Sendable (_ archiveData: Data, _ outputURL: URL) async throws -> Void

    public init(
        extract: @Sendable @escaping (_ archiveData: Data, _ outputURL: URL) async throws -> Void
    ) {
        self.extract = extract
    }
}

private enum TangledSourceArchiveExtractorKey: DependencyKey {
    static var liveValue: TangledSourceArchiveExtractorClient {
        TangledSourceArchiveExtractorClient { archiveData, outputURL in
            try TangledSourceArchiveExtractor().extract(archiveData, to: outputURL)
        }
    }
}

extension DependencyValues {
    public var tangledSourceArchiveExtractor: TangledSourceArchiveExtractorClient {
        get { self[TangledSourceArchiveExtractorKey.self] }
        set { self[TangledSourceArchiveExtractorKey.self] = newValue }
    }
}
#endif

private extension String {
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
