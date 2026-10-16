import ATProto
import ArgumentParser
import struct ArgumentParser.ValidationError
import Dependencies
import Foundation
import HTTPTypesFoundation
import OpenMusicEventSourceEditing

extension OpenMusicEventCommand.ProtocolRecords {
    struct PublishProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "publish-profile",
            abstract: "Publish and verify a venue-owned app.bsky.actor.profile record."
        )

        @Option(help: "Venue account DID.")
        var account: String

        @Option(help: "Venue display name.")
        var displayName: String

        @Option(help: "Venue profile description.")
        var description: String?

        @Option(help: "Optional local PNG or JPEG avatar, limited to 1 MB.")
        var avatar: String?

        @Option(help: "Explicit PDS hostname.")
        var pds: String

        @Option(help: "Private createSession JSON file containing did and accessJwt.")
        var sessionFile: String

        @Option(help: "CA certificate for the explicit PDS; scoped to this invocation.")
        var caCertificate: String?

        @Option(help: "HTTP CONNECT proxy for the explicit PDS; scoped to this invocation.")
        var proxy: String?

        @Option(help: "Write the verified receipt to this new JSON file.")
        var output: String?

        func validate() throws {
            guard DID(account) != nil else { throw ValidationError("--account must be a DID.") }
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("--display-name must not be empty.")
            }
            guard let url = URL(string: "https://\(pds)"), url.host == pds,
                  url.user == nil, url.password == nil, url.port == nil,
                  url.path.isEmpty, url.query == nil, url.fragment == nil else {
                throw ValidationError("--pds must be a hostname without a scheme, path, or credentials.")
            }
            if let proxy {
                _ = try EventPublicationNetworking.proxyDictionary(proxy)
            }
            if let output, FileManager.default.fileExists(atPath: output) {
                throw ValidationError("Receipt output already exists: \(output)")
            }
        }

        func run() async throws {
            let account = DID(account)!
            let avatarURL: URL?
            if let avatar {
                avatarURL = URL(filePath: avatar)
            } else {
                avatarURL = nil
            }
            let publication = try VenueProfilePublication.prepare(
                account: account,
                displayName: displayName,
                description: description,
                avatarURL: avatarURL
            )
            let session = try JSONDecoder().decode(
                EventPublicationSession.self,
                from: Data(contentsOf: URL(filePath: sessionFile))
            )
            try session.validate(owner: account)
            let tls = try caCertificate.map {
                try EventPublicationTLS(certificateURL: URL(filePath: $0), host: pds)
            }
            let configuration = try EventPublicationNetworking.configuration(proxy: proxy)
            let urlSession = tls != nil || proxy != nil
                ? URLSession(configuration: configuration, delegate: tls, delegateQueue: nil)
                : nil
            defer { urlSession?.invalidateAndCancel() }
            let result = try await withDependencies {
                if let urlSession {
                    $0.dataForURL = { request, body in
                        if let body { return try await urlSession.upload(for: request, from: body) }
                        return try await urlSession.data(for: request)
                    }
                }
                session.prepareDependencies(&$0, host: ATProto.PDSHost(rawValue: pds))
            } operation: {
                @Dependency(XRPC.Client.self) var xrpc
                let observed = try await xrpc.run(ATProto.Server.Requests.GetSession())
                guard observed.did.rawValue == account else {
                    throw ValidationError("The PDS session does not belong to the publisher.")
                }
                @Dependency(SourceRecordPublisher.self) var publisher
                return await publisher.publish(publication)
            }
            guard result.failures.isEmpty, let receipt = result.receipts.only else {
                throw ValidationError(
                    result.failures.values.first ?? "The venue profile was not verified."
                )
            }
            if let output {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(receipt).write(
                    to: URL(filePath: output),
                    options: .withoutOverwriting
                )
            }
            print("Verified \(receipt.id)\n  cid: \(receipt.cid.rawValue)")
        }
    }
}

enum VenueProfilePublication {
    static func prepare(
        account: DID,
        displayName: String,
        description: String?,
        avatarURL: URL?
    ) throws -> SourceRecordPublication {
        let id = ATProto.URI(
            "at://\(account.description)/app.bsky.actor.profile/self"
        )!
        var value: [String: Lexicon.JSONValue] = [
            "$type": .string("app.bsky.actor.profile"),
            "displayName": .string(displayName),
        ]
        if let description, !description.isEmpty {
            value["description"] = .string(description)
        }
        var images: [ATProto.CID: Data] = [:]
        if let avatarURL {
            let data = try Data(contentsOf: avatarURL)
            guard data.count <= 1_000_000 else {
                throw ValidationError("Venue profile avatars must not exceed 1 MB.")
            }
            let mimeType: ATProto.MIMEType
            if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
                mimeType = .png
            } else if data.starts(with: [255, 216, 255]) {
                mimeType = .jpeg
            } else {
                throw ValidationError("Venue profile avatars must be PNG or JPEG files.")
            }
            let blob = localImageBlob(data, mimeType: mimeType)
            value["avatar"] = try Lexicon.JSONValue(encoding: blob)
            images[blob.ref] = data
        }
        var publication = SourceRecordPublication(account: account)
        try publication.append(id: id, payload: .object(value), images: images)
        return publication
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
