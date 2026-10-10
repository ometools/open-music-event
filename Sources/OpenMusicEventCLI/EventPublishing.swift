import ATProto
import ATProtoOAuth
import ArgumentParser
import struct ArgumentParser.ValidationError
import Dependencies
import FileTree
import Foundation
import HTTPTypesFoundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing

extension OpenMusicEventCommand {
    struct ProtocolRecords: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "protocol",
            abstract: "Publish OpenMusicEvent records to AT Protocol repositories.",
            subcommands: [PublishEvents.self, PublishProfile.self]
        )
    }
}

extension OpenMusicEventCommand.ProtocolRecords {
    struct PublishEvents: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "publish-events",
            abstract: "Publish source Events at stable AT URIs and verify CID and payload readback."
        )

        @Argument(help: "Path to a local OpenMusicEvent source repository.")
        var source: String

        @Option(name: .long, help: "DIRECTORY=at://DID/events.openmusic.event/TID. Repeat for each Event.")
        var event: [String] = []

        @Flag(help: "Discover every Event directory and allocate stable Event URIs in --identity-map.")
        var discoverEvents = false

        @Option(help: "Stable ISO-8601 creation timestamp. Reuse it when retrying.")
        var createdAt: String

        @Option(help: "Publisher DID; inferred from the mapped Event URIs when omitted.")
        var account: String?

        @Flag(help: "Validate and print the records without authenticating or writing.")
        var dryRun = false

        @Option(help: "Write verified receipts to this new JSON file.")
        var output: String?

        @Option(help: "Explicit PDS hostname for a createSession JSON file.")
        var pds: String?

        @Option(help: "Private createSession JSON file containing did and accessJwt; requires --pds.")
        var sessionFile: String?

        @Option(help: "CA certificate for the explicit PDS; scoped to this invocation.")
        var caCertificate: String?

        @Option(help: "HTTP CONNECT proxy for the explicit PDS; scoped to this invocation.")
        var proxy: String?

        @Flag(help: "Publish the complete source graphs, including contributors, places, programs, schedules, posts and maps.")
        var allRecords = false

        @Flag(help: "Preserve non-URL contributor link values as labeled description text.")
        var preserveLinkText = false

        @Option(help: "Cache downloaded source images for a reviewed publication and its retries. Use a new directory to refresh images.")
        var imageCache: String?

        @Option(help: "Persistent source-to-record identity map; required with --all-records and saved before network writes.")
        var identityMap: String?

        func validate() throws {
            guard allRecords == (identityMap != nil) else {
                throw ValidationError("--all-records and --identity-map must be supplied together.")
            }
            guard event.isEmpty == discoverEvents else {
                throw ValidationError("Pass explicit --event mappings or --discover-events, but not both.")
            }
            if discoverEvents {
                guard allRecords, account != nil else {
                    throw ValidationError("--discover-events requires --all-records, --identity-map, and --account.")
                }
            }
            guard ISO8601DateFormatter().date(from: createdAt) != nil else {
                throw ValidationError("--created-at must be an ISO-8601 timestamp.")
            }
            guard (pds == nil) == (sessionFile == nil) else {
                throw ValidationError("--pds and --session-file must be supplied together.")
            }
            if caCertificate != nil && pds == nil {
                throw ValidationError("--ca-certificate requires --pds and --session-file.")
            }
            if proxy != nil && pds == nil {
                throw ValidationError("--proxy requires --pds and --session-file.")
            }
            if let proxy {
                _ = try EventPublicationNetworking.proxyDictionary(proxy)
            }
            if let pds {
                guard let url = URL(string: "https://\(pds)"), url.host == pds,
                      url.user == nil, url.password == nil, url.port == nil,
                      url.path.isEmpty, url.query == nil, url.fragment == nil else {
                    throw ValidationError("--pds must be a hostname without a scheme, path, or credentials.")
                }
            }
            if let output, FileManager.default.fileExists(atPath: output) {
                throw ValidationError("Receipt output already exists: \(output)")
            }
        }

        func run() async throws {
            let createdAt = ISO8601DateFormatter().date(from: createdAt)!
            let sourceURL = URL(filePath: source)
            let identityMapURL: URL?
            if let identityMap {
                identityMapURL = URL(filePath: identityMap)
            } else {
                identityMapURL = nil
            }
            var identities: SourcePublicationIdentities
            let repository: OpenMusicEventSourceRepository?
            if let identityMapURL {
                identities = try Self.loadIdentities(from: identityMapURL)
                repository = try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: sourceURL)
                    .output
                    .requiredValue
            } else {
                identities = SourcePublicationIdentities()
                repository = nil
            }
            let inputs: [EventPublicationInput]
            if discoverEvents {
                guard let account = account.flatMap(DID.init) else {
                    throw ValidationError("--account must be a DID.")
                }
                inputs = try repository!.events
                    .map { $0.directoryName }
                    .sorted()
                    .map { directory in
                        EventPublicationInput(
                            eventDirectory: directory,
                            uri: try identities.eventURI(
                                sourceDirectory: directory,
                                account: account,
                                createdAt: createdAt
                            )
                        )
                    }
                guard !inputs.isEmpty else {
                    throw ValidationError("The source repository contains no Event directories.")
                }
                try Self.save(identities, to: identityMapURL!)
            } else {
                inputs = try event.map(EventPublicationInput.init(argument:))
            }
            let owner = try EventPublicationInput.owner(of: inputs)
            if let account, account != owner.description {
                throw ValidationError("--account must own every mapped Event URI.")
            }
            let records = try EventPublicationLoader.load(
                sourceURL: sourceURL,
                inputs: inputs,
                account: owner,
                createdAt: createdAt,
                deferSourceImages: identityMapURL != nil
            )
            let eventOnlyPublication = try identityMapURL == nil
                ? EventRecordPublication.prepare(events: records, account: owner) { blob in
                    throw EventRecordPublication.PublicationError.missingImage(blob.ref)
                }
                : nil
            let related: SourceRecordPublication?
            if let identityMapURL {
                let events = Dictionary(uniqueKeysWithValues: try inputs.map { input in
                    guard let record = records.first(where: { $0.id == input.uri }) else { throw ValidationError("Missing selected Event") }
                    return (input.eventDirectory, record)
                })
                let cacheDirectory = imageCache.map { URL(filePath: $0) }
                related = try await SourceRecordPublication.prepare(source: repository!, sourceRoot: sourceURL,
                    events: events, identities: &identities, preserveLinkText: preserveLinkText) { url in
                        if url.isFileURL { return try Data(contentsOf: url) }
                        return try await loadPublicationImage(from: url, cacheDirectory: cacheDirectory) { url in
                            var request = URLRequest(url: url)
                            request.setValue("image/png, image/jpeg", forHTTPHeaderField: "Accept")
                            let (data, response) = try await URLSession.shared.data(for: request)
                            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                                throw ValidationError("Could not download source image: \(url)")
                            }
                            return data
                        }
                    }
                for diagnostic in related?.diagnostics ?? [] {
                    FileHandle.standardError.write(Data((diagnostic + "\n").utf8))
                }
                try Self.save(identities, to: identityMapURL)
            } else {
                related = nil
            }
            if dryRun {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let payloads = related?.records.map { ($0.id, $0.payload) }
                    ?? eventOnlyPublication?.records.map { ($0.id, $0.payload) }
                    ?? []
                for (id, payload) in payloads {
                    print(id.description)
                    print(String(decoding: try encoder.encode(payload), as: UTF8.self))
                }
                return
            }

            let executePublication: @Sendable () async throws -> SourceRecordPublication.Result = {
                if let related {
                    @Dependency(SourceRecordPublisher.self) var publisher
                    return await publisher.publish(related)
                }
                @Dependency(EventRecordPublisher.self) var publisher
                guard let eventOnlyPublication else {
                    throw ValidationError("Missing prepared Event publication")
                }
                let published = try await publisher.publish(eventOnlyPublication)
                var result = SourceRecordPublication.Result()
                result.failures = published.failures
                result.receipts = try published.receipts.map { receipt in
                    guard let record = receipt.event else { throw ValidationError("Missing verified record payload") }
                    return .init(id: receipt.id, cid: receipt.cid, payloadSHA256: receipt.payloadSHA256, value: record.value)
                }
                return result
            }
            let result: SourceRecordPublication.Result
            if let sessionFile, let pds {
                let session = try JSONDecoder().decode(
                    EventPublicationSession.self, from: Data(contentsOf: URL(filePath: sessionFile))
                )
                try session.validate(owner: owner)
                let tls = try caCertificate.map { try EventPublicationTLS(certificateURL: URL(filePath: $0), host: pds) }
                let configuration = try EventPublicationNetworking.configuration(proxy: proxy)
                let urlSession = tls != nil || proxy != nil
                    ? URLSession(configuration: configuration, delegate: tls, delegateQueue: nil)
                    : nil
                defer { urlSession?.invalidateAndCancel() }
                result = try await withDependencies {
                    if let urlSession {
                        $0.dataForURL = { request, body in
                            if let body { return try await urlSession.upload(for: request, from: body) }
                            return try await urlSession.data(for: request)
                        }
                    }
                    session.prepareDependencies(&$0, host: ATProto.PDSHost(rawValue: pds))
                } operation: {
                    // Verify the credential with the named PDS before the first publication write.
                    @Dependency(XRPC.Client.self) var xrpc
                    let observed = try await xrpc.run(ATProto.Server.Requests.GetSession())
                    guard observed.did.rawValue == owner else {
                        throw ValidationError("The PDS session does not belong to the publisher.")
                    }
                    return try await executePublication()
                }
            } else {
                try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
                guard let session = OpenMusicEventOAuth.sessionStore.wrappedValue.sessions[owner] else {
                    throw ValidationError("No stored OME OAuth session for \(owner).")
                }
                result = try await withDependencies {
                    OpenMusicEventOAuth.prepareDependencies(&$0)
                    $0.getSelectedOAuthSessionID = { session.accountID }
                    $0.getDefaultSession = { OpenMusicEventOAuth.sessionStore.wrappedValue[session.accountID] ?? session }
                    $0.getOptionalDefaultSession = { OpenMusicEventOAuth.sessionStore.wrappedValue[session.accountID] ?? session }
                } operation: {
                    return try await executePublication()
                }
            }
            if let output {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(result.receipts).write(to: URL(filePath: output), options: .withoutOverwriting)
            }
            for receipt in result.receipts {
                print("Verified \(receipt.id)\n  cid: \(receipt.cid.rawValue)")
            }
            guard result.failures.isEmpty else {
                throw ValidationError(result.failures.sorted { $0.key.description < $1.key.description }
                    .map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
            }
        }

        private static func loadIdentities(from path: URL) throws -> SourcePublicationIdentities {
            FileManager.default.fileExists(atPath: path.path)
                ? try JSONDecoder().decode(
                    SourcePublicationIdentities.self,
                    from: Data(contentsOf: path)
                )
                : SourcePublicationIdentities()
        }

        private static func save(
            _ identities: SourcePublicationIdentities,
            to path: URL
        ) throws {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(identities).write(to: path, options: .atomic)
        }
    }
}

