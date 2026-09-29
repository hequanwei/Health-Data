//
//  HealthAlertSettings.swift
//  Health Data
//

import Combine
import BackgroundTasks
import Foundation

struct HealthAlertThresholds: Codable, Equatable {
    var hrvWarningRatio: Double = 0.75
    var hrvCriticalRatio: Double = 0.60
    var restingHRWarningDelta: Double = 5
    var restingHRCriticalDelta: Double = 8
    var minSleepWarningHours: Double = 6
    var minSleepCriticalHours: Double = 5
    var minWorkoutMinutesForLoadAlert: Double = 20

    static let `default` = HealthAlertThresholds()
}

@MainActor
final class HealthAlertSettings: ObservableObject {
    static let shared = HealthAlertSettings()

    @Published var thresholds: HealthAlertThresholds {
        didSet { save() }
    }

    static let backgroundScanKey = "health_background_scan_enabled"

    @Published var notificationsEnabled: Bool {
        didSet { save() }
    }

    @Published var backgroundScanEnabled: Bool {
        didSet {
            save()
            if backgroundScanEnabled {
                BackgroundScanScheduler.scheduleNextScan()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundScanScheduler.taskIdentifier)
            }
        }
    }

    private let thresholdsKey = "health_alert_thresholds"
    private let notificationsKey = "health_notifications_enabled"

    private init() {
        if let data = UserDefaults.standard.data(forKey: thresholdsKey),
           let decoded = try? JSONDecoder().decode(HealthAlertThresholds.self, from: data) {
            thresholds = decoded
        } else {
            thresholds = .default
        }
        notificationsEnabled = UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? false
        backgroundScanEnabled = UserDefaults.standard.object(forKey: Self.backgroundScanKey) as? Bool ?? true
    }

    func resetToDefaults() {
        thresholds = .default
        notificationsEnabled = false
        backgroundScanEnabled = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(thresholds) {
            UserDefaults.standard.set(data, forKey: thresholdsKey)
        }
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsKey)
        UserDefaults.standard.set(backgroundScanEnabled, forKey: Self.backgroundScanKey)
    }

    static var isBackgroundScanEnabled: Bool {
        UserDefaults.standard.object(forKey: backgroundScanKey) as? Bool ?? true
    }
}
