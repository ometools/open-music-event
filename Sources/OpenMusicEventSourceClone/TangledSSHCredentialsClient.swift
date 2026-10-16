import ATProto
import ATProtoOAuth
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Dependencies
import Foundation
import HTTPClient
#if canImport(OSLog)
import OSLog
#endif
#if os(Android)
import SkipSharing
#else
import Sharing
#endif
import SourceControlClient
import ATProto

#if os(Linux)
private let tangledSSHCredentialsStorage = Shared<TangledStoredSSHCredentials?>(value: nil)
#elseif os(Android)
private let tangledSSHCredentialsStorage = Shared<TangledStoredSSHCredentials?>(
    wrappedValue: nil,
    .appStorage("fm_woody_openMusicEvent_tangled_ssh_credentials")
)
#else
private let tangledSSHCredentialsStorage = Shared<TangledStoredSSHCredentials?>(
    wrappedValue: nil,
    KeychainSharedKey(
        item: KeychainStorageItem(
            service: "fm.woody.openMusicEvent",
            account: "tangled.sshCredentials"
        )
    )
)
private let tangledSSHCredentialsLegacyStorage = Shared<TangledStoredSSHCredentials?>(
    wrappedValue: nil,
    .appStorage("fm_woody_openMusicEvent_tangled_ssh_credentials")
)
#endif

public struct TangledSSHCredentialsClient: Sendable {
    public var credentials: @Sendable () async throws -> Credentials
    public var readyCredentials: @Sendable (ATProto.PDSHost) async throws -> Credentials
    public var reset: @Sendable () -> Void

    public init(
        credentials: @escaping @Sendable () async throws -> Credentials,
        readyCredentials: (@Sendable (ATProto.PDSHost) async throws -> Credentials)? = nil,
        reset: @escaping @Sendable () -> Void = {}
    ) {
        self.credentials = credentials
        self.readyCredentials = readyCredentials ?? { _ in try await credentials() }
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
        #if os(Linux) || os(Android)
        live(
            storage: tangledSSHCredentialsStorage,
            generateKeyPair: {
                try TangledSSHKeyPair.ed25519(comment: "Open Music Event")
            }
        )
        #else
        live(
            storage: tangledSSHCredentialsStorage,
            legacyStorage: tangledSSHCredentialsLegacyStorage,
            generateKeyPair: {
                try TangledSSHKeyPair.ed25519(comment: "Open Music Event")
            }
        )
        #endif
    }

    static func live(
        storage: Shared<TangledStoredSSHCredentials?>,
        legacyStorage: Shared<TangledStoredSSHCredentials?>? = nil,
        generateKeyPair: @escaping @Sendable () throws -> TangledSSHKeyPair
    ) -> Self {
        let provider = LiveTangledSSHCredentialsProvider(
            storage: storage,
            legacyStorage: legacyStorage,
            generateKeyPair: generateKeyPair
        )
        return Self(
            credentials: {
                try await provider.credentials()
            },
            readyCredentials: { knotHost in
                try await provider.credentials(readyOn: knotHost)
            },
            reset: {
                storage.withLock { $0 = nil }
                legacyStorage?.withLock { $0 = nil }
            }
        )
    }
}

