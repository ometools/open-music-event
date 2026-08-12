import ComposableNotifications
import Crypto
import Foundation

/// Authenticated encryption for provider-issued notification destinations stored by the AppView.
///
/// The deployment owns the key bytes and supplies them through ``AppViewConfiguration``. The
/// database stores only AES-GCM combined ciphertext and the key version required to open it.
public struct NotificationDestinationProtection: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidBase64Key
        case invalidKeyLength(Int)
        case invalidKeyVersion(Int)
        case missingCombinedCiphertext
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
            keyVersion: storedKeyVersion
        )
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(
            sealedBox,
            using: key,
            authenticating: context.authenticatedData
        )
        guard let rawValue = String(data: plaintext, encoding: .utf8) else {
            throw NotificationPersistenceError.invalidDestinationEncoding
        }
        return rawValue
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
    var value: String

    init(_ destination: Push.Destination) {
        switch destination {
        case .apns(let registration):
            self.init(
                applicationID: registration.applicationID,
                provider: .apns,
                value: registration.deviceToken.rawValue
            )
        case .fcm(let registration):
            self.init(
                applicationID: registration.applicationID,
                provider: .fcm,
                value: registration.registrationToken.rawValue
            )
        }
    }

    init(applicationID: Push.ApplicationID, provider: Provider, value: String) {
        self.applicationID = applicationID
        self.provider = provider
        self.value = value
    }

    var destination: Push.Destination {
        switch provider {
        case .apns:
            .apns(
                Push.APNS(
                    applicationID: applicationID,
                    deviceToken: .init(rawValue: value)
                )
            )
        case .fcm:
            .fcm(
                Push.FCM(
                    applicationID: applicationID,
                    registrationToken: .init(rawValue: value)
                )
            )
        }
    }

    var fingerprintData: Data {
        canonicalNotificationData([
            applicationID.rawValue,
            provider.rawValue,
            value,
        ])
    }
}

private struct NotificationDestinationEncryptionContext {
    var installationID: NotificationInstallation.ID
    var applicationID: Push.ApplicationID
    var provider: PersistedNotificationDestination.Provider
    var keyVersion: Int

    var authenticatedData: Data {
        canonicalNotificationData([
            installationID.rawValue,
            applicationID.rawValue,
            provider.rawValue,
            String(keyVersion),
        ])
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
