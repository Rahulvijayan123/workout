import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    /// Check current notification authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
        
        // Save to UserDefaults for badge tracking
        if isAuthorized {
            UserDefaults.standard.set(true, forKey: "hasEnabledNotifications")
        }
    }
    
    /// Request notification authorization
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await checkAuthorizationStatus()
            
            if granted {
                UserDefaults.standard.set(true, forKey: "hasEnabledNotifications")
            }
            
            return granted
        } catch {
            print("[Notifications] Authorization error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Workout Reminders
    
    /// Schedule a workout reminder for a specific day and time
    func scheduleWorkoutReminder(
        weekday: Int,  // 1 = Sunday, 2 = Monday, etc.
        hour: Int,
        minute: Int,
        title: String = "Time to Train",
        body: String = "Your workout is waiting. Let's crush it!"
    ) async {
        guard isAuthorized else {
            print("[Notifications] Not authorized to schedule reminders")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "workout-reminder-\(weekday)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[Notifications] Scheduled workout reminder for weekday \(weekday) at \(hour):\(minute)")
        } catch {
            print("[Notifications] Failed to schedule reminder: \(error.localizedDescription)")
        }
    }
    
    /// Cancel all workout reminders
    func cancelAllWorkoutReminders() {
        let identifiers = (1...7).map { "workout-reminder-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("[Notifications] Cancelled all workout reminders")
    }
    
    /// Schedule a rest day check-in reminder
    func scheduleRestDayReminder(daysFromNow: Int = 1) async {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Recovery Day"
        content.body = "Rest is part of the process. How are you feeling today?"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(daysFromNow * 24 * 60 * 60),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "rest-day-checkin",
            content: content,
            trigger: trigger
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    /// Schedule a streak reminder to maintain consistency
    func scheduleStreakReminder() async {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Keep Your Streak"
        content.body = "Don't break the chain! Log your workout today."
        content.sound = .default
        
        // Schedule for 6 PM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "streak-reminder",
            content: content,
            trigger: trigger
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    /// Send a local notification immediately (for testing)
    func sendTestNotification() async {
        guard isAuthorized else {
            print("[Notifications] Not authorized")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "IronForge"
        content.body = "Notifications are working! 💪"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test-notification",
            content: content,
            trigger: trigger
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
}
