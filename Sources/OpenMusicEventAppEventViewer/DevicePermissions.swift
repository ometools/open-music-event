import Dependencies
import Foundation
import Sharing
import SkipKit
#if os(Android)
import SkipSwiftUI
#elseif os(iOS)
import UIKit
import UserNotifications
#endif

public struct DevicePermissions: Equatable, Sendable {
    public enum NotificationAuthorization: Equatable, Sendable {
        case authorized
        case denied
        case limited
        case restricted
        case unknown
    }

    public var notifications: NotificationAuthorization

    public init(notifications: NotificationAuthorization = .unknown) {
        self.notifications = notifications
    }

    public var notificationSetupBadgeValue: Int? {
        notifications == .unknown ? 1 : nil
    }

    public var notificationsAreAllowed: Bool {
        notifications == .authorized || notifications == .limited
    }
}

public struct DevicePermissionsClient: Sendable {
    public var load: @Sendable () async -> DevicePermissions
    public var openNotificationSettings: @MainActor @Sendable () async -> Bool
    public var requestNotifications: @Sendable () async throws -> DevicePermissions.NotificationAuthorization

    public init(
        load: @escaping @Sendable () async -> DevicePermissions,
        openNotificationSettings: @escaping @MainActor @Sendable () async -> Bool,
        requestNotifications: @escaping @Sendable () async throws -> DevicePermissions.NotificationAuthorization
    ) {
        self.load = load
        self.openNotificationSettings = openNotificationSettings
        self.requestNotifications = requestNotifications
    }
}

extension DevicePermissionsClient: DependencyKey {
    public static let liveValue = Self(
        load: {
            let authorization = await PermissionManager.queryPostNotificationPermission()
            #if os(Android)
            if authorization == .unknown,
               UserDefaults.standard.bool(forKey: notificationPermissionWasRequestedKey)
            {
                return DevicePermissions(notifications: .denied)
            }
            #endif
            return DevicePermissions(notifications: authorization.devicePermissionAuthorization)
        },
        openNotificationSettings: {
            #if os(Android)
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
                return false
            }
            return await UIApplication.shared.open(url, options: [:])
            #elseif os(iOS)
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
                return false
            }
            return await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
            #else
            return false
            #endif
        },
        requestNotifications: {
            #if os(iOS)
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .criticalAlert, .sound]
            )
            let authorization = await PermissionManager.queryPostNotificationPermission()
            #else
            let authorization = try await PermissionManager.requestPostNotificationPermission(
                alert: true,
                sound: true,
                badge: true
            )
            #endif
            #if os(Android)
            UserDefaults.standard.set(true, forKey: notificationPermissionWasRequestedKey)
            #endif
            return authorization.devicePermissionAuthorization
        }
    )

    public static let testValue = Self(
        load: { DevicePermissions() },
        openNotificationSettings: { false },
        requestNotifications: { .unknown }
    )
}

public extension DependencyValues {
    var devicePermissions: DevicePermissionsClient {
        get { self[DevicePermissionsClient.self] }
        set { self[DevicePermissionsClient.self] = newValue }
    }
}

public struct DevicePermissionsKey: SharedReaderKey {
    public init() {}

    public var id: String { "devicePermissions" }

    @Dependency(\.devicePermissions) var devicePermissions

    public func load(
        context: LoadContext<DevicePermissions>,
        continuation: LoadContinuation<DevicePermissions>
    ) {
        Task {
            continuation.resume(returning: await devicePermissions.load())
        }
    }

    public func subscribe(
        context: LoadContext<DevicePermissions>,
        subscriber: SharedSubscriber<DevicePermissions>
    ) -> SharedSubscription {
        SharedSubscription {}
    }
}

public extension SharedReaderKey where Self == DevicePermissionsKey.Default {
    static var devicePermissions: Self {
        Self[DevicePermissionsKey(), default: DevicePermissions()]
    }
}

extension PermissionAuthorization {
    var devicePermissionAuthorization: DevicePermissions.NotificationAuthorization {
        switch self {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .limited:
            .limited
        case .restricted:
            .restricted
        case .unknown:
            .unknown
        }
    }
}

#if os(Android)
let notificationPermissionWasRequestedKey = "devicePermissions.notifications.wasRequested"
#endif