struct EventPublicationInput: Equatable, Sendable {
    var eventDirectory: String
    var uri: ATProto.URI

    init(eventDirectory: String, uri: ATProto.URI) {
        self.eventDirectory = eventDirectory
        self.uri = uri
    }

    init(argument: String) throws {
        let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, let uri = ATProto.URI(parts[1]),
              case .did = uri.authority else {
            throw ValidationError("--event must be DIRECTORY=at://DID/events.openmusic.event/TID.")
        }
        try LexiconCoding.validateRecordURI(uri, type: Event.self)
        eventDirectory = parts[0]
        self.uri = uri
    }

    static func owner(of inputs: [Self]) throws -> DID {
        guard let first = inputs.first, case let .did(owner) = first.uri.authority,
              inputs.allSatisfy({ $0.uri.authority == .did(owner) }) else {
            throw ValidationError("All mapped Events must belong to one publisher DID.")
        }
        return owner
    }
}

enum EventPublicationLoader {
    static func load(
        sourceURL: URL,
        inputs: [EventPublicationInput],
        account: DID,
        createdAt: Date,
        deferSourceImages: Bool = false
    ) throws -> [Event] {
        var repository = try OpenMusicEventSourceRepositoryFileTree().read(from: sourceURL).output.requiredValue
        let directories = Set(inputs.map(\.eventDirectory))
        repository.events.removeAll { !directories.contains($0.directoryName) }
        if deferSourceImages {
            for index in repository.events.indices {
                repository.events[index].components.event.images = nil
            }
        }
        return try OpenMusicEventSourcePublicationCompiler.compileEvents(
            repository: repository, account: account,
            identities: inputs.map { .init(sourceDirectory: $0.eventDirectory, uri: $0.uri, createdAt: createdAt) }
        ).map(\.record)
    }
}

