import ComposableNotifications
import ComposableNotificationsServer
import Crypto
import Foundation
import Tagged

/// Authenticated encryption for provider-issued notification destinations stored by the AppView.
///
/// The deployment owns the key bytes and supplies them through ``AppViewConfiguration``. The
/// database stores only AES-GCM combined ciphertext and the key version required to open it.
public struct NotificationDestinationProtection: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidBase64Key
        case invalidKeyLength(Int)
        case invalidKeyVersion(Int)
        case invalidDestinationEncoding
        case missingCombinedCiphertext
        case missingAPNSEnvironment(Push.ApplicationID)
        case unsupportedKeyVersion(Int)
    }

    public let keyVersion: Int
    private let key: SymmetricKey

    public init(keyData: Data, keyVersion: Int = 1) throws {
        guard keyData.count == 32 else {
            throw Error.invalidKeyLength(keyData.count)
        }
        guard keyVersion > 0 else {
            throw Error.invalidKeyVersion(keyVersion)
        }
        self.keyVersion = keyVersion
        self.key = SymmetricKey(data: keyData)
    }

    public init(base64EncodedKey: String, keyVersion: Int = 1) throws {
        guard let keyData = Data(base64Encoded: base64EncodedKey) else {
            throw Error.invalidBase64Key
        }
        try self.init(keyData: keyData, keyVersion: keyVersion)
    }

    func seal(
        _ destination: PersistedNotificationDestination,
        for installationID: NotificationInstallation.ID
    ) throws -> Data {
        let context = NotificationDestinationEncryptionContext(
            installationID: installationID,
            applicationID: destination.applicationID,
            provider: destination.provider,
            apnsEnvironment: destination.apnsEnvironment,
            keyVersion: keyVersion
        )
        let sealedBox = try AES.GCM.seal(
            Data(destination.value.utf8),
            using: key,
            authenticating: context.authenticatedData
        )
        guard let combined = sealedBox.combined else {
            throw Error.missingCombinedCiphertext
        }
        return combined
    }

    func open(
        _ ciphertext: Data,
        applicationID: Push.ApplicationID,
        provider: PersistedNotificationDestination.Provider,
        apnsEnvironment: Push.APNS.Environment?,
        installationID: NotificationInstallation.ID,
        keyVersion storedKeyVersion: Int
    ) throws -> String {
        guard storedKeyVersion == keyVersion else {
            throw Error.unsupportedKeyVersion(storedKeyVersion)
        }
        let context = NotificationDestinationEncryptionContext(
            installationID: installationID,
            applicationID: applicationID,
            provider: provider,
            apnsEnvironment: apnsEnvironment,
            keyVersion: storedKeyVersion
        )
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(
            sealedBox,
            using: key,
            authenticating: context.authenticatedData
        )
        guard let rawValue = String(data: plaintext, encoding: .utf8) else {
            throw Error.invalidDestinationEncoding
        }
        return rawValue
    }
}

extension NotificationDestinationProtection {
    public var client: NotificationDestinationProtectionClient {
        client(legacyAPNSEnvironments: [:])
    }

    public func client(
        legacyAPNSEnvironments: [Push.ApplicationID: Push.APNS.Environment]
    ) -> NotificationDestinationProtectionClient {
        NotificationDestinationProtectionClient(
            protect: { destination, installationID in
                let persisted = PersistedNotificationDestination(destination)
                return ProtectedNotificationDestination(
                    applicationID: persisted.applicationID,
                    apnsEnvironment: persisted.apnsEnvironment,
                    provider: persisted.provider.protectedProvider,
                    ciphertext: try seal(persisted, for: installationID),
                    fingerprint: Data(
                        SHA256.hash(data: persisted.fingerprintData)
                    )
                    .base64EncodedString(),
                    keyVersion: keyVersion
                )
            },
            reveal: { protected, installationID in
                let provider = PersistedNotificationDestination.Provider(protected.provider)
                let value = try open(
                    protected.ciphertext,
                    applicationID: protected.applicationID,
                    provider: provider,
                    apnsEnvironment: protected.apnsEnvironment,
                    installationID: installationID,
                    keyVersion: protected.keyVersion
                )
                let resolvedAPNSEnvironment: Push.APNS.Environment?
                switch provider {
                case .apns:
                    guard
                        let environment = protected.apnsEnvironment
                            ?? legacyAPNSEnvironments[protected.applicationID]
                    else {
                        throw Error.missingAPNSEnvironment(protected.applicationID)
                    }
                    resolvedAPNSEnvironment = environment
                case .fcm:
                    resolvedAPNSEnvironment = nil
                }
                return try PersistedNotificationDestination(
                    applicationID: protected.applicationID,
                    provider: provider,
                    apnsEnvironment: resolvedAPNSEnvironment,
                    value: value
                )
                .destination()
            }
        )
    }
}

