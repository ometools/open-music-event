import Dependencies
import Foundation
import Sharing

#if canImport(Security)
import Security
#endif

struct KeychainStorageItem: Hashable, Sendable {
    var service: String
    var account: String
}

struct KeychainStorageClient: Sendable {
    var data: @Sendable (KeychainStorageItem) throws -> Data?
    var setData: @Sendable (Data?, KeychainStorageItem) throws -> Void
}

enum KeychainStorageFailure: Error, Equatable, Sendable {
    case unexpectedData
    case unavailable
    case unhandledStatus(operation: String, status: Int32)
}

extension DependencyValues {
    var keychainStorage: KeychainStorageClient {
        get { self[KeychainStorageClientKey.self] }
        set { self[KeychainStorageClientKey.self] = newValue }
    }
}

private enum KeychainStorageClientKey: TestDependencyKey {
    static var testValue: KeychainStorageClient {
        .inMemory(testKeychainStorage)
    }
}

extension KeychainStorageClientKey: DependencyKey {
    static var liveValue: KeychainStorageClient {
        #if canImport(Security)
        .security
        #else
        .inMemory(nonSecurityKeychainStorage)
        #endif
    }
}

private let testKeychainStorage = InMemoryKeychainStorage()
private let nonSecurityKeychainStorage = InMemoryKeychainStorage()

extension KeychainStorageClient {
    static func inMemory(_ storage: InMemoryKeychainStorage = InMemoryKeychainStorage()) -> Self {
        Self(
            data: { item in
                storage.data(for: item)
            },
            setData: { data, item in
                storage.setData(data, for: item)
            }
        )
    }
}

final class InMemoryKeychainStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [KeychainStorageItem: Data] = [:]

    func data(for item: KeychainStorageItem) -> Data? {
        lock.withLock {
            values[item]
        }
    }

    func setData(_ data: Data?, for item: KeychainStorageItem) {
        lock.withLock {
            values[item] = data
        }
    }
}

struct KeychainSharedKey<Value: Codable & Sendable>: SharedKey {
    let item: KeychainStorageItem
    @Dependency(\.keychainStorage) private var storage

    var id: KeychainStorageItem {
        item
    }

    func load(
        context: LoadContext<Value>,
        continuation: LoadContinuation<Value>
    ) {
        do {
            let data = try storage.data(item)
            continuation.resume(
                returning: try Self.decode(data, initialValue: context.initialValue)
            )
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func save(
        _ value: Value,
        context: SaveContext,
        continuation: SaveContinuation
    ) {
        do {
            let data = try Self.encode(value)
            try storage.setData(data, item)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func subscribe(
        context _: LoadContext<Value>,
        subscriber _: SharedSubscriber<Value>
    ) -> SharedSubscription {
        SharedSubscription {}
    }

    private static func decode(
        _ data: Data?,
        initialValue: Value?
    ) throws -> Value {
        guard let data else {
            if let initialValue {
                return initialValue
            }
            throw KeychainStorageFailure.unexpectedData
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private static func encode(_ value: Value) throws -> Data? {
        if (value as? any AnyOptional)?.isNil == true {
            return nil
        }
        return try JSONEncoder().encode(value)
    }
}

private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    var isNil: Bool {
        self == nil
    }
}

#if canImport(Security)
private extension KeychainStorageClient {
    static var security: Self {
        Self(
            data: { item in
                var query = item.query
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                switch status {
                case errSecSuccess:
                    guard let data = result as? Data else {
                        throw KeychainStorageFailure.unexpectedData
                    }
                    return data

                case errSecItemNotFound:
                    return nil

                default:
                    throw KeychainStorageFailure.unhandledStatus(
                        operation: "copy",
                        status: status
                    )
                }
            },
            setData: { data, item in
                if let data {
                    let updateStatus = SecItemUpdate(
                        item.query as CFDictionary,
                        [kSecValueData as String: data] as CFDictionary
                    )
                    switch updateStatus {
                    case errSecSuccess:
                        return

                    case errSecItemNotFound:
                        var query = item.query
                        query[kSecValueData as String] = data
                        let addStatus = SecItemAdd(query as CFDictionary, nil)
                        guard addStatus == errSecSuccess else {
                            throw KeychainStorageFailure.unhandledStatus(
                                operation: "add",
                                status: addStatus
                            )
                        }

                    default:
                        throw KeychainStorageFailure.unhandledStatus(
                            operation: "update",
                            status: updateStatus
                        )
                    }
                } else {
                    let deleteStatus = SecItemDelete(item.query as CFDictionary)
                    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
                    else {
                        throw KeychainStorageFailure.unhandledStatus(
                            operation: "delete",
                            status: deleteStatus
                        )
                    }
                }
            }
        )
    }
}

private extension KeychainStorageItem {
    var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