struct EventPublicationSession: Decodable, Sendable {
    let did: DID
    let accessJwt: String

    func validate(owner: DID) throws {
        guard did == owner, !accessJwt.isEmpty,
              !accessJwt.contains(where: { $0.isWhitespace }) else {
            throw ValidationError("The session file must contain a token for the publisher DID.")
        }
    }

    func prepareDependencies(_ dependencies: inout DependencyValues, host: ATProto.PDSHost) {
        dependencies.pdsHost = host
        dependencies[ATProto.Repository.PDSHostResolver.self] = .init { repository in
            guard repository == .did(did) else { throw ValidationError("Unexpected publication repository.") }
            return host
        }
        dependencies.xrpcAuthorizationGate = .init { policy, routing, operation in
            if let requirement = policy.authRequirement,
               case let .did(owner) = requirement.account, owner != did {
                throw ValidationError("The session does not own this publication.")
            }
            return try await withDependencies {
                $0.requestHeaders[.authorization] = "Bearer \(accessJwt)"
            } operation: {
                try await routing.withAuthenticatedRoute(operation: operation)
            }
        }
        let transport = dependencies.dataForURL
        dependencies.dataForURL = { request, body in
            guard request.scheme == "https", request.authority == host.rawValue else {
                throw ValidationError("Publication session credentials are restricted to the explicit PDS.")
            }
            return try await transport(request, body)
        }
    }
}
