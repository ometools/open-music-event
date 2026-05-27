import ATProto
import ATProtoOAuth
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Dependencies
import Foundation
import Sharing
import SourceControlClient
import XRPCClient

private let tangledSSHCredentialsStorage = Shared<TangledStoredSSHCredentials?>(
    wrappedValue: nil,
    .appStorage("fm_woody_openMusicEvent_tangled_ssh_credentials")
)

public struct TangledSSHCredentialsClient: Sendable {
    public var credentials: @Sendable () async throws -> Credentials
    public var reset: @Sendable () -> Void

    public init(
        credentials: @escaping @Sendable () async throws -> Credentials,
        reset: @escaping @Sendable () -> Void = {}
    ) {
        self.credentials = credentials
        self.reset = reset
    }
}

public struct TangledStoredSSHCredentials: Codable, Equatable, Sendable {
    public var publicKey: String
    public var privateKey: String
    public var name: String
    public var createdAt: String
    public var recordURI: String?
    public var recordCID: String?

    public init(
        publicKey: String,
        privateKey: String,
        name: String,
        createdAt: String,
        recordURI: String? = nil,
        recordCID: String? = nil
    ) {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.name = name
        self.createdAt = createdAt
        self.recordURI = recordURI
        self.recordCID = recordCID
    }

    public var sourceControlCredentials: Credentials {
        Credentials(
            ssh: SSHCredentials(
                publicKey: SSHPublicKey(rawValue: publicKey),
                privateKey: SSHPrivateKey(rawValue: privateKey)
            )
        )
    }
}

public struct TangledSSHKeyPair: Equatable, Sendable {
    public var publicKey: String
    public var privateKey: String

    public init(publicKey: String, privateKey: String) {
        self.publicKey = publicKey
        self.privateKey = privateKey
    }
}

public extension TangledSSHCredentialsClient {
    static var live: Self {
        live(
            storage: tangledSSHCredentialsStorage,
            generateKeyPair: {
                try TangledSSHKeyPair.ed25519(comment: "Open Music Event")
            }
        )
    }

    static func live(
        storage: Shared<TangledStoredSSHCredentials?>,
        generateKeyPair: @escaping @Sendable () throws -> TangledSSHKeyPair
    ) -> Self {
        Self {
            if var stored = storage.withLock({ $0 }) {
                if stored.recordURI == nil {
                    stored = try await registeredCredentials(stored, storage: storage)
                }
                return stored.sourceControlCredentials
            }

            let keyPair = try generateKeyPair()
            let createdAt = iso8601String(now())
            var stored = TangledStoredSSHCredentials(
                publicKey: keyPair.publicKey,
                privateKey: keyPair.privateKey,
                name: "Open Music Event",
                createdAt: createdAt
            )
            storage.withLock { $0 = stored }
            stored = try await registeredCredentials(stored, storage: storage)
            return stored.sourceControlCredentials
        } reset: {
            storage.withLock { $0 = nil }
        }
    }
}

public extension DependencyValues {
    var tangledSSHCredentials: TangledSSHCredentialsClient {
        get { self[TangledSSHCredentialsClientKey.self] }
        set { self[TangledSSHCredentialsClientKey.self] = newValue }
    }
}

private enum TangledSSHCredentialsClientKey: DependencyKey {
    static var liveValue: TangledSSHCredentialsClient {
        .live
    }

    static var testValue: TangledSSHCredentialsClient {
        TangledSSHCredentialsClient {
            throw TangledSSHCredentialsError.notConfigured
        }
    }
}

public enum TangledSSHCredentialsError: Equatable, Error, Sendable {
    case invalidEd25519KeyLength
    case notConfigured
}

extension TangledSSHKeyPair {
    static func ed25519(comment: String) throws -> Self {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try ed25519(
            seed: Data(privateKey.rawRepresentation),
            publicKey: Data(privateKey.publicKey.rawRepresentation),
            comment: comment
        )
    }

