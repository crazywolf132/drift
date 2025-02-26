//
//  NotificationManager.swift
//  Drift
//
//  Created by Brayden Moon
//

import Foundation
import UserNotifications

/// Manages user notifications throughout the application
class NotificationManager {
    /// Shared singleton instance
    static let shared = NotificationManager()
    
    /// Notification content object that's reused to reduce allocations
    private let notificationContent = UNMutableNotificationContent()
    
    private init() {}
    
    /// Shows a notification to the user
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message content
    func showNotification(title: String, message: String) {
        DispatchQueue.main.async {
            self.notificationContent.title = title
            self.notificationContent.body = message
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: self.notificationContent,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error showing notification: \(error.localizedDescription)")
                }
            }
        }
    }
} 