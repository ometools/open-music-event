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

@Observable
public final class NotificationPermissionManager: @unchecked Sendable {
    private(set) var isAuthorized: Bool = false
    private(set) var hasRequestedPermission: Bool = false
    
    private let hasRequestedKey = "hasRequestedNotificationPermission"
    private let isAuthorizedKey = "notificationPermissionAuthorized"
    
    public init() {
        loadStoredState()
    }

    static let shared = NotificationPermissionManager()

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
}

enum NotificationPermissionManagerDependencyKey: DependencyKey {
    public static let liveValue = NotificationPermissionManager.shared
    public static let testValue = NotificationPermissionManager.shared
}

extension DependencyValues {
    public var notificationPermissionManager: NotificationPermissionManager {
        get { self[NotificationPermissionManagerDependencyKey.self] }
        set { self[NotificationPermissionManagerDependencyKey.self] = newValue }
    }
}
