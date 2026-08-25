import Crypto
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventSourceClone

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
                url: configuration.publicURL(key: objectKey),
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

struct SourceArtifactPublicationRequest: Equatable, Sendable {
    let archiveData: Data
    let repository: TangledRepositoryReference
    let revision: String
}

struct PublishedSourceArtifact: Equatable, Sendable {
    let url: URL
    let reference: String
    let objectKey: String
    let revision: String
    let checksumSHA256: String
    let byteCount: Int
    let publishedAt: Date
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