extension NotificationDestinationProtection: CustomDebugStringConvertible {
    public var debugDescription: String {
        "NotificationDestinationProtection(keyVersion: \(keyVersion), key: <redacted>)"
    }
}

extension NotificationDestinationProtection: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "keyVersion": keyVersion,
                "key": "<redacted>",
            ],
            displayStyle: .struct
        )
    }
}

extension NotificationDestinationProtection: CustomStringConvertible {
    public var description: String { debugDescription }
}

struct PersistedNotificationDestination: Equatable, Sendable {
    enum Provider: String, Sendable {
        case apns
        case fcm
    }

    var applicationID: Push.ApplicationID
    var provider: Provider
    var apnsEnvironment: Push.APNS.Environment?
    var value: String

    init(_ destination: Push.Destination) {
        switch destination {
        case .apns(let registration):
            self.init(
                applicationID: registration.applicationID,
                provider: .apns,
                apnsEnvironment: registration.environment,
                value: registration.deviceToken.rawValue
            )
        case .fcm(let registration):
            self.init(
                applicationID: registration.applicationID,
                provider: .fcm,
                apnsEnvironment: nil,
                value: registration.registrationToken.rawValue
            )
        }
    }

    init(
        applicationID: Push.ApplicationID,
        provider: Provider,
        apnsEnvironment: Push.APNS.Environment?,
        value: String
    ) {
        self.applicationID = applicationID
        self.provider = provider
        self.apnsEnvironment = apnsEnvironment
        self.value = value
    }

    func destination() throws -> Push.Destination {
        switch provider {
        case .apns:
            guard let apnsEnvironment else {
                throw NotificationDestinationProtection.Error.missingAPNSEnvironment(
                    applicationID
                )
            }
            return .apns(
                Push.APNS(
                    applicationID: applicationID,
                    environment: apnsEnvironment,
                    deviceToken: .init(rawValue: value)
                )
            )
        case .fcm:
            return .fcm(
                Push.FCM(
                    applicationID: applicationID,
                    installationID: .init(rawValue: value)
                )
            )
        }
    }

    var fingerprintData: Data {
        var values = [
            applicationID.rawValue,
            provider.rawValue,
        ]
        if let apnsEnvironment {
            values.append(apnsEnvironment.rawValue)
        }
        values.append(value)
        return canonicalNotificationData(values)
    }
}

private extension PersistedNotificationDestination.Provider {
    init(_ provider: ProtectedNotificationDestination.Provider) {
        switch provider {
        case .apns: self = .apns
        case .fcm: self = .fcm
        }
    }

    var protectedProvider: ProtectedNotificationDestination.Provider {
        switch self {
        case .apns: .apns
        case .fcm: .fcm
        }
    }
}

private struct NotificationDestinationEncryptionContext {
    var installationID: NotificationInstallation.ID
    var applicationID: Push.ApplicationID
    var provider: PersistedNotificationDestination.Provider
    var apnsEnvironment: Push.APNS.Environment?
    var keyVersion: Int

    var authenticatedData: Data {
        var values = [
            installationID.rawValue,
            applicationID.rawValue,
            provider.rawValue,
            String(keyVersion),
        ]
        if let apnsEnvironment {
            values.append(apnsEnvironment.rawValue)
        }
        return canonicalNotificationData(values)
    }
}

private func canonicalNotificationData(_ values: [String]) -> Data {
    var data = Data()
    for value in values {
        let valueData = Data(value.utf8)
        var length = UInt64(valueData.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(valueData)
    }
    return data
}
