//
//  HealthAlertModels.swift
//  Health Data
//

import Foundation
import SwiftUI

enum HealthAlertSeverity: String, Codable, Comparable {
    case info
    case warning
    case critical

    private var sortOrder: Int {
        switch self {
        case .critical: return 2
        case .warning: return 1
        case .info: return 0
        }
    }

    static func < (lhs: HealthAlertSeverity, rhs: HealthAlertSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var title: String {
        switch self {
        case .info: return "提示"
        case .warning: return "注意"
        case .critical: return "重要"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "bell.badge.fill"
        }
    }
}

struct HealthAlert: Identifiable, Codable, Equatable {
    let id: String
    let severity: HealthAlertSeverity
    let title: String
    let message: String
    let relatedDate: String?
    let metric: String

    init(
        id: String? = nil,
        severity: HealthAlertSeverity,
        title: String,
        message: String,
        relatedDate: String? = nil,
        metric: String
    ) {
        self.id = id ?? "\(metric)-\(relatedDate ?? "general")-\(title)"
        self.severity = severity
        self.title = title
        self.message = message
        self.relatedDate = relatedDate
        self.metric = metric
    }
}

enum RecoveryStatusLevel: String, Codable {
    case good
    case moderate
    case caution
    case alert

    var label: String {
        switch self {
        case .good: return "恢复良好"
        case .moderate: return "恢复一般"
        case .caution: return "需要休息"
        case .alert: return "生化警报"
        }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .moderate: return .yellow
        case .caution: return .orange
        case .alert: return .red
        }
    }

    var iconName: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .moderate: return "minus.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .alert: return "bell.badge.fill"
        }
    }
}

struct HealthInsightResult: Equatable, Codable {
    let recoveryScore: Int
    let recoveryStatus: RecoveryStatusLevel
    let alerts: [HealthAlert]
    let analyzedDayCount: Int
    let latestHrvMs: Double?
    let baselineHrvMs: Double?
    let weeklyFlags: [String]
    let suggestedAnalysisPrompt: String?

    init(
        recoveryScore: Int,
        recoveryStatus: RecoveryStatusLevel,
        alerts: [HealthAlert],
        analyzedDayCount: Int,
        latestHrvMs: Double?,
        baselineHrvMs: Double?,
        weeklyFlags: [String] = [],
        suggestedAnalysisPrompt: String? = nil
    ) {
        self.recoveryScore = recoveryScore
        self.recoveryStatus = recoveryStatus
        self.alerts = alerts
        self.analyzedDayCount = analyzedDayCount
        self.latestHrvMs = latestHrvMs
        self.baselineHrvMs = baselineHrvMs
        self.weeklyFlags = weeklyFlags
        self.suggestedAnalysisPrompt = suggestedAnalysisPrompt
    }
}
