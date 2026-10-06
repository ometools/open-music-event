import ATProto
import ATProtoOAuth
import ArgumentParser
import struct ArgumentParser.ValidationError
import Dependencies
import FileTree
import Foundation
import HTTPTypesFoundation
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing

extension OpenMusicEventCommand {
    struct ProtocolRecords: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "protocol",
            abstract: "Publish OpenMusicEvent records to AT Protocol repositories.",
            subcommands: [PublishEvents.self]
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
        var event: [String]

        @Option(help: "Stable ISO-8601 creation timestamp. Reuse it when retrying.")
        var createdAt: String

        @Option(help: "Publisher DID; defaults to the selected stored OAuth account.")
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

        func validate() throws {
            guard !event.isEmpty else { throw ValidationError("Pass at least one --event mapping.") }
            guard ISO8601DateFormatter().date(from: createdAt) != nil else {
                throw ValidationError("--created-at must be an ISO-8601 timestamp.")
            }
            guard (pds == nil) == (sessionFile == nil) else {
                throw ValidationError("--pds and --session-file must be supplied together.")
            }
            if caCertificate != nil && pds == nil {
                throw ValidationError("--ca-certificate requires --pds and --session-file.")
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
            let inputs = try event.map(EventPublicationInput.init(argument:))
            let owner = try EventPublicationInput.owner(of: inputs)
            if let account, account != owner.description {
                throw ValidationError("--account must own every mapped Event URI.")
            }
            let records = try EventPublicationLoader.load(
                sourceURL: URL(filePath: source), inputs: inputs,
                account: owner, createdAt: ISO8601DateFormatter().date(from: createdAt)!
            )
            let publication = try EventRecordPublication.prepare(events: records, account: owner) { blob in
                throw EventRecordPublication.PublicationError.missingImage(blob.ref)
            }
            if dryRun {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                for record in publication.records {
                    print(record.id.description)
                    print(String(decoding: try encoder.encode(record.payload), as: UTF8.self))
                }
                return
            }

            let result: EventRecordPublicationResult
            if let sessionFile, let pds {
                let session = try JSONDecoder().decode(
                    EventPublicationSession.self, from: Data(contentsOf: URL(filePath: sessionFile))
                )
                try session.validate(owner: owner)
                let tls = try caCertificate.map { try EventPublicationTLS(certificateURL: URL(filePath: $0), host: pds) }
                let urlSession = tls.map { URLSession(configuration: .ephemeral, delegate: $0, delegateQueue: nil) }
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
                    @Dependency(EventRecordPublisher.self) var publisher
                    return try await publisher.publish(publication)
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
                    @Dependency(EventRecordPublisher.self) var publisher
                    return try await publisher.publish(publication)
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
    }
}

struct EventPublicationInput: Equatable, Sendable {
    var eventDirectory: String
    var uri: ATProto.URI

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
    static func load(sourceURL: URL, inputs: [EventPublicationInput], account: DID, createdAt: Date) throws -> [Event] {
        var repository = try OpenMusicEventSourceRepositoryFileTree().read(from: sourceURL).output.requiredValue
        let directories = Set(inputs.map(\.eventDirectory))
        repository.events.removeAll { !directories.contains($0.directoryName) }
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
