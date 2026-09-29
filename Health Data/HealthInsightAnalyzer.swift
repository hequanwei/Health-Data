//
//  HealthInsightAnalyzer.swift
//  Health Data
//

import Foundation

enum HealthInsightAnalyzer {

    private static let asleepStages: Set<String> = [
        "asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified"
    ]

    // MARK: - Public

    static func analyze(
        dataByDate: [String: DailyHealthData],
        thresholds: HealthAlertThresholds = .default
    ) -> HealthInsightResult {
        let sortedDays = dataByDate.keys.sorted()
        guard !sortedDays.isEmpty else {
            return HealthInsightResult(
                recoveryScore: 0,
                recoveryStatus: .moderate,
                alerts: [
                    HealthAlert(
                        severity: .info,
                        title: "暂无分析数据",
                        message: "请先扫描或导出近 7 日健康数据，并确认已在「健康」中授权读取 HRV、睡眠与训练记录。",
                        metric: "general"
                    )
                ],
                analyzedDayCount: 0,
                latestHrvMs: nil,
                baselineHrvMs: nil
            )
        }

        var dailyHRV: [String: Double] = [:]
        var dailyRHR: [String: Double] = [:]
        var dailySleepMinutes: [String: Double] = [:]
        var dailyWorkoutMinutes: [String: Double] = [:]
        var dailyWorkoutCount: [String: Int] = [:]

        for day in sortedDays {
            guard let daily = dataByDate[day] else { continue }
            if let avg = average(from: daily.hrv) { dailyHRV[day] = avg }
            if let avg = average(from: daily.restingHeartRate) { dailyRHR[day] = avg }
            if let sleep = daily.sleep, !sleep.isEmpty {
                dailySleepMinutes[day] = asleepMinutes(from: sleep)
            }
            let workoutMinutes = daily.workouts?.reduce(0.0) { $0 + $1.durationMinutes } ?? 0
            let workoutCount = daily.workouts?.count ?? 0
            if workoutCount > 0 {
                dailyWorkoutMinutes[day] = workoutMinutes
                dailyWorkoutCount[day] = workoutCount
            }
        }

        let baselineHRV = mean(of: Array(dailyHRV.values))
        let baselineRHR = mean(of: Array(dailyRHR.values))
        let latestDay = sortedDays.last
        let latestHRV = latestDay.flatMap { dailyHRV[$0] }

        var alerts: [HealthAlert] = []
        alerts.append(contentsOf: hrvAlerts(
            dailyHRV: dailyHRV,
            baseline: baselineHRV,
            sortedDays: sortedDays,
            thresholds: thresholds
        ))
        alerts.append(contentsOf: restingHeartRateAlerts(
            dailyRHR: dailyRHR,
            baseline: baselineRHR,
            sortedDays: sortedDays,
            thresholds: thresholds
        ))
        alerts.append(contentsOf: sleepAlerts(
            dailySleepMinutes: dailySleepMinutes,
            sortedDays: sortedDays,
            thresholds: thresholds
        ))
        alerts.append(contentsOf: trainingLoadAlerts(
            dailyHRV: dailyHRV,
            dailyWorkoutMinutes: dailyWorkoutMinutes,
            dailyWorkoutCount: dailyWorkoutCount,
            sortedDays: sortedDays,
            thresholds: thresholds
        ))

        if alerts.isEmpty {
            alerts.append(HealthAlert(
                severity: .info,
                title: "近 7 日未见明显异常",
                message: "HRV、静息心率、睡眠与训练负荷未触发预警规则。建议继续保持，并定期导出做 Weekly 复盘。",
                metric: "general"
            ))
        }

        let score = recoveryScore(
            latestHRV: latestHRV,
            baselineHRV: baselineHRV,
            latestRHR: latestDay.flatMap { dailyRHR[$0] },
            baselineRHR: baselineRHR,
            latestSleep: latestDay.flatMap { dailySleepMinutes[$0] },
            criticalCount: alerts.filter { $0.severity == .critical }.count,
            warningCount: alerts.filter { $0.severity == .warning }.count,
            thresholds: thresholds
        )

        let weeklyFlags = collectWeeklyFlags(from: alerts)

        return HealthInsightResult(
            recoveryScore: score,
            recoveryStatus: status(for: score, alerts: alerts),
            alerts: alerts.sorted { $0.severity > $1.severity },
            analyzedDayCount: sortedDays.count,
            latestHrvMs: latestHRV,
            baselineHrvMs: baselineHRV,
            weeklyFlags: weeklyFlags
        )
    }

    // MARK: - Rules