private actor LiveTangledSSHCredentialsProvider {
    let storage: Shared<TangledStoredSSHCredentials?>
    let legacyStorage: Shared<TangledStoredSSHCredentials?>?
    let generateKeyPair: @Sendable () throws -> TangledSSHKeyPair

    init(
        storage: Shared<TangledStoredSSHCredentials?>,
        legacyStorage: Shared<TangledStoredSSHCredentials?>?,
        generateKeyPair: @escaping @Sendable () throws -> TangledSSHKeyPair
    ) {
        self.storage = storage
        self.legacyStorage = legacyStorage
        self.generateKeyPair = generateKeyPair
    }

    func credentials(readyOn knotHost: ATProto.PDSHost? = nil) async throws -> Credentials {
        TangledSSHCredentialsDiagnostics.logPreparationStarted(knotHost: knotHost)
        do {
            var stored = try storedCredentials()
            var knotInventoryAvailable = knotHost != nil

            if let knotHost {
                let inventory = try await knotKeyInventory(
                    for: stored,
                    knotHost: knotHost,
                    attempt: 1
                )
                knotInventoryAvailable = inventory != nil
                if inventory?.containsStoredKey == true {
                    TangledSSHCredentialsDiagnostics.logPreparationDone(
                        knotHost: knotHost,
                        source: "existing knot key"
                    )
                    return stored.sourceControlCredentials
                }
            }

            if knotHost != nil || stored.recordURI == nil {
                stored = try await registeredCredentials(stored, storage: storage)
            } else {
                TangledSSHCredentialsDiagnostics.logPDSLookupSkipped()
            }

            if let knotHost, knotInventoryAvailable {
                try await waitForKnotKey(stored, knotHost: knotHost)
            }

            TangledSSHCredentialsDiagnostics.logPreparationDone(
                knotHost: knotHost,
                source: stored.recordURI == nil ? "local key" : "registered key"
            )
            return stored.sourceControlCredentials
        } catch {
            TangledSSHCredentialsDiagnostics.logPreparationFailed(error, knotHost: knotHost)
            throw error
        }
    }

    private func storedCredentials() throws -> TangledStoredSSHCredentials {
        if let stored = storage.withLock({ $0 }) {
            TangledSSHCredentialsDiagnostics.logLocalKeyFound()
            return stored
        }
        if let stored = legacyStorage?.withLock({ $0 }) {
            storage.withLock { $0 = stored }
            legacyStorage?.withLock { $0 = nil }
            TangledSSHCredentialsDiagnostics.logLegacyKeyMigrationDone()
            return stored
        }

        TangledSSHCredentialsDiagnostics.logLocalKeyGenerationStarted()
        let keyPair = try generateKeyPair()
        let stored = TangledStoredSSHCredentials(
            publicKey: keyPair.publicKey,
            privateKey: keyPair.privateKey,
            name: "Open Music Event",
            createdAt: iso8601String(now())
        )
        storage.withLock { $0 = stored }
        TangledSSHCredentialsDiagnostics.logLocalKeyGenerationDone()
        return stored
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
    case knotKeyNotReady(String)
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
    TangledSSHCredentialsDiagnostics.logPDSLookupStarted()
    if let registered = try await existingCredentialsRecord(stored) {
        storage.withLock { $0 = registered }
        TangledSSHCredentialsDiagnostics.logPDSLookupDone(found: true)
        return registered
    }
    TangledSSHCredentialsDiagnostics.logPDSLookupDone(found: false)

    var stored = stored
    @Dependency(\.getDefaultSession) var getDefaultSession
    @Dependency(XRPC.Client.self) var xrpcClient
    TangledSSHCredentialsDiagnostics.logPDSRegistrationStarted()
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
    TangledSSHCredentialsDiagnostics.logPDSRegistrationDone()
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

private struct TangledKnotKeyInventory: Equatable, Sendable {
    var accountKeyCount: Int
    var containsStoredKey: Bool
}

private func knotKeyInventory(
    for stored: TangledStoredSSHCredentials,
    knotHost: ATProto.PDSHost,
    attempt: Int
) async throws -> TangledKnotKeyInventory? {
    @Dependency(\.getDefaultSession) var getDefaultSession
    @Dependency(XRPC.Client.self) var xrpcClient
    let accountDID = getDefaultSession().accountID.rawValue.description
    var accountKeyCount = 0
    var containsStoredKey = false
    var cursor: String?

    TangledSSHCredentialsDiagnostics.logKnotLookupStarted(
        knotHost: knotHost,
        attempt: attempt
    )
    repeat {
        let output: TangledKnotListKeysOutput
        do {
            output = try await xrpcClient.run(
                TangledKnotListKeysRequest(knotHost: knotHost, cursor: cursor)
            )
        } catch let HTTPError.httpError(status, _, _) where status.code == 404 {
            TangledSSHCredentialsDiagnostics.logKnotLookupUnavailable(
                knotHost: knotHost,
                attempt: attempt
            )
            return nil
        }
        for key in output.keys where key.did == accountDID {
            accountKeyCount += 1
            containsStoredKey = containsStoredKey || key.key == stored.publicKey
        }
        cursor = output.cursor
    } while cursor != nil

    let inventory = TangledKnotKeyInventory(
        accountKeyCount: accountKeyCount,
        containsStoredKey: containsStoredKey
    )
    TangledSSHCredentialsDiagnostics.logKnotLookupDone(
        inventory,
        knotHost: knotHost,
        attempt: attempt
    )
    return inventory
}

private func waitForKnotKey(
    _ stored: TangledStoredSSHCredentials,
    knotHost: ATProto.PDSHost
) async throws {
    @Dependency(\.continuousClock) var clock
    let maximumAttempts = 8
    TangledSSHCredentialsDiagnostics.logReadinessStarted(
        knotHost: knotHost,
        maximumAttempts: maximumAttempts
    )

    for attempt in 1...maximumAttempts {
        let inventory = try await knotKeyInventory(
            for: stored,
            knotHost: knotHost,
            attempt: attempt
        )
        guard let inventory else {
            TangledSSHCredentialsDiagnostics.logReadinessUnavailable(knotHost: knotHost)
            return
        }
        if inventory.containsStoredKey {
            TangledSSHCredentialsDiagnostics.logReadinessDone(
                knotHost: knotHost,
                attempt: attempt
            )
            return
        }
        if attempt < maximumAttempts {
            try await clock.sleep(for: .seconds(1))
        }
    }

    let error = TangledSSHCredentialsError.knotKeyNotReady(knotHost.rawValue)
    TangledSSHCredentialsDiagnostics.logReadinessFailed(error, knotHost: knotHost)
    throw error
}

private enum TangledSSHCredentialsDiagnostics {
    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: "fm.woody.openmusicevent",
        category: "TangledSSHCredentials"
    )
    #endif

    static func logPreparationStarted(knotHost: ATProto.PDSHost?) {
        notice("""
        Tangled SSH credential preparation started
        knot: \(knotHost?.rawValue ?? "none")
        """)
    }

    static func logPreparationDone(knotHost: ATProto.PDSHost?, source: String) {
        notice("""
        Tangled SSH credential preparation done
        knot: \(knotHost?.rawValue ?? "none")
        source: \(source)
        """)
    }

    static func logPreparationFailed(_ error: Error, knotHost: ATProto.PDSHost?) {
        failure("""
        Tangled SSH credential preparation failed
        knot: \(knotHost?.rawValue ?? "none")
        error: \(String(describing: error))
        """)
    }

    static func logLocalKeyFound() {
        notice("Tangled local SSH key lookup done\nfound: true")
    }

    static func logLocalKeyGenerationStarted() {
        notice("Tangled local SSH key generation started")
    }

    static func logLocalKeyGenerationDone() {
        notice("Tangled local SSH key generation done")
    }

    static func logLegacyKeyMigrationDone() {
        notice("Tangled local SSH key migration done\nsource: app storage\ndestination: keychain")
    }

    static func logPDSLookupStarted() {
        notice("Tangled PDS public-key lookup started")
    }

    static func logPDSLookupDone(found: Bool) {
        notice("""
        Tangled PDS public-key lookup done
        matching local key: \(found)
        """)
    }

    static func logPDSLookupSkipped() {
        notice("""
        Tangled PDS public-key lookup done
        matching local key: true
        source: stored record
        """)
    }

    static func logPDSRegistrationStarted() {
        notice("Tangled PDS public-key registration started")
    }

    static func logPDSRegistrationDone() {
        notice("Tangled PDS public-key registration done")
    }

    static func logKnotLookupStarted(knotHost: ATProto.PDSHost, attempt: Int) {
        notice("""
        Tangled knot public-key lookup started
        knot: \(knotHost.rawValue)
        attempt: \(attempt)
        """)
    }

    static func logKnotLookupDone(
        _ inventory: TangledKnotKeyInventory,
        knotHost: ATProto.PDSHost,
        attempt: Int
    ) {
        notice("""
        Tangled knot public-key lookup done
        knot: \(knotHost.rawValue)
        attempt: \(attempt)
        account keys: \(inventory.accountKeyCount)
        matching local key: \(inventory.containsStoredKey)
        """)
    }

    static func logKnotLookupUnavailable(knotHost: ATProto.PDSHost, attempt: Int) {
        notice("""
        Tangled knot public-key lookup done
        knot: \(knotHost.rawValue)
        attempt: \(attempt)
        status: unavailable (endpoint not supported)
        """)
    }

    static func logReadinessStarted(
        knotHost: ATProto.PDSHost,
        maximumAttempts: Int
    ) {
        notice("""
        Tangled SSH key readiness started
        knot: \(knotHost.rawValue)
        maximum attempts: \(maximumAttempts)
        """)
    }

    static func logReadinessDone(knotHost: ATProto.PDSHost, attempt: Int) {
        notice("""
        Tangled SSH key readiness done
        knot: \(knotHost.rawValue)
        attempt: \(attempt)
        """)
    }

    static func logReadinessUnavailable(knotHost: ATProto.PDSHost) {
        notice("""
        Tangled SSH key readiness unavailable
        knot: \(knotHost.rawValue)
        reason: knot does not expose key inventory
        """)
    }

    static func logReadinessFailed(_ error: Error, knotHost: ATProto.PDSHost) {
        failure("""
        Tangled SSH key readiness failed
        knot: \(knotHost.rawValue)
        error: \(String(describing: error))
        """)
    }

    private static func notice(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    private static func failure(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
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
