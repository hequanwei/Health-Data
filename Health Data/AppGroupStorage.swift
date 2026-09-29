//
//  AppGroupStorage.swift
//  Health Data
//

import Foundation

enum AppGroupConstants {
    static let suiteName = "group.com.personal.Health-Data"
    static let widgetSnapshotKey = "widget_recovery_snapshot"
    static let lastBackgroundScanKey = "last_background_scan_at"
}

struct WidgetRecoverySnapshot: Codable {
    let recoveryScore: Int
    let recoveryStatus: String
    let recoveryStatusLabel: String
    let latestHrvMs: Double?
    let baselineHrvMs: Double?
    let analyzedDayCount: Int
    let weeklyFlags: [String]
    let alertCount: Int
    let updatedAt: Date

    static let placeholder = WidgetRecoverySnapshot(
        recoveryScore: 0,
        recoveryStatus: "moderate",
        recoveryStatusLabel: "暂无数据",
        latestHrvMs: nil,
        baselineHrvMs: nil,
        analyzedDayCount: 0,
        weeklyFlags: [],
        alertCount: 0,
        updatedAt: .distantPast
    )
}

enum WidgetSnapshotStore {
    static func save(from insight: HealthInsightResult) {
        let snapshot = WidgetRecoverySnapshot(
            recoveryScore: insight.recoveryScore,
            recoveryStatus: insight.recoveryStatus.rawValue,
            recoveryStatusLabel: insight.recoveryStatus.label,
            latestHrvMs: insight.latestHrvMs,
            baselineHrvMs: insight.baselineHrvMs,
            analyzedDayCount: insight.analyzedDayCount,
            weeklyFlags: insight.weeklyFlags,
            alertCount: insight.alerts.filter { $0.severity != .info || insight.alerts.count == 1 }.count,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName) else { return }
        defaults.set(data, forKey: AppGroupConstants.widgetSnapshotKey)
    }

    static func load() -> WidgetRecoverySnapshot? {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
              let data = defaults.data(forKey: AppGroupConstants.widgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetRecoverySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}

enum BackgroundScanStore {
    static func markCompleted(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: AppGroupConstants.lastBackgroundScanKey)
        if let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName) {
            defaults.set(date.timeIntervalSince1970, forKey: AppGroupConstants.lastBackgroundScanKey)
        }
    }

    static func lastCompletedAt() -> Date? {
        let key = AppGroupConstants.lastBackgroundScanKey
        let interval = UserDefaults.standard.double(forKey: key)
        if interval > 0 { return Date(timeIntervalSince1970: interval) }
        if let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName) {
            let groupInterval = defaults.double(forKey: key)
            if groupInterval > 0 { return Date(timeIntervalSince1970: groupInterval) }
        }
        return nil
    }
}
