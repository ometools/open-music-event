import ATProtoOAuth
import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import Foundation
#if os(Android)
import SkipKeychain
#endif

public enum OpenMusicEventServiceEnvironment: String, CaseIterable, Equatable, Hashable, Sendable {
    case production
    case staging

    public static let userDefaultsKey = "openMusicEventServiceEnvironment"

    public static func persisted(
        userDefaults: UserDefaults = .standard
    ) -> Self {
        userDefaults.string(forKey: userDefaultsKey).flatMap(Self.init(rawValue:))
            ?? .production
    }

    public var serverURL: URL {
        switch self {
        case .production:
            URL(string: "https://openmusicevent.app")!
        case .staging:
            URL(string: "https://stg.openmusicevent.app")!
        }
    }
}

enum OpenMusicEventServiceEnvironmentKey: DependencyKey {
    static var liveValue: OpenMusicEventServiceEnvironment { .production }
    static var testValue: OpenMusicEventServiceEnvironment { .production }
}

public extension DependencyValues {
    var openMusicEventServiceEnvironment: OpenMusicEventServiceEnvironment {
        get { self[OpenMusicEventServiceEnvironmentKey.self] }
        set { self[OpenMusicEventServiceEnvironmentKey.self] = newValue }
    }
}

public enum OpenMusicEventNotificationAuthorization {
    public static let serverURL = OpenMusicEventServiceEnvironment.production.serverURL

    static let credentialKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "notifications.installationCredential"
    )

    static let stagingCredentialKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "notifications.installationCredential.staging"
    )

    public static func prepareDependencies(
        _ dependencies: inout DependencyValues,
        environment: OpenMusicEventServiceEnvironment = .production
    ) {
        let storage = credentialStorage(dependencies, environment: environment)
        dependencies.notificationHTTPAuthorization = .anonymousNotificationInstallation(
            baseURL: environment.serverURL,
            storage: storage
        )
    }

    static func credentialStorage(
        _ dependencies: DependencyValues,
        environment: OpenMusicEventServiceEnvironment = .production
    ) -> NotificationInstallationCredentialStorage {
        #if os(Android)
        let key = switch environment {
        case .production:
            "fm.woody.openMusicEvent.notifications.installationCredential"
        case .staging:
            "fm.woody.openMusicEvent.notifications.installationCredential.staging"
        }
        return NotificationInstallationCredentialStorage(
            credential: {
                Keychain.shared.string(forKey: key).map {
                    NotificationInstallation.Credential(rawValue: $0)
                }
            },
            setCredential: { credential in
                if let credential {
                    Keychain.shared.set(credential.rawValue, forKey: key)
                } else {
                    Keychain.shared.removeValue(forKey: key)
                }
            }
        )
        #else
        let keychainItem = switch environment {
        case .production:
            Self.credentialKeychainItem
        case .staging:
            Self.stagingCredentialKeychainItem
        }
        let keychainStorage = dependencies.keychainStorage
        return NotificationInstallationCredentialStorage(
            credential: {
                guard let data = try keychainStorage.data(keychainItem) else {
                    return nil
                }
                guard let value = String(data: data, encoding: .utf8) else {
                    throw KeychainStorageFailure.unexpectedData
                }
                return NotificationInstallation.Credential(rawValue: value)
            },
            setCredential: { credential in
                try keychainStorage.setData(
                    credential.map { Data($0.rawValue.utf8) },
                    keychainItem
                )
            }
        )
        #endif
    }
}
