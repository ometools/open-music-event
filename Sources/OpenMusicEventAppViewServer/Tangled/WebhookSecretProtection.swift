import Crypto
import Foundation

public struct WebhookSecretProtection: Sendable {
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
        _ secret: Data,
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID
    ) throws -> Data {
        let context = WebhookSecretEncryptionContext(
            source: source,
            watchID: watchID,
            keyVersion: keyVersion
        )
        let sealedBox = try AES.GCM.seal(
            secret,
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
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID,
        keyVersion storedKeyVersion: Int
    ) throws -> Data {
        guard storedKeyVersion == keyVersion else {
            throw Error.unsupportedKeyVersion(storedKeyVersion)
        }
        let context = WebhookSecretEncryptionContext(
            source: source,
            watchID: watchID,
            keyVersion: storedKeyVersion
        )
        return try AES.GCM.open(
            AES.GCM.SealedBox(combined: ciphertext),
            using: key,
            authenticating: context.authenticatedData
        )
    }
}

extension WebhookSecretProtection: CustomDebugStringConvertible {
    public var debugDescription: String {
        "WebhookSecretProtection(keyVersion: \(keyVersion), key: <redacted>)"
    }
}

extension WebhookSecretProtection: CustomReflectable {
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

extension WebhookSecretProtection: CustomStringConvertible {
    public var description: String { debugDescription }
}

private struct WebhookSecretEncryptionContext {
    var source: WebhookInboxDelivery.Source
    var watchID: WebhookInboxDelivery.WatchID
    var keyVersion: Int

    var authenticatedData: Data {
        canonicalWebhookData([
            "open-music-event:webhook-secret",
            source.rawValue,
            watchID.rawValue,
            String(keyVersion),
        ])
    }
}

private func canonicalWebhookData(_ values: [String]) -> Data {
    var data = Data()
    for value in values {
        let valueData = Data(value.utf8)
        var length = UInt64(valueData.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(valueData)
    }
    return data
}