    static func ed25519(seed: Data, publicKey: Data, comment: String) throws -> Self {
        guard seed.count == 32, publicKey.count == 32 else {
            throw TangledSSHCredentialsError.invalidEd25519KeyLength
        }

        let publicKeyBlob = sshEd25519PublicKeyBlob(publicKey)
        var privateKeyBytes = Data()
        privateKeyBytes.append(seed)
        privateKeyBytes.append(publicKey)

        var privateBlock = SSHBinaryWriter()
        privateBlock.appendUInt32(0)
        privateBlock.appendUInt32(0)
        privateBlock.appendString("ssh-ed25519")
        privateBlock.appendData(publicKey)
        privateBlock.appendData(privateKeyBytes)
        privateBlock.appendString(comment)

        var paddingByte: UInt8 = 1
        while privateBlock.data.count % 8 != 0 {
            privateBlock.data.append(paddingByte)
            paddingByte += 1
        }

        var outer = SSHBinaryWriter()
        outer.data.append(Data("openssh-key-v1\0".utf8))
        outer.appendString("none")
        outer.appendString("none")
        outer.appendData(Data())
        outer.appendUInt32(1)
        outer.appendData(publicKeyBlob)
        outer.appendData(privateBlock.data)

        let privateKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(wrappedBase64(outer.data.base64EncodedString()))
        -----END OPENSSH PRIVATE KEY-----

        """

        return Self(
            publicKey: "ssh-ed25519 \(publicKeyBlob.base64EncodedString()) \(comment)",
            privateKey: privateKey
        )
    }
}

private func registeredCredentials(
    _ stored: TangledStoredSSHCredentials,
    storage: Shared<TangledStoredSSHCredentials?>
) async throws -> TangledStoredSSHCredentials {
    if let registered = try await existingCredentialsRecord(stored) {
        storage.withLock { $0 = registered }
        return registered
    }

    var stored = stored
    @Dependency(\.getDefaultSession) var getDefaultSession
    @Dependency(XRPC.Client.self) var xrpcClient
    let output = try await xrpcClient.run(
        TangledCreateRecordRequest(
            input: TangledCreateRecordInput(
                repo: getDefaultSession().accountID.rawValue.description,
                collection: TangledPublicKeyRecord.collection,
                record: TangledPublicKeyRecord(
                    key: stored.publicKey,
                    name: stored.name,
                    createdAt: stored.createdAt
                )
            ),
            authorizationPolicy: .required(TangledOAuthRequirements.publicKeyAuthRequirement)
        )
    )
    stored.recordURI = output.uri.description
    stored.recordCID = output.cid.description
    storage.withLock { $0 = stored }
    return stored
}

private func existingCredentialsRecord(
    _ stored: TangledStoredSSHCredentials
) async throws -> TangledStoredSSHCredentials? {
    @Dependency(\.getDefaultSession) var getDefaultSession
    @Dependency(XRPC.Client.self) var xrpcClient
    var cursor: String?

    repeat {
        let output = try await xrpcClient.run(
            TangledListRecordsRequest<TangledPublicKeyRecord>(
                repo: getDefaultSession().accountID.rawValue.description,
                collection: TangledPublicKeyRecord.collection,
                cursor: cursor,
                authorizationPolicy: .required(TangledOAuthRequirements.publicKeyAuthRequirement)
            )
        )
        if let record = output.records.first(where: { $0.value.key == stored.publicKey }) {
            var stored = stored
            stored.recordURI = record.uri.description
            stored.recordCID = record.cid?.description
            return stored
        }
        cursor = output.cursor
    } while cursor != nil

    return nil
}

private func now() -> Date {
    @Dependency(\.date.now) var now
    return now
}

private func iso8601String(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func sshEd25519PublicKeyBlob(_ publicKey: Data) -> Data {
    var writer = SSHBinaryWriter()
    writer.appendString("ssh-ed25519")
    writer.appendData(publicKey)
    return writer.data
}

private func wrappedBase64(_ base64: String) -> String {
    stride(from: 0, to: base64.count, by: 70)
        .map { start in
            let startIndex = base64.index(base64.startIndex, offsetBy: start)
            let endIndex = base64.index(
                startIndex,
                offsetBy: min(70, base64.distance(from: startIndex, to: base64.endIndex))
            )
            return String(base64[startIndex..<endIndex])
        }
        .joined(separator: "\n")
}

private struct SSHBinaryWriter {
    var data = Data()

    mutating func appendUInt32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    mutating func appendString(_ value: String) {
        appendData(Data(value.utf8))
    }

    mutating func appendData(_ value: Data) {
        appendUInt32(UInt32(value.count))
        data.append(value)
    }
}
