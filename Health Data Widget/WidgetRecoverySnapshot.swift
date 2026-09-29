//
//  WidgetRecoverySnapshot.swift
//  Health Data Widget
//

import Foundation

enum AppGroupConstants {
    static let suiteName = "group.com.personal.Health-Data"
    static let widgetSnapshotKey = "widget_recovery_snapshot"
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
    static func load() -> WidgetRecoverySnapshot? {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
              let data = defaults.data(forKey: AppGroupConstants.widgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetRecoverySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
