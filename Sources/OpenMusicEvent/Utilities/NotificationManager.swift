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

struct Box<T>: @unchecked Sendable {
    let rawValue: T
}

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

    @MainActor
    public func applicationDidLaunch() async throws {
        #if os(Android)
        // Android handles push tokens automatically
        #else
        // Register for remote notifications to get APNs token
        UIApplication.shared.registerForRemoteNotifications()
        _ = await self.requestPermission()
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

    @MainActor
    public func requestPermission() async -> Bool {

        hasRequestedPermission = true
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            print("RECEIVED: \(granted)")
            isAuthorized = granted
            saveState()
            try await self.ensureTopicsAreSubscribed()
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

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    func ensureTopicsAreSubscribed() async throws {
        let channels = try await defaultDatabase.read { try CommunicationChannel.fetchAll($0) }

        try await self.updateTopicSubscription("data-updates", to: .subscribed)

        for channel in channels {
            if let topic = channel.firebaseTopicName, let state = channel.userNotificationState {
                try await self.updateTopicSubscription(topic, to: state)
            }
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

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        logger.info("Notification tapped: \(content.title): \(content.body)")

        nonisolated(unsafe) let userInfo = content.userInfo

        _ = Messaging.messaging().appDidReceiveMessage(userInfo)

        if let channelID = content.userInfo(for: "channel").map(CommunicationChannel.ID.init(rawValue:)),
           let postID = content.userInfo(for: "post-stub").map(CommunicationChannel.Post.Stub.init(rawValue:)) {
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .userSelectedToViewPost,
                    object: nil,
                    info: .viewPost(channelID: channelID, postID: postID)
                )
            }
        }
    }

//    #if os(iOS)
//    func application(_ application: UIApplication,
//                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
//      -> UIBackgroundFetchResult {
//      // If you are receiving a notification message while your app is in the background,
//      // this callback will not be fired till the user taps on the notification launching the application.
//      // TODO: Handle data of notification
//
//
//      // With swizzling disabled you must let Messaging know about the message, for Analytics
//       Messaging.messaging().appDidReceiveMessage(userInfo)
//
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
//    #endif

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
