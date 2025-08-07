//
//  NotificationPermissionManager.swift
//  open-music-event
//
//  Created by Claude Code on 8/3/25.
//

import Foundation
import SwiftUI
import Dependencies
#if canImport(UserNotifications)
import UserNotifications
#endif

import SkipFuse

#if os(Android)
import SkipFirebaseCore
import SkipFirebaseMessaging
#else
import FirebaseCore
import FirebaseMessaging
#endif

/* SKIP @bridge */
@Observable
public final class NotificationManager: NSObject, @unchecked Sendable, MessagingDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "ome.OpenMusicEvent", category: "NotificationManager")
    
    private(set) var isAuthorized: Bool = false
    private(set) var hasRequestedPermission: Bool = false

    private(set) var fcmToken: String?

    private let hasRequestedKey = "hasRequestedNotificationPermission"
    private let isAuthorizedKey = "notificationPermissionAuthorized"
    
    public override init() {
        super.init()
        loadStoredState()
    }

    static let shared = NotificationManager()

    public func applicationDidLaunch() async throws {
        #if os(Android)
        
        #else
        await UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private func loadStoredState() {
        hasRequestedPermission = UserDefaults.standard.bool(forKey: hasRequestedKey)
        isAuthorized = UserDefaults.standard.bool(forKey: isAuthorizedKey)
    }
    
    private func saveState() {
        UserDefaults.standard.set(hasRequestedPermission, forKey: hasRequestedKey)
        UserDefaults.standard.set(isAuthorized, forKey: isAuthorizedKey)
    }
    
    public func requestPermission() async -> Bool {
        guard !hasRequestedPermission else {
            return isAuthorized
        }
        
        hasRequestedPermission = true
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            saveState()
            return granted
        } catch {
            isAuthorized = false
            saveState()
            return false
        }
    }
    
    @MainActor public func openSettings() {
        #if canImport(UIKit) && !SKIP
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        #endif
    }
    
    public var shouldShowPermissionRequest: Bool {
        return !hasRequestedPermission
    }
    
    public var shouldShowSettingsPrompt: Bool {
        return hasRequestedPermission && !isAuthorized
    }

    // MARK: - Topic Management
    
    public func subscribeToTopic(_ topic: String) async throws {
        try await Messaging.messaging().subscribe(toTopic: topic)
        logger.info("Subscribed to topic: \(topic)")
    }
    
    public func unsubscribeFromTopic(_ topic: String) async throws {
        try await Messaging.messaging().unsubscribe(fromTopic: topic)
        logger.info("Unsubscribed from topic: \(topic)")
    }
    
    // MARK: - MessagingDelegate
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        logger.info("FCM token received: \(token ?? "nil")")
        
        Task { @MainActor in
            self.fcmToken = token
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        logger.info("Will present notification: \(content.title): \(content.body)")
        
        return [.banner, .sound, .badge]
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        logger.info("Notification tapped: \(content.title): \(content.body)")
        
        // Handle deep linking
        if let channelId = content.userInfo["channelId"] as? String {
            await handleNotificationTap(channelId: channelId, userInfo: content.userInfo)
        }
    }
    
    private func handleNotificationTap(channelId: String, userInfo: [AnyHashable: Any]) async {
        // TODO: Implement deep linking to specific communication channels
        logger.info("Handling notification tap for channel: \(channelId)")
    }
}

enum NotificationError: LocalizedError {
    case firebaseNotConfigured
    case subscriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase is not properly configured"
        case .subscriptionFailed(let topic):
            return "Failed to manage subscription for topic: \(topic)"
        }
    }
}

enum NotificationPermissionManagerDependencyKey: DependencyKey {
    public static let liveValue = NotificationManager.shared
    public static let testValue = NotificationManager.shared
}

extension DependencyValues {
    public var notificationManager: NotificationManager {
        get { self[NotificationPermissionManagerDependencyKey.self] }
        set { self[NotificationPermissionManagerDependencyKey.self] = newValue }
    }
}
