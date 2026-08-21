import Crypto
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventSource
import OpenMusicEventSourceClone

public struct SourceArtifactAWSCredentials: Sendable {
    public init(
        accessKeyID: String,
        secretAccessKey: String,
        sessionToken: String? = nil
    ) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }

    public let accessKeyID: String
    public let secretAccessKey: String
    public let sessionToken: String?
}

public struct SourceArtifactS3Configuration: Sendable {
    public init(
        bucket: String,
        region: String,
        publicOrigin: URL,
        credentials: SourceArtifactAWSCredentials
    ) {
        self.bucket = bucket
        self.region = region
        self.publicOrigin = publicOrigin
        self.credentials = credentials
    }

    public let bucket: String
    public let region: String
    public let publicOrigin: URL
    public let credentials: SourceArtifactAWSCredentials

    func reference(for repository: TangledRepositoryReference) -> String {
        publicOrigin
            .appending(path: repository.owner)
            .appending(path: repository.repository)
            .absoluteString
    }

    func objectKey(for repository: TangledRepositoryReference, revision: String) -> String {
        "\(repository.owner)/\(repository.repository)/archive/\(revision).tar.gz"
    }

    func objectURL(key: String) -> URL {
        key.split(separator: "/").reduce(
            URL(string: "https://s3.\(region).amazonaws.com")!
                .appending(path: bucket)
        ) { url, component in
            url.appending(path: String(component))
        }
    }
}

struct ValidatedSourceArchive: Equatable, Sendable {
    let data: Data
    let snapshot: TangledSourceSnapshot

    static func downloadAndValidate(
        update: TangledSourceUpdate,
        revision: String
    ) async throws -> Self {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.uuid) var uuid

        let repository = TangledRepositoryReference(
            host: update.repository.host,
            port: update.repository.port,
            owner: update.repositoryOwnerDID.description,
            repository: update.repository.repository
        )
        let archiveData: Data = try await withDependencies {
            $0.logBody = false
        } operation: {
            try await httpClient.get(
                repository.archiveURL(ref: revision),
                decodingTo: Data.self
            )
        }
        let outputURL = TangledSourceCloner.temporaryOutputURL(uuid: uuid())
        try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try TangledSourceArchiveExtractor().extract(archiveData, to: outputURL)
        let validation = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: outputURL.path(percentEncoded: false),
                organizerID: update.canonicalSource.organizerID,
                sourceProvenance: update.canonicalSource.provenance(ref: revision),
                ref: revision
            )
        )
        .validate()
        return Self(
            data: archiveData,
            snapshot: try TangledSourceSnapshot(
                validated: validation.insertion,
                revision: revision
            )
        )
    }
}

struct SourceArtifactPublicationRequest: Equatable, Sendable {
    let archiveData: Data
    let repository: TangledRepositoryReference
    let revision: String
}

struct PublishedSourceArtifact: Equatable, Sendable {
    let reference: String
    let objectKey: String
    let revision: String
    let checksumSHA256: String
    let byteCount: Int
    let publishedAt: Date
}

public struct SourceArtifactPublisher: Sendable {
    var publish: @Sendable (SourceArtifactPublicationRequest) async throws
        -> PublishedSourceArtifact

    init(
        publish: @escaping @Sendable (SourceArtifactPublicationRequest) async throws
            -> PublishedSourceArtifact
    ) {
        self.publish = publish
    }

    static func s3(configuration: SourceArtifactS3Configuration) -> Self {
        Self { request in
            @Dependency(\.date.now) var now
            @Dependency(\.httpClient) var httpClient
            let objectKey = configuration.objectKey(
                for: request.repository,
                revision: request.revision
            )
            let signedRequest = SourceArtifactS3Request(
                url: configuration.objectURL(key: objectKey),
                body: request.archiveData,
                revision: request.revision,
                region: configuration.region,
                credentials: configuration.credentials,
                date: now
            )
            _ = try await httpClient.run(signedRequest.request, request.archiveData)
            return PublishedSourceArtifact(
                reference: configuration.reference(for: request.repository),
                objectKey: objectKey,
                revision: request.revision,
                checksumSHA256: signedRequest.checksumSHA256,
                byteCount: request.archiveData.count,
                publishedAt: now
            )
        }
    }
}

struct SourceArtifactS3Request: Equatable, Sendable {
    init(
        url: URL,
        body: Data,
        revision: String,
        region: String,
        credentials: SourceArtifactAWSCredentials,
        date: Date
    ) {
        let payloadDigest = Data(SHA256.hash(data: body))
        let payloadHash = payloadDigest.hexEncodedString
        checksumSHA256 = payloadDigest.base64EncodedString()

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)
        let dateStamp = String(amzDate.prefix(8))
        let host = url.host(percentEncoded: false)!

        var canonicalHeaders = [
            "cache-control": "public, max-age=31536000, immutable",
            "content-type": "application/octet-stream",
            "host": host,
            "x-amz-checksum-sha256": checksumSHA256,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": amzDate,
            "x-amz-meta-source-revision": revision,
        ]
        if let sessionToken = credentials.sessionToken {
            canonicalHeaders["x-amz-security-token"] = sessionToken
        }
        let signedHeaderNames = canonicalHeaders.keys.sorted()
        let signedHeaders = signedHeaderNames.joined(separator: ";")
        let canonicalHeaderBlock = signedHeaderNames
            .map { "\($0):\(canonicalHeaders[$0]!)\n" }
            .joined()
        let canonicalPath = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )!
        .percentEncodedPath
        let canonicalRequest = [
            "PUT",
            canonicalPath,
            "",
            canonicalHeaderBlock,
            signedHeaders,
            payloadHash,
        ]
        .joined(separator: "\n")
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Data(SHA256.hash(data: Data(canonicalRequest.utf8))).hexEncodedString,
        ]
        .joined(separator: "\n")
        let dateKey = Self.hmac(
            Data("AWS4\(credentials.secretAccessKey)".utf8),
            dateStamp
        )
        let regionKey = Self.hmac(dateKey, region)
        let serviceKey = Self.hmac(regionKey, "s3")
        let signingKey = Self.hmac(serviceKey, "aws4_request")
        let signature = Self.hmac(signingKey, stringToSign).hexEncodedString

        var request = HTTPRequest(url: url)
        request.method = .put
        request.headerFields[.authorization] =
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        for (name, value) in canonicalHeaders {
            request.headerFields[HTTPField.Name(name)!] = value
        }
        self.request = request
    }

    let request: HTTPRequest
    let checksumSHA256: String

    private static func hmac(_ key: Data, _ message: String) -> Data {
        Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: SymmetricKey(data: key)
            )
        )
    }
}

private extension Data {
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
