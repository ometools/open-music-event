import ATProtoOAuth
import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import Foundation
#if os(Android)
import SkipKeychain
#endif

public enum OpenMusicEventNotificationAuthorization {
    public static let serverURL = URL(string: "https://openmusicevent.app")!

    static let credentialKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "notifications.installationCredential"
    )

    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        let storage = credentialStorage(dependencies)
        dependencies.notificationRequestInterceptors = [
            .anonymousNotificationInstallation(
                baseURL: serverURL,
                storage: storage
            )
        ]
    }

    static func credentialStorage(
        _ dependencies: DependencyValues
    ) -> NotificationInstallationCredentialStorage {
        #if os(Android)
        let key = "fm.woody.openMusicEvent.notifications.installationCredential"
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
        let keychainStorage = dependencies.keychainStorage
        return NotificationInstallationCredentialStorage(
            credential: {
                guard let data = try keychainStorage.data(credentialKeychainItem) else {
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
                    credentialKeychainItem
                )
            }
        )
        #endif
    }
}