    private static func hrvAlerts(
        dailyHRV: [String: Double],
        baseline: Double?,
        sortedDays: [String],
        thresholds: HealthAlertThresholds
    ) -> [HealthAlert] {
        guard let baseline, baseline > 0, dailyHRV.count >= 2 else { return [] }

        var alerts: [HealthAlert] = []
        var consecutiveLowDays = 0

        for day in sortedDays {
            guard let value = dailyHRV[day] else { continue }
            let ratio = value / baseline

            if ratio < thresholds.hrvCriticalRatio {
                alerts.append(HealthAlert(
                    severity: .critical,
                    title: "HRV 断崖式下跌",
                    message: String(format: "%@ HRV 仅 %.1f ms，约为近 7 日均值（%.1f ms）的 %.0f%%。自主神经可能处于高压状态，常见于免疫应激、睡眠不足或过度训练。", day, value, baseline, ratio * 100),
                    relatedDate: day,
                    metric: "hrv"
                ))
                consecutiveLowDays += 1
            } else if ratio < thresholds.hrvWarningRatio {
                consecutiveLowDays += 1
                alerts.append(HealthAlert(
                    severity: .warning,
                    title: "HRV 明显低于基线",
                    message: String(format: "%@ HRV %.1f ms，低于近 7 日均值 %.1f ms 约 %.0f%%。建议减少高强度训练，优先睡眠与恢复。", day, value, baseline, (1 - ratio) * 100),
                    relatedDate: day,
                    metric: "hrv"
                ))
            } else {
                consecutiveLowDays = 0
            }
        }

        if consecutiveLowDays >= 2 {
            alerts.append(HealthAlert(
                severity: .critical,
                title: "HRV 持续低迷",
                message: "连续多日 HRV 低于个人基线，系统可能在症状出现前已发出恢复不足信号。建议暂停高强度运动，增加睡眠。",
                metric: "hrv"
            ))
        }

        return alerts
    }

    private static func restingHeartRateAlerts(
        dailyRHR: [String: Double],
        baseline: Double?,
        sortedDays: [String],
        thresholds: HealthAlertThresholds
    ) -> [HealthAlert] {
        guard let baseline, dailyRHR.count >= 2 else { return [] }

        var alerts: [HealthAlert] = []
        var consecutiveHighDays = 0

        for day in sortedDays {
            guard let value = dailyRHR[day] else { continue }
            let delta = value - baseline

            if delta >= thresholds.restingHRCriticalDelta {
                consecutiveHighDays += 1
                alerts.append(HealthAlert(
                    severity: .warning,
                    title: "静息心率偏高",
                    message: String(format: "%@ 静息心率 %.0f bpm，较近 7 日均值 %.0f bpm 偏高 %.0f bpm。可能提示恢复不足或身体应激。", day, value, baseline, delta),
                    relatedDate: day,
                    metric: "restingHeartRate"
                ))
            } else if delta >= thresholds.restingHRWarningDelta {
                consecutiveHighDays += 1
            } else {
                consecutiveHighDays = 0
            }
        }

        if consecutiveHighDays >= 2 {
            alerts.append(HealthAlert(
                severity: .warning,
                title: "静息心率连续偏高",
                message: "连续多日静息心率高于个人基线，建议关注睡眠、补水，并避免带病高强度训练。",
                metric: "restingHeartRate"
            ))
        }

        return alerts
    }

    private static func sleepAlerts(
        dailySleepMinutes: [String: Double],
        sortedDays: [String],
        thresholds: HealthAlertThresholds
    ) -> [HealthAlert] {
        var alerts: [HealthAlert] = []
        let criticalMinutes = thresholds.minSleepCriticalHours * 60
        let warningMinutes = thresholds.minSleepWarningHours * 60

        for day in sortedDays {
            guard let minutes = dailySleepMinutes[day] else { continue }
            let hours = minutes / 60.0

            if minutes < criticalMinutes {
                alerts.append(HealthAlert(
                    severity: .critical,
                    title: "睡眠严重不足",
                    message: String(format: "%@ 实际睡眠约 %.1f 小时，明显不足。恢复能力将显著下降。", day, hours),
                    relatedDate: day,
                    metric: "sleep"
                ))
            } else if minutes < warningMinutes {
                alerts.append(HealthAlert(
                    severity: .warning,
                    title: "睡眠不足",
                    message: String(format: "%@ 实际睡眠约 %.1f 小时，低于建议的 %.0f 小时。建议优先补觉。", day, hours, thresholds.minSleepWarningHours),
                    relatedDate: day,
                    metric: "sleep"
                ))
            }
        }

        return alerts
    }

