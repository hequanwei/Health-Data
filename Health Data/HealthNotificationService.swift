//
//  HealthNotificationService.swift
//  Health Data
//

import Foundation
import UserNotifications

enum HealthNotificationService {
    private static let lastNotificationDayKey = "health_last_notification_day"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func notifyIfNeeded(for insight: HealthInsightResult, enabled: Bool) async {
        guard enabled else { return }

        let actionable = insight.alerts.filter { $0.severity == .critical || $0.severity == .warning }
        guard !actionable.isEmpty else { return }

        let today = dayKey(for: Date())
        if UserDefaults.standard.string(forKey: lastNotificationDayKey) == today {
            return
        }

        let authorized = await requestAuthorization()
        guard authorized else { return }

        let top = actionable.sorted { $0.severity > $1.severity }.first!
        let content = UNMutableNotificationContent()
        content.title = "健康提醒：\(insight.recoveryStatus.label)"
        content.body = top.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "health-alert-\(today)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(today, forKey: lastNotificationDayKey)
        } catch {
            return
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter.string(from: date)
    }
}
