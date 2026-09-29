//
//  DailySummaryBuilder.swift
//  Health Data
//

import Foundation

enum DailySummaryBuilder {

    private static let asleepStages: Set<String> = [
        "asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified"
    ]

    static func buildDailySummaries(
        from dataByDate: [String: DailyHealthData],
        baselineHRV: Double?,
        baselineRHR: Double?,
        thresholds: HealthAlertThresholds
    ) -> [String: DailySummary] {
        var result: [String: DailySummary] = [:]

        for (day, daily) in dataByDate.sorted(by: { $0.key < $1.key }) {
            let hrvAvg = average(from: daily.hrv)
            let rhrAvg = average(from: daily.restingHeartRate)
            let sleepMinutes = daily.sleep.map { asleepMinutes(from: $0) }
            let workoutCount = daily.workouts?.count ?? 0
            let workoutMinutes = daily.workouts?.reduce(0.0) { $0 + $1.durationMinutes } ?? 0

            var flags: [String] = []
            if let hrvAvg, let baselineHRV, baselineHRV > 0 {
                let ratio = hrvAvg / baselineHRV
                if ratio < thresholds.hrvCriticalRatio { flags.append("hrv_cliff") }
                else if ratio < thresholds.hrvWarningRatio { flags.append("hrv_low") }
            }
            if let rhrAvg, let baselineRHR {
                let delta = rhrAvg - baselineRHR
                if delta >= thresholds.restingHRCriticalDelta { flags.append("rhr_elevated") }
                else if delta >= thresholds.restingHRWarningDelta { flags.append("rhr_high") }
            }
            if let sleepMinutes {
                if sleepMinutes < thresholds.minSleepCriticalHours * 60 { flags.append("sleep_critical") }
                else if sleepMinutes < thresholds.minSleepWarningHours * 60 { flags.append("sleep_low") }
            }
            if workoutCount > 0, let hrvAvg, let baselineHRV, hrvAvg < baselineHRV * thresholds.hrvWarningRatio {
                flags.append("training_while_suppressed")
            }

            result[day] = DailySummary(
                hrvAvgMs: hrvAvg,
                restingHeartRateAvg: rhrAvg,
                sleepMinutes: sleepMinutes,
                workoutCount: workoutCount,
                workoutMinutes: workoutMinutes,
                stepCount: daily.stepCount?.total,
                activeEnergyKcal: daily.activeEnergyBurned?.total,
                flags: flags
            )
        }

        return result
    }

    static func buildWeeklyInsight(
        from insight: HealthInsightResult,
        dailySummaries: [String: DailySummary],
        periodStart: String,
        periodEnd: String
    ) -> WeeklyInsightExport {
        let weeklyFlags = Array(Set(dailySummaries.values.flatMap(\.flags) + insight.weeklyFlags)).sorted()
        let prompt = AnalysisPromptBuilder.build(
            insight: insight,
            dailySummaries: dailySummaries,
            periodStart: periodStart,
            periodEnd: periodEnd,
            weeklyFlags: weeklyFlags
        )

        return WeeklyInsightExport(
            recoveryScore: insight.recoveryScore,
            recoveryStatus: insight.recoveryStatus.rawValue,
            baselineHrvMs: insight.baselineHrvMs,
            latestHrvMs: insight.latestHrvMs,
            weeklyFlags: weeklyFlags,
            alertCount: insight.alerts.count,
            criticalAlertCount: insight.alerts.filter { $0.severity == .critical }.count,
            alerts: insight.alerts,
            suggestedAnalysisPrompt: prompt
        )
    }

    private static func average(from records: [QuantityRecord]?) -> Double? {
        guard let records, !records.isEmpty else { return nil }
        return records.reduce(0.0) { $0 + $1.value } / Double(records.count)
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

enum AnalysisPromptBuilder {
    static func build(
        insight: HealthInsightResult,
        dailySummaries: [String: DailySummary],
        periodStart: String,
        periodEnd: String,
        weeklyFlags: [String]
    ) -> String {
        """
        你是运动恢复与睡眠健康顾问。请根据以下过去 7 日的 Apple Watch 健康 JSON 数据，输出一份 Weekly 量化自我分析报告。

        分析区间：\(periodStart) 至 \(periodEnd)
        恢复分：\(insight.recoveryScore)/100（\(insight.recoveryStatus.label)）
        周级标记：\(weeklyFlags.isEmpty ? "无明显异常" : weeklyFlags.joined(separator: ", "))
        HRV 基线：\(formatOptional(insight.baselineHrvMs, suffix: " ms"))
        最新 HRV：\(formatOptional(insight.latestHrvMs, suffix: " ms"))

        请从以下维度分析，并给出可执行的 72 小时调整建议：
        1. 恢复与自主神经（HRV、静息心率）
        2. 睡眠与作息
        3. 训练负荷与是否「带病/带压训练」
        4. 风险信号与优先事项

        附：日级摘要（供快速阅读）
        \(summariesText(dailySummaries))

        免责声明：非医疗诊断，仅供参考。完整原始数据见 JSON 附件。
        """
    }

    private static func formatOptional(_ value: Double?, suffix: String) -> String {
        guard let value else { return "无数据" }
        return String(format: "%.1f%@", value, suffix)
    }

    private static func summariesText(_ summaries: [String: DailySummary]) -> String {
        summaries.keys.sorted().compactMap { day in
            guard let s = summaries[day] else { return nil }
            let hrv = s.hrvAvgMs.map { String(format: "%.0fms", $0) } ?? "-"
            let sleep = s.sleepMinutes.map { String(format: "%.1fh", $0 / 60) } ?? "-"
            let train = s.workoutCount > 0 ? "\(s.workoutCount)次/\(Int(s.workoutMinutes))分" : "无"
            let flags = s.flags.isEmpty ? "" : " [\(s.flags.joined(separator: ","))]"
            return "- \(day): HRV \(hrv), 睡眠 \(sleep), 训练 \(train)\(flags)"
        }.joined(separator: "\n")
    }
}
