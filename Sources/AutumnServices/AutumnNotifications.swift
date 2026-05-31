import Foundation
import UserNotifications

/// AutumnNotifications — Push notification manager
/// Handles permission request, scheduling local notifications,
/// and receiving remote push notifications from GAS/leatr-ash
public final class AutumnNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    public static let shared = AutumnNotifications()

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch { return false }
    }

    // MARK: - Local Notifications
    /// Schedule a local notification — used for Ash Star events and journal reminders
    public func scheduleLocal(title: String, body: String, delay: TimeInterval = 5) {
        let content        = UNMutableNotificationContent()
        content.title      = title
        content.body       = body
        content.sound      = .default
        let trigger        = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request        = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Notify user when Autumn fires an Ash Star
    public func notifyAshStar(thought: String) {
        scheduleLocal(title: "Ash Star", body: thought.isEmpty ? "Autumn sent a signal." : thought, delay: 1)
    }

    // MARK: - Delegate
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
