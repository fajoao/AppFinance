import Foundation
#if canImport(UserNotifications)
import UserNotifications

/// Lembretes de vencimento e alertas de orçamento via notificações locais (UserNotifications).
@MainActor
final class UserNotificationsScheduler: ReminderScheduling {
    private let center = UNUserNotificationCenter.current()
    private static let billPrefix = "bill-"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private func isAuthorized() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    func replaceAll(with reminders: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.billPrefix) })
        guard await isAuthorized() else { return }
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            var comps = DateComponents()
            comps.year = r.year; comps.month = r.month; comps.day = r.day; comps.hour = r.hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }

    func notifyNow(id: String, title: String, body: String) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
#endif

@MainActor
func makeReminderScheduler() -> ReminderScheduling {
    #if canImport(UserNotifications)
    return UserNotificationsScheduler()
    #else
    return NoopReminderScheduler()
    #endif
}