    private static func trainingLoadAlerts(
        dailyHRV: [String: Double],
        dailyWorkoutMinutes: [String: Double],
        dailyWorkoutCount: [String: Int],
        sortedDays: [String],
        thresholds: HealthAlertThresholds
    ) -> [HealthAlert] {
        guard !dailyHRV.isEmpty else { return [] }

        let sortedHRV = dailyHRV.values.sorted()
        guard let threshold = percentile(sortedHRV, p: 0.25) else { return [] }

        var alerts: [HealthAlert] = []

        for day in sortedDays {
            guard let hrv = dailyHRV[day], hrv <= threshold,
                  let minutes = dailyWorkoutMinutes[day], minutes >= thresholds.minWorkoutMinutesForLoadAlert,
                  let count = dailyWorkoutCount[day], count > 0 else { continue }

            alerts.append(HealthAlert(
                severity: .critical,
                title: "低 HRV 日进行高强度训练",
                message: String(format: "%@ HRV 处于近 7 日低位（%.1f ms），当日仍有 %.0f 分钟训练。免疫或恢复承压时不宜强行上强度。", day, hrv, minutes),
                relatedDate: day,
                metric: "workouts"
            ))
        }

        return alerts
    }

    // MARK: - Scoring

    private static func recoveryScore(
        latestHRV: Double?,
        baselineHRV: Double?,
        latestRHR: Double?,
        baselineRHR: Double?,
        latestSleep: Double?,
        criticalCount: Int,
        warningCount: Int,
        thresholds: HealthAlertThresholds
    ) -> Int {
        var score = 75

        if let latestHRV, let baselineHRV, baselineHRV > 0 {
            let ratio = latestHRV / baselineHRV
            if ratio >= 0.95 { score += 15 }
            else if ratio >= 0.85 { score += 5 }
            else if ratio < thresholds.hrvCriticalRatio { score -= 35 }
            else if ratio < thresholds.hrvWarningRatio { score -= 20 }
        }

        if let latestRHR, let baselineRHR {
            let delta = latestRHR - baselineRHR
            if delta <= 2 { score += 5 }
            else if delta >= thresholds.restingHRCriticalDelta { score -= 15 }
            else if delta >= thresholds.restingHRWarningDelta { score -= 8 }
        }

        if let latestSleep {
            if latestSleep >= 420 { score += 10 }
            else if latestSleep < thresholds.minSleepCriticalHours * 60 { score -= 20 }
            else if latestSleep < thresholds.minSleepWarningHours * 60 { score -= 10 }
        }

        score -= criticalCount * 12
        score -= warningCount * 5

        return min(100, max(0, score))
    }

    private static func status(for score: Int, alerts: [HealthAlert]) -> RecoveryStatusLevel {
        if alerts.contains(where: { $0.severity == .critical }) || score < 45 { return .alert }
        if score < 60 || alerts.contains(where: { $0.severity == .warning }) { return .caution }
        if score < 75 { return .moderate }
        return .good
    }

    private static func collectWeeklyFlags(from alerts: [HealthAlert]) -> [String] {
        var flags = Set<String>()

        for alert in alerts {
            switch alert.metric {
            case "hrv":
                if alert.title.contains("断崖") { flags.insert("hrv_cliff") }
                else if alert.title.contains("持续") { flags.insert("hrv_sustained_low") }
                else if alert.title.contains("低于基线") { flags.insert("hrv_low") }
            case "restingHeartRate":
                if alert.title.contains("连续") { flags.insert("rhr_sustained_high") }
                else { flags.insert("rhr_elevated") }
            case "sleep":
                flags.insert(alert.title.contains("严重不足") ? "sleep_critical" : "sleep_low")
            case "workouts":
                flags.insert("training_while_suppressed")
            default:
                break
            }
        }

        return flags.sorted()
    }

    // MARK: - Helpers

    private static func average(from records: [QuantityRecord]?) -> Double? {
        guard let records, !records.isEmpty else { return nil }
        let sum = records.reduce(0.0) { $0 + $1.value }
        return sum / Double(records.count)
    }

    private static func mean(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ sortedValues: [Double], p: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let index = Int(Double(sortedValues.count - 1) * p)
        return sortedValues[max(0, min(sortedValues.count - 1, index))]
    }

    private static func asleepMinutes(from records: [SleepRecord]) -> Double {
        var total: TimeInterval = 0
        for record in records where asleepStages.contains(record.stage) {
            guard let start = parseDate(record.start), let end = parseDate(record.end), end > start else { continue }
            total += end.timeIntervalSince(start)
        }
        return total / 60.0
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}
