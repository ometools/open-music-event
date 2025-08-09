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
        if !self.hasRequestedPermission {
            try await self.requestPermission()
        }
        
        #if os(Android)
        // Android handles push tokens automatically
        #else
        // Register for remote notifications to get APNs token
        await UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    
    // MARK: - APNs Token Handling
    
    public func didRegisterForRemoteNotificationsWithDeviceToken(_ deviceToken: Data) {
        #if !os(Android)
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Token: \(tokenString)")

        // Set APNs token for Firebase
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }
    
    public func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        logger.error("Failed to register for remote notifications: \(error)")
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
    public func updateTopicSubscription(_ topicID: CommunicationChannel.FirebaseTopicName, to state: CommunicationChannel.UserNotificationState) async throws {
        switch state {
        case .subscribed:
            logger.debug("subscribe to topic \(topicID.rawValue)")
            try await Messaging.messaging().subscribe(toTopic: topicID.rawValue)
        case .unsubscribed:
            logger.info("unsubscribed from topic \(topicID.rawValue)")
            try await Messaging.messaging().unsubscribe(fromTopic: topicID.rawValue)
        }
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
        
        Messaging.messaging().appDidReceiveMessage(content.userInfo)

        logger.info("Will present notification: \(content.title): \(content.body)")
        
        return [.banner, .sound, .badge]
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        logger.info("Notification tapped: \(content.title): \(content.body)")

        Messaging.messaging().appDidReceiveMessage(content.userInfo)

        if let organizationURL = content.userInfo(for: "organizationURL").flatMap(URL.init(string:)),
           let channelID = content.userInfo(for: "channelID").map(CommunicationChannel.ID.init(rawValue:)),
           let postID = content.userInfo(for: "postID").map(CommunicationChannel.Post.ID.init(rawValue:)) {

            await withErrorReporting {
                try await downloadAndStoreOrganizer(from: .url(organizationURL))

                NotificationCenter.default.post(
                    name: .userSelectedToViewPost,
                    object: nil,
                    info: .viewPost(channelID: channelID, postID: postID)
                )
            }

        }
    }
//
//    func application(_ application: UIApplication,
//                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
//      -> UIBackgroundFetchResult {
//      // If you are receiving a notification message while your app is in the background,
//      // this callback will not be fired till the user taps on the notification launching the application.
//      // TODO: Handle data of notification
//
//      // With swizzling disabled you must let Messaging know about the message, for Analytics
//      // Messaging.messaging().appDidReceiveMessage(userInfo)
//
//      // Print message ID.
////      if let messageID = userInfo[gcmMessageIDKey] {
////        print("Message ID: \(messageID)")
////      }
//
//      // Print full message.
//      print(userInfo)
//
//      return UIBackgroundFetchResult.newData
//    }

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

extension UNNotificationContent {
    func userInfo(for key: AnyHashable) -> String? {
        self.userInfo[key] as? String
    }
}
