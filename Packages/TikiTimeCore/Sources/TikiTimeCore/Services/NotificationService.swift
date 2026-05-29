import UserNotifications
import Foundation

public final class NotificationService: Sendable {
    public static let shared = NotificationService()
    private init() {}

    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    public func scheduleHourlyNotifications(greetings: [String] = [], sound: String = "default") {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for hour in 0..<24 {
            let content = UNMutableNotificationContent()
            content.title = "TikiTime ⏰"
            content.body = hour < greetings.count ? greetings[hour] : hourlyMessage(for: hour)
            switch sound {
            case "none": content.sound = nil
            case "default": content.sound = .default
            default: content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
            }

            var dateComponents = DateComponents()
            dateComponents.minute = 0
            dateComponents.second = 0
            dateComponents.hour = hour

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "hourly-\(hour)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    public func cancelHourlyNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func hourlyMessage(for hour: Int) -> String {
        let period = hour < 12 ? "오전" : "오후"
        let display = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(period) \(display)시가 되었어요! 티키가 인사해요 🎉"
    }
}
