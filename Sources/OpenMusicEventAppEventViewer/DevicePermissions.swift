import Dependencies
import Foundation
import Sharing
#if os(Android) || os(iOS)
import SkipKit
#endif
#if os(Android)
import SkipSwiftUI
#elseif os(iOS)
import UIKit
import UserNotifications
#elseif canImport(UserNotifications)
import UserNotifications
#endif

public struct DevicePermissions: Equatable, Sendable {
    public enum CriticalAlertAuthorization: Equatable, Sendable {
        case disabled
        case enabled
        case unavailable
    }

    public enum NotificationAuthorization: Equatable, Sendable {
        case authorized
        case denied
        case limited
        case restricted
        case unknown
    }

    public var criticalAlerts: CriticalAlertAuthorization
    public var notifications: NotificationAuthorization

    public init(
        criticalAlerts: CriticalAlertAuthorization = .unavailable,
        notifications: NotificationAuthorization = .unknown
    ) {
        self.criticalAlerts = criticalAlerts
        self.notifications = notifications
    }

    public var notificationSetupBadgeValue: Int? {
        notifications == .unknown
            || (notificationsAreAllowed && criticalAlerts == .disabled)
            ? 1
            : nil
    }

    public var notificationsAreAllowed: Bool {
        notifications == .authorized || notifications == .limited
    }
}

public struct DevicePermissionsClient: Sendable {
    public var load: @Sendable () async -> DevicePermissions
    public var openNotificationSettings: @MainActor @Sendable () async -> Bool
    public var requestCriticalAlerts: @Sendable () async throws -> DevicePermissions.CriticalAlertAuthorization
    public var requestNotifications: @Sendable () async throws -> DevicePermissions.NotificationAuthorization

    public init(
        load: @escaping @Sendable () async -> DevicePermissions,
        openNotificationSettings: @escaping @MainActor @Sendable () async -> Bool,
        requestCriticalAlerts: @escaping @Sendable () async throws -> DevicePermissions.CriticalAlertAuthorization,
        requestNotifications: @escaping @Sendable () async throws -> DevicePermissions.NotificationAuthorization
    ) {
        self.load = load
        self.openNotificationSettings = openNotificationSettings
        self.requestCriticalAlerts = requestCriticalAlerts
        self.requestNotifications = requestNotifications
    }
}

extension DevicePermissionsClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.deviceSupportsCriticalAlerts) var supportsCriticalAlerts
        return live(supportsCriticalAlerts: supportsCriticalAlerts)
    }

    public static func live(supportsCriticalAlerts: Bool) -> Self {
        Self(
            load: {
                #if os(iOS)
                let authorization = await PermissionManager.queryPostNotificationPermission()
                let criticalAlerts = await UNUserNotificationCenter.current()
                    .notificationSettings()
                    .criticalAlertSetting
                    .devicePermissionAuthorization(
                        supportsCriticalAlerts: supportsCriticalAlerts
                    )
                return DevicePermissions(
                    criticalAlerts: criticalAlerts,
                    notifications: authorization.devicePermissionAuthorization
                )
                #elseif os(Android)
                let authorization = await PermissionManager.queryPostNotificationPermission()
                if authorization == .unknown,
                   UserDefaults.standard.bool(forKey: notificationPermissionWasRequestedKey)
                {
                    return DevicePermissions(
                        criticalAlerts: .unavailable,
                        notifications: .denied
                    )
                }
                return DevicePermissions(
                    criticalAlerts: .unavailable,
                    notifications: authorization.devicePermissionAuthorization
                )
                #else
                return DevicePermissions()
                #endif
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
            requestCriticalAlerts: {
                #if os(iOS)
                guard supportsCriticalAlerts else { return .unavailable }
                _ = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.criticalAlert]
                )
                return await UNUserNotificationCenter.current()
                    .notificationSettings()
                    .criticalAlertSetting
                    .devicePermissionAuthorization(
                        supportsCriticalAlerts: supportsCriticalAlerts
                    )
                #else
                return .unavailable
                #endif
            },
            requestNotifications: {
                #if os(iOS)
                _ = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                let authorization = await PermissionManager.queryPostNotificationPermission()
                return authorization.devicePermissionAuthorization
                #elseif os(Android)
                let authorization = try await PermissionManager.requestPostNotificationPermission(
                    alert: true,
                    sound: true,
                    badge: true
                )
                UserDefaults.standard.set(true, forKey: notificationPermissionWasRequestedKey)
                return authorization.devicePermissionAuthorization
                #else
                return .unknown
                #endif
            }
        )
    }

    public static var testValue: Self {
        Self(
            load: { DevicePermissions() },
            openNotificationSettings: { false },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: { .unknown }
        )
    }
}

private enum DeviceSupportsCriticalAlertsKey: DependencyKey {
    static let liveValue = false
    static let testValue = false
}

public extension DependencyValues {
    var deviceSupportsCriticalAlerts: Bool {
        get { self[DeviceSupportsCriticalAlertsKey.self] }
        set { self[DeviceSupportsCriticalAlertsKey.self] = newValue }
    }

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

#if os(Android) || os(iOS)
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
#endif

#if canImport(UserNotifications)
extension UNNotificationSetting {
    func devicePermissionAuthorization(
        supportsCriticalAlerts: Bool
    ) -> DevicePermissions.CriticalAlertAuthorization {
        guard supportsCriticalAlerts else { return .unavailable }

        return switch self {
        case .disabled:
            .disabled
        case .enabled:
            .enabled
        case .notSupported:
            .disabled
        @unknown default:
            .unavailable
        }
    }
}
#endif

#if os(Android)
let notificationPermissionWasRequestedKey = "devicePermissions.notifications.wasRequested"
#endif
