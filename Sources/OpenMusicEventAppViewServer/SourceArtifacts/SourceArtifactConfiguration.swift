import Foundation
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

    func publicURL(key: String) -> URL {
        key.split(separator: "/").reduce(publicOrigin) { url, component in
            url.appending(path: String(component))
        }
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

extension AppViewConfiguration {
    static func sourceArtifactConfiguration(
        environment: [String: String]
    ) throws -> SourceArtifactS3Configuration? {
        let keys = [
            "OME_SOURCE_ARTIFACT_S3_BUCKET",
            "OME_SOURCE_ARTIFACT_S3_REGION",
            "OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN",
        ]
        guard keys.contains(where: { environment[$0] != nil }) else {
            return nil
        }

        func required(_ key: String) throws -> String {
            guard let value = environment[key]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !value.isEmpty else {
                throw AppViewConfigurationError.sourceArtifactConfigurationValueMissing(key)
            }
            return value
        }

        let rawOrigin = try required("OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN")
        guard let publicOrigin = URL(string: rawOrigin),
              publicOrigin.scheme == "https",
              publicOrigin.host(percentEncoded: false) != nil,
              publicOrigin.user == nil,
              publicOrigin.password == nil,
              publicOrigin.query == nil,
              publicOrigin.fragment == nil,
              publicOrigin.path.isEmpty || publicOrigin.path == "/"
        else {
            throw AppViewConfigurationError.invalidSourceArtifactPublicOrigin(rawOrigin)
        }
        let sessionToken = environment["AWS_SESSION_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SourceArtifactS3Configuration(
            bucket: try required("OME_SOURCE_ARTIFACT_S3_BUCKET"),
            region: try required("OME_SOURCE_ARTIFACT_S3_REGION"),
            publicOrigin: publicOrigin,
            credentials: SourceArtifactAWSCredentials(
                accessKeyID: try required("AWS_ACCESS_KEY_ID"),
                secretAccessKey: try required("AWS_SECRET_ACCESS_KEY"),
                sessionToken: sessionToken?.isEmpty == false ? sessionToken : nil
            )
        )
    }
}
