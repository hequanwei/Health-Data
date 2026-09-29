//
//  HealthManager.swift
//  Health Data
//

import Combine
import Foundation
import HealthKit

enum HealthFetchKind: String, CaseIterable, Sendable {
    case heartRate
    case restingHeartRate
    case hrv
    case respiratoryRate
    case sleep
    case workouts
    case stepCount
    case vo2Max
    case heartRateRecoveryOneMinute
    case walkingHeartRateAverage
    case walkingAsymmetryPercentage
    case walkingDoubleSupportPercentage
    case appleSleepingWristTemperature
    case oxygenSaturation
    case timeInDaylight
    case activeEnergyBurned
    case basalEnergyBurned
    case appleStandTime
    case stepLength
    case stairAscentSpeed
    case stairDescentSpeed
    case environmentalAudioExposure
    case dietaryCaffeine

    var displayName: String {
        switch self {
        case .heartRate: return "心率"
        case .restingHeartRate: return "静息心率"
        case .hrv: return "HRV"
        case .respiratoryRate: return "呼吸率"
        case .sleep: return "睡眠"
        case .workouts: return "体能训练"
        case .stepCount: return "步数"
        case .vo2Max: return "VO2 Max"
        case .heartRateRecoveryOneMinute: return "心率恢复"
        case .walkingHeartRateAverage: return "步行心率"
        case .walkingAsymmetryPercentage: return "步行不对称"
        case .walkingDoubleSupportPercentage: return "双支撑占比"
        case .appleSleepingWristTemperature: return "睡眠手腕温度"
        case .oxygenSaturation: return "血氧"
        case .timeInDaylight: return "日光时间"
        case .activeEnergyBurned: return "活动能量"
        case .basalEnergyBurned: return "基础能量"
        case .appleStandTime: return "站立时间"
        case .stepLength: return "步长"
        case .stairAscentSpeed: return "上楼梯速度"
        case .stairDescentSpeed: return "下楼梯速度"
        case .environmentalAudioExposure: return "环境音量"
        case .dietaryCaffeine: return "咖啡因"
        }
    }
}

@MainActor
class HealthManager: ObservableObject {
    let healthStore = HKHealthStore()

    @Published var statusMessage: String = "等待同步..."
    @Published var isExporting = false
    @Published var lastExportedFileURL: URL?
    @Published var exportedFiles: [URL] = []
    @Published var exportFileItems: [ExportFileItem] = []
    @Published var healthInsight: HealthInsightResult?
    @Published var isCheckingAlerts = false

    private let alertSettings = HealthAlertSettings.shared

    private static let alertFetchKinds: [HealthFetchKind] = [.hrv, .restingHeartRate, .sleep, .workouts]

    init() {
        healthInsight = HealthInsightPersistence.load()
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter
    }()

    private let exportFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter
    }()

    var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .stepCount,
            .vo2Max,
            .heartRateRecoveryOneMinute,
            .walkingHeartRateAverage,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .appleSleepingWristTemperature,
            .oxygenSaturation,
            .timeInDaylight,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .appleStandTime,
            .walkingStepLength,
            .stairAscentSpeed,
            .stairDescentSpeed,
            .environmentalAudioExposure,
            .dietaryCaffeine
        ]

        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())

        return types
    }

    // MARK: - Authorization

    /// 弹出 HealthKit 授权面板。注意：`success` 仅表示对话框已处理完毕，不代表用户已允许读取。
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 HealthKit"
            return
        }

        statusMessage = "正在请求权限…"

        await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                Task { @MainActor in
                    if let error {
                        self.statusMessage = "授权异常: \(error.localizedDescription)"
                    } else if success {
                        self.statusMessage = "授权面板已确认，开始导出…"
                    } else {
                        self.statusMessage = "授权未完成，仍将尝试导出…"
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Export

    func exportHealthData() async {
        guard !isExporting else { return }

        isExporting = true
        defer { isExporting = false }

        statusMessage = "准备导出（过去 7 天）…"

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: end) else {
            statusMessage = "无法计算时间范围"
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        var mergedByDate: [String: DailyHealthData] = [:]
        var errors: [String: String] = [:]
        var completedKinds: [String] = []
        let totalKinds = HealthFetchKind.allCases.count

        statusMessage = "正在并发读取 \(totalKinds) 类健康数据 (0/\(totalKinds))…"

        await withTaskGroup(of: (HealthFetchKind, Result<[String: DailyHealthData], Error>).self) { group in
            for kind in HealthFetchKind.allCases {
                group.addTask { @MainActor in
                    await self.fetchResult(kind, predicate: predicate, start: start, end: end)
                }
            }

            for await (kind, result) in group {
                switch result {
                case .success(let partial):
                    mergeDaily(partial, into: &mergedByDate)
                    completedKinds.append(kind.displayName)
                case .failure(let error):
                    errors[kind.rawValue] = error.localizedDescription
                }

                let progress = completedKinds.count + errors.count
                let names = completedKinds.joined(separator: "、")
                if names.isEmpty {
                    statusMessage = "正在读取健康数据… (\(progress)/\(totalKinds))"
                } else {
                    statusMessage = "正在读取：\(names)… (\(progress)/\(totalKinds))"
                }
            }
        }

        statusMessage = "正在按日期整理数据…"

        let periodStartDay = dayKey(for: start)
        let periodEndDay = dayKey(for: end)
        updateHealthInsight(from: mergedByDate, periodStart: periodStartDay, periodEnd: periodEndDay)

        let thresholds = alertSettings.thresholds
        let dailySummaries = DailySummaryBuilder.buildDailySummaries(
            from: mergedByDate,
            baselineHRV: healthInsight?.baselineHrvMs,
            baselineRHR: meanRestingHeartRate(from: mergedByDate),
            thresholds: thresholds
        )
        let weeklyInsight = healthInsight.map {
            DailySummaryBuilder.buildWeeklyInsight(
                from: $0,
                dailySummaries: dailySummaries,
                periodStart: periodStartDay,
                periodEnd: periodEndDay
            )
        }

        let summary = buildExportSummary(from: mergedByDate)
        let payload = HealthExportPayload(
            schemaVersion: 4,
            exportedAt: isoFormatter.string(from: Date()),
            periodStart: isoFormatter.string(from: start),
            periodEnd: isoFormatter.string(from: end),
            notes: "按样本开始日归并；跨午夜睡眠计入开始日。dailySummaries 为日级摘要，weeklyInsight 含恢复分、周级标记与 AI 分析 Prompt。若 dataByDate 为空，请到 设置→健康→数据访问 中为本 App 开启读取权限。",
            errors: errors.isEmpty ? nil : errors,
            exportSummary: summary,
            dataByDate: mergedByDate,
            dailySummaries: dailySummaries,
            weeklyInsight: weeklyInsight
        )

        statusMessage = "正在生成 JSON…"

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(payload)
            let dateString = exportFilenameFormatter.string(from: Date())
            let filename = "HealthExport_\(dateString).json"
            let fileURL = try saveJSONToDocuments(data: jsonData, filename: filename)
            lastExportedFileURL = fileURL
            refreshExportedFilesList()

            let byteCount = jsonData.count
            var message = "导出成功：\(filename)\n大小 \(byteCount) 字节"
            message += "\n\n在「文件」→「我的 iPhone」→「Health Data」中查看"
            message += "\n（若未看到请下拉刷新文件夹）"
            message += "\n\n样本统计：心率 \(summary.heartRateSamples)、HRV \(summary.hrvSamples)、睡眠 \(summary.sleepSamples)、训练 \(summary.workoutSamples)、步数 \(summary.stepDays) 天"
            message += "\nVO2 \(summary.vo2MaxSamples)、血氧 \(summary.oxygenSaturationSamples)、活动能量 \(summary.activeEnergyDays) 天"

            if summary.dayCount == 0 {
                message += "\n\n⚠️ JSON 已生成但无健康数据，请到 设置→健康→数据访问 检查权限"
            }
            if !errors.isEmpty {
                message += "\n部分类型失败：\(errors.keys.joined(separator: "、"))"
            }
            if let insight = healthInsight, !insight.alerts.isEmpty {
                let alertCount = insight.alerts.filter { $0.severity != .info || insight.alerts.count == 1 }.count
                if insight.recoveryStatus == .alert || insight.recoveryStatus == .caution {
                    message += "\n\n⚠️ 健康提醒：\(insight.recoveryStatus.label)（恢复分 \(insight.recoveryScore)）"
                } else if alertCount > 0 {
                    message += "\n\n健康扫描：\(alertCount) 条提醒，详见上方卡片"
                }
            }
            statusMessage = message
        } catch {
            statusMessage = "导出失败: \(error.localizedDescription)"
        }
    }

    func refreshExportedFilesList() {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            exportedFiles = []
            exportFileItems = []
            return
        }

        exportedFiles = listExportFiles(in: documentDirectory).sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        exportFileItems = exportedFiles.compactMap { ExportFileItem.from(url: $0) }
    }

    func deleteExport(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        if lastExportedFileURL == url {
            lastExportedFileURL = exportedFiles.first(where: { $0 != url })
        }
        refreshExportedFilesList()
    }

    func deleteAllExports() throws {
        for url in exportedFiles {
            try FileManager.default.removeItem(at: url)
        }
        lastExportedFileURL = nil
        refreshExportedFilesList()
    }

    // MARK: - Health Alerts

    /// 轻量扫描：仅读取 HRV、静息心率、睡眠、训练，用于 App 内提醒（无需完整导出）。
    func checkHealthAlerts() async {
        guard !isCheckingAlerts, !isExporting else { return }

        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 HealthKit"
            return
        }

        isCheckingAlerts = true
        defer { isCheckingAlerts = false }

        statusMessage = "正在扫描近 7 日健康信号…"

        guard let mergedByDate = await fetchAlertWindowData() else {
            statusMessage = "无法计算时间范围"
            return
        }

        updateHealthInsight(from: mergedByDate)
        await finalizeScan(notifyUser: true)
    }

    /// 后台任务调用：静默扫描并刷新 Widget。
    func performBackgroundScan() async -> Bool {
        guard !isCheckingAlerts, !isExporting else { return false }
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        isCheckingAlerts = true
        defer { isCheckingAlerts = false }

        guard let mergedByDate = await fetchAlertWindowData() else { return false }

        updateHealthInsight(from: mergedByDate)
        await finalizeScan(notifyUser: true)
        BackgroundScanStore.markCompleted()
        return (healthInsight?.analyzedDayCount ?? 0) > 0
    }

    private func fetchAlertWindowData() async -> [String: DailyHealthData]? {
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: end) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        var mergedByDate: [String: DailyHealthData] = [:]

        await withTaskGroup(of: (HealthFetchKind, Result<[String: DailyHealthData], Error>).self) { group in
            for kind in Self.alertFetchKinds {
                group.addTask { @MainActor in
                    await self.fetchResult(kind, predicate: predicate, start: start, end: end)
                }
            }

            for await (_, result) in group {
                if case .success(let partial) = result {
                    mergeDaily(partial, into: &mergedByDate)
                }
            }
        }

        return mergedByDate
    }

    private func finalizeScan(notifyUser: Bool) async {
        guard let insight = healthInsight else { return }

        if notifyUser {
            if insight.analyzedDayCount == 0 {
                statusMessage = "未读取到足够数据。请确认健康 App 授权后重试，或直接执行完整导出。"
            } else {
                statusMessage = "扫描完成：\(insight.recoveryStatus.label) · 恢复分 \(insight.recoveryScore) · \(insight.alerts.count) 条提醒"
            }
        }

        await HealthNotificationService.notifyIfNeeded(
            for: insight,
            enabled: alertSettings.notificationsEnabled
        )
    }

    func updateHealthInsight(
        from dataByDate: [String: DailyHealthData],
        periodStart: String? = nil,
        periodEnd: String? = nil
    ) {
        let thresholds = alertSettings.thresholds
        var insight = HealthInsightAnalyzer.analyze(dataByDate: dataByDate, thresholds: thresholds)

        let sortedDays = dataByDate.keys.sorted()
        let startDay = periodStart ?? sortedDays.first ?? dayKey(for: Date())
        let endDay = periodEnd ?? sortedDays.last ?? dayKey(for: Date())

        let dailySummaries = DailySummaryBuilder.buildDailySummaries(
            from: dataByDate,
            baselineHRV: insight.baselineHrvMs,
            baselineRHR: meanRestingHeartRate(from: dataByDate),
            thresholds: thresholds
        )
        let weeklyInsight = DailySummaryBuilder.buildWeeklyInsight(
            from: insight,
            dailySummaries: dailySummaries,
            periodStart: startDay,
            periodEnd: endDay
        )

        insight = HealthInsightResult(
            recoveryScore: insight.recoveryScore,
            recoveryStatus: insight.recoveryStatus,
            alerts: insight.alerts,
            analyzedDayCount: insight.analyzedDayCount,
            latestHrvMs: insight.latestHrvMs,
            baselineHrvMs: insight.baselineHrvMs,
            weeklyFlags: weeklyInsight.weeklyFlags,
            suggestedAnalysisPrompt: weeklyInsight.suggestedAnalysisPrompt
        )

        healthInsight = insight
        HealthInsightPersistence.save(insight)
    }

    private func meanRestingHeartRate(from dataByDate: [String: DailyHealthData]) -> Double? {
        let values = dataByDate.values.compactMap { daily -> Double? in
            guard let records = daily.restingHeartRate, !records.isEmpty else { return nil }
            return records.reduce(0.0) { $0 + $1.value } / Double(records.count)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Fetch

    private func fetchResult(
        _ kind: HealthFetchKind,
        predicate: NSPredicate,
        start: Date,
        end: Date
    ) async -> (HealthFetchKind, Result<[String: DailyHealthData], Error>) {
        do {
            let data: [String: DailyHealthData]
            switch kind {
            case .heartRate:
                data = try await fetchQuantitySamples(
                    identifier: .heartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    unitLabel: "count/min",
                    predicate: predicate,
                    keyPath: \.heartRate
                )
            case .restingHeartRate:
                data = try await fetchQuantitySamples(
                    identifier: .restingHeartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    unitLabel: "count/min",
                    predicate: predicate,
                    keyPath: \.restingHeartRate
                )
            case .hrv:
                data = try await fetchQuantitySamples(
                    identifier: .heartRateVariabilitySDNN,
                    unit: HKUnit.secondUnit(with: .milli),
                    unitLabel: "ms",
                    predicate: predicate,
                    keyPath: \.hrv
                )
            case .respiratoryRate:
                data = try await fetchQuantitySamples(
                    identifier: .respiratoryRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    unitLabel: "count/min",
                    predicate: predicate,
                    keyPath: \.respiratoryRate
                )
            case .sleep:
                data = try await fetchSleepSamples(predicate: predicate)
            case .workouts:
                data = try await fetchWorkoutSamples(predicate: predicate)
            case .stepCount:
                data = try await fetchDailyStepStatistics(start: start, end: end, predicate: predicate)
            case .vo2Max:
                data = try await fetchQuantitySamples(
                    identifier: .vo2Max,
                    unit: HKUnit(from: "ml/kg*min"),
                    unitLabel: "ml/(kg·min)",
                    predicate: predicate,
                    keyPath: \.vo2Max
                )
            case .heartRateRecoveryOneMinute:
                data = try await fetchQuantitySamples(
                    identifier: .heartRateRecoveryOneMinute,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    unitLabel: "count/min",
                    predicate: predicate,
                    keyPath: \.heartRateRecoveryOneMinute
                )
            case .walkingHeartRateAverage:
                data = try await fetchQuantitySamples(
                    identifier: .walkingHeartRateAverage,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    unitLabel: "count/min",
                    predicate: predicate,
                    keyPath: \.walkingHeartRateAverage
                )
            case .walkingAsymmetryPercentage:
                data = try await fetchQuantitySamples(
                    identifier: .walkingAsymmetryPercentage,
                    unit: HKUnit.percent(),
                    unitLabel: "%",
                    predicate: predicate,
                    keyPath: \.walkingAsymmetryPercentage,
                    valueTransform: { $0 * 100 }
                )
            case .walkingDoubleSupportPercentage:
                data = try await fetchQuantitySamples(
                    identifier: .walkingDoubleSupportPercentage,
                    unit: HKUnit.percent(),
                    unitLabel: "%",
                    predicate: predicate,
                    keyPath: \.walkingDoubleSupportPercentage,
                    valueTransform: { $0 * 100 }
                )
            case .appleSleepingWristTemperature:
                data = try await fetchQuantitySamples(
                    identifier: .appleSleepingWristTemperature,
                    unit: HKUnit.degreeCelsius(),
                    unitLabel: "degC",
                    predicate: predicate,
                    keyPath: \.appleSleepingWristTemperature
                )
            case .oxygenSaturation:
                data = try await fetchQuantitySamples(
                    identifier: .oxygenSaturation,
                    unit: HKUnit.percent(),
                    unitLabel: "%",
                    predicate: predicate,
                    keyPath: \.oxygenSaturation,
                    valueTransform: { $0 * 100 }
                )
            case .timeInDaylight:
                data = try await fetchDailyQuantityStatistics(
                    identifier: .timeInDaylight,
                    unit: HKUnit.minute(),
                    unitLabel: "min",
                    start: start,
                    end: end,
                    predicate: predicate,
                    keyPath: \.timeInDaylight
                )
            case .activeEnergyBurned:
                data = try await fetchDailyQuantityStatistics(
                    identifier: .activeEnergyBurned,
                    unit: HKUnit.kilocalorie(),
                    unitLabel: "kcal",
                    start: start,
                    end: end,
                    predicate: predicate,
                    keyPath: \.activeEnergyBurned
                )
            case .basalEnergyBurned:
                data = try await fetchDailyQuantityStatistics(
                    identifier: .basalEnergyBurned,
                    unit: HKUnit.kilocalorie(),
                    unitLabel: "kcal",
                    start: start,
                    end: end,
                    predicate: predicate,
                    keyPath: \.basalEnergyBurned
                )
            case .appleStandTime:
                data = try await fetchDailyQuantityStatistics(
                    identifier: .appleStandTime,
                    unit: HKUnit.minute(),
                    unitLabel: "min",
                    start: start,
                    end: end,
                    predicate: predicate,
                    keyPath: \.appleStandTime
                )
            case .stepLength:
                data = try await fetchQuantitySamples(
                    identifier: .walkingStepLength,
                    unit: HKUnit.meter(),
                    unitLabel: "m",
                    predicate: predicate,
                    keyPath: \.stepLength
                )
            case .stairAscentSpeed:
                data = try await fetchQuantitySamples(
                    identifier: .stairAscentSpeed,
                    unit: HKUnit.meter().unitDivided(by: .second()),
                    unitLabel: "m/s",
                    predicate: predicate,
                    keyPath: \.stairAscentSpeed
                )
            case .stairDescentSpeed:
                data = try await fetchQuantitySamples(
                    identifier: .stairDescentSpeed,
                    unit: HKUnit.meter().unitDivided(by: .second()),
                    unitLabel: "m/s",
                    predicate: predicate,
                    keyPath: \.stairDescentSpeed
                )
            case .environmentalAudioExposure:
                data = try await fetchQuantitySamples(
                    identifier: .environmentalAudioExposure,
                    unit: HKUnit.decibelAWeightedSoundPressureLevel(),
                    unitLabel: "dBASPL",
                    predicate: predicate,
                    keyPath: \.environmentalAudioExposure
                )
            case .dietaryCaffeine:
                data = try await fetchQuantitySamples(
                    identifier: .dietaryCaffeine,
                    unit: HKUnit.gramUnit(with: .milli),
                    unitLabel: "mg",
                    predicate: predicate,
                    keyPath: \.dietaryCaffeine
                )
            }
            return (kind, .success(data))
        } catch {
            return (kind, .failure(error))
        }
    }

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        unitLabel: String,
        predicate: NSPredicate,
        keyPath: WritableKeyPath<DailyHealthData, [QuantityRecord]?>,
        valueTransform: ((Double) -> Double)? = nil
    ) async throws -> [String: DailyHealthData] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthExportError.unsupportedType(identifier.rawValue)
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.quantitySample(type: quantityType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        let samples = try await descriptor.result(for: healthStore)
        var result: [String: DailyHealthData] = [:]

        for sample in samples {
            guard let quantitySample = sample as? HKQuantitySample else { continue }
            let day = dayKey(for: quantitySample.startDate)
            let rawValue = quantitySample.quantity.doubleValue(for: unit)
            let exportValue = valueTransform?(rawValue) ?? rawValue
            let record = QuantityRecord(
                start: isoFormatter.string(from: quantitySample.startDate),
                end: isoFormatter.string(from: quantitySample.endDate),
                value: exportValue,
                unit: unitLabel
            )

            var daily = result[day] ?? DailyHealthData()
            var records = daily[keyPath: keyPath] ?? []
            records.append(record)
            daily[keyPath: keyPath] = records
            result[day] = daily
        }

        return result
    }

    private func fetchSleepSamples(predicate: NSPredicate) async throws -> [String: DailyHealthData] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthExportError.unsupportedType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        let samples = try await descriptor.result(for: healthStore)
        var result: [String: DailyHealthData] = [:]

        for sample in samples {
            guard let categorySample = sample as? HKCategorySample else { continue }
            let day = dayKey(for: categorySample.startDate)
            let record = SleepRecord(
                start: isoFormatter.string(from: categorySample.startDate),
                end: isoFormatter.string(from: categorySample.endDate),
                stage: sleepStageName(for: categorySample.value)
            )

            var daily = result[day] ?? DailyHealthData()
            var records = daily.sleep ?? []
            records.append(record)
            daily.sleep = records
            result[day] = daily
        }

        return result
    }

    private func fetchWorkoutSamples(predicate: NSPredicate) async throws -> [String: DailyHealthData] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        let samples = try await descriptor.result(for: healthStore)
        var result: [String: DailyHealthData] = [:]

        for sample in samples {
            guard let workout = sample as? HKWorkout else { continue }
            let day = dayKey(for: workout.startDate)

            let energyKcal: Double?
            if let energy = workout.totalEnergyBurned {
                energyKcal = energy.doubleValue(for: HKUnit.kilocalorie())
            } else {
                energyKcal = nil
            }

            let record = WorkoutRecord(
                activityType: workoutActivityName(workout.workoutActivityType),
                start: isoFormatter.string(from: workout.startDate),
                end: isoFormatter.string(from: workout.endDate),
                durationMinutes: workout.duration / 60.0,
                totalEnergyKcal: energyKcal
            )

            var daily = result[day] ?? DailyHealthData()
            var records = daily.workouts ?? []
            records.append(record)
            daily.workouts = records
            result[day] = daily
        }

        return result
    }

    private func fetchDailyStepStatistics(
        start: Date,
        end: Date,
        predicate: NSPredicate
    ) async throws -> [String: DailyHealthData] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthExportError.unsupportedType(HKQuantityTypeIdentifier.stepCount.rawValue)
        }

        let anchorDate = Calendar.current.startOfDay(for: start)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await descriptor.result(for: healthStore)
        var result: [String: DailyHealthData] = [:]

        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let day = self.dayFormatter.string(from: statistics.startDate)
            let total: Int
            if let sum = statistics.sumQuantity() {
                total = Int(sum.doubleValue(for: HKUnit.count()))
            } else {
                total = 0
            }

            let daily = DailyHealthData(
                stepCount: StepDaySummary(total: total, unit: "count")
            )
            result[day] = daily
        }

        return result
    }

    private func fetchDailyQuantityStatistics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        unitLabel: String,
        start: Date,
        end: Date,
        predicate: NSPredicate,
        keyPath: WritableKeyPath<DailyHealthData, DailyQuantitySummary?>
    ) async throws -> [String: DailyHealthData] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthExportError.unsupportedType(identifier.rawValue)
        }

        let anchorDate = Calendar.current.startOfDay(for: start)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: quantityType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await descriptor.result(for: healthStore)
        var result: [String: DailyHealthData] = [:]

        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let day = self.dayFormatter.string(from: statistics.startDate)
            let total: Double
            if let sum = statistics.sumQuantity() {
                total = sum.doubleValue(for: unit)
            } else {
                total = 0
            }

            var daily = DailyHealthData()
            daily[keyPath: keyPath] = DailyQuantitySummary(
                total: total,
                unit: unitLabel,
                source: "statistics.cumulativeSum"
            )
            result[day] = daily
        }

        return result
    }

    // MARK: - Merge & Persist

    private func mergeDaily(_ partial: [String: DailyHealthData], into target: inout [String: DailyHealthData]) {
        for (day, incoming) in partial {
            var existing = target[day] ?? DailyHealthData()

            if let values = incoming.heartRate {
                existing.heartRate = (existing.heartRate ?? []) + values
            }
            if let values = incoming.restingHeartRate {
                existing.restingHeartRate = (existing.restingHeartRate ?? []) + values
            }
            if let values = incoming.hrv {
                existing.hrv = (existing.hrv ?? []) + values
            }
            if let values = incoming.respiratoryRate {
                existing.respiratoryRate = (existing.respiratoryRate ?? []) + values
            }
            if let values = incoming.sleep {
                existing.sleep = (existing.sleep ?? []) + values
            }
            if let values = incoming.workouts {
                existing.workouts = (existing.workouts ?? []) + values
            }
            if let stepCount = incoming.stepCount {
                existing.stepCount = stepCount
            }
            if let values = incoming.vo2Max {
                existing.vo2Max = (existing.vo2Max ?? []) + values
            }
            if let values = incoming.heartRateRecoveryOneMinute {
                existing.heartRateRecoveryOneMinute = (existing.heartRateRecoveryOneMinute ?? []) + values
            }
            if let values = incoming.walkingHeartRateAverage {
                existing.walkingHeartRateAverage = (existing.walkingHeartRateAverage ?? []) + values
            }
            if let values = incoming.walkingAsymmetryPercentage {
                existing.walkingAsymmetryPercentage = (existing.walkingAsymmetryPercentage ?? []) + values
            }
            if let values = incoming.walkingDoubleSupportPercentage {
                existing.walkingDoubleSupportPercentage = (existing.walkingDoubleSupportPercentage ?? []) + values
            }
            if let values = incoming.appleSleepingWristTemperature {
                existing.appleSleepingWristTemperature = (existing.appleSleepingWristTemperature ?? []) + values
            }
            if let values = incoming.oxygenSaturation {
                existing.oxygenSaturation = (existing.oxygenSaturation ?? []) + values
            }
            if let timeInDaylight = incoming.timeInDaylight {
                existing.timeInDaylight = timeInDaylight
            }
            if let activeEnergyBurned = incoming.activeEnergyBurned {
                existing.activeEnergyBurned = activeEnergyBurned
            }
            if let basalEnergyBurned = incoming.basalEnergyBurned {
                existing.basalEnergyBurned = basalEnergyBurned
            }
            if let appleStandTime = incoming.appleStandTime {
                existing.appleStandTime = appleStandTime
            }
            if let values = incoming.stepLength {
                existing.stepLength = (existing.stepLength ?? []) + values
            }
            if let values = incoming.stairAscentSpeed {
                existing.stairAscentSpeed = (existing.stairAscentSpeed ?? []) + values
            }
            if let values = incoming.stairDescentSpeed {
                existing.stairDescentSpeed = (existing.stairDescentSpeed ?? []) + values
            }
            if let values = incoming.environmentalAudioExposure {
                existing.environmentalAudioExposure = (existing.environmentalAudioExposure ?? []) + values
            }
            if let values = incoming.dietaryCaffeine {
                existing.dietaryCaffeine = (existing.dietaryCaffeine ?? []) + values
            }

            target[day] = existing
        }
    }

    @discardableResult
    private func saveJSONToDocuments(data: Data, filename: String) throws -> URL {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw HealthExportError.documentsDirectoryUnavailable
        }

        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)

        let fileURL = documentDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HealthExportError.fileNotWritten(filename)
        }

        return fileURL
    }

    private func listExportFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files.filter {
            $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasPrefix("HealthExport_")
        }
    }

    private func buildExportSummary(from dataByDate: [String: DailyHealthData]) -> ExportSummary {
        var heartRate = 0
        var restingHeartRate = 0
        var respiratoryRate = 0
        var sleep = 0
        var workouts = 0
        var stepDays = 0
        var hrv = 0
        var vo2Max = 0
        var heartRateRecovery = 0
        var walkingHeartRate = 0
        var walkingAsymmetry = 0
        var walkingDoubleSupport = 0
        var wristTemperature = 0
        var oxygenSaturation = 0
        var timeInDaylightDays = 0
        var activeEnergyDays = 0
        var basalEnergyDays = 0
        var appleStandTimeDays = 0
        var stepLength = 0
        var stairAscentSpeed = 0
        var stairDescentSpeed = 0
        var environmentalAudioExposure = 0
        var dietaryCaffeine = 0

        for daily in dataByDate.values {
            heartRate += daily.heartRate?.count ?? 0
            restingHeartRate += daily.restingHeartRate?.count ?? 0
            hrv += daily.hrv?.count ?? 0
            respiratoryRate += daily.respiratoryRate?.count ?? 0
            sleep += daily.sleep?.count ?? 0
            workouts += daily.workouts?.count ?? 0
            if daily.stepCount != nil { stepDays += 1 }
            vo2Max += daily.vo2Max?.count ?? 0
            heartRateRecovery += daily.heartRateRecoveryOneMinute?.count ?? 0
            walkingHeartRate += daily.walkingHeartRateAverage?.count ?? 0
            walkingAsymmetry += daily.walkingAsymmetryPercentage?.count ?? 0
            walkingDoubleSupport += daily.walkingDoubleSupportPercentage?.count ?? 0
            wristTemperature += daily.appleSleepingWristTemperature?.count ?? 0
            oxygenSaturation += daily.oxygenSaturation?.count ?? 0
            if daily.timeInDaylight != nil { timeInDaylightDays += 1 }
            if daily.activeEnergyBurned != nil { activeEnergyDays += 1 }
            if daily.basalEnergyBurned != nil { basalEnergyDays += 1 }
            if daily.appleStandTime != nil { appleStandTimeDays += 1 }
            stepLength += daily.stepLength?.count ?? 0
            stairAscentSpeed += daily.stairAscentSpeed?.count ?? 0
            stairDescentSpeed += daily.stairDescentSpeed?.count ?? 0
            environmentalAudioExposure += daily.environmentalAudioExposure?.count ?? 0
            dietaryCaffeine += daily.dietaryCaffeine?.count ?? 0
        }

        return ExportSummary(
            dayCount: dataByDate.count,
            heartRateSamples: heartRate,
            restingHeartRateSamples: restingHeartRate,
            respiratoryRateSamples: respiratoryRate,
            sleepSamples: sleep,
            workoutSamples: workouts,
            stepDays: stepDays,
            hrvSamples: hrv,
            vo2MaxSamples: vo2Max,
            heartRateRecoverySamples: heartRateRecovery,
            walkingHeartRateSamples: walkingHeartRate,
            walkingAsymmetrySamples: walkingAsymmetry,
            walkingDoubleSupportSamples: walkingDoubleSupport,
            wristTemperatureSamples: wristTemperature,
            oxygenSaturationSamples: oxygenSaturation,
            timeInDaylightDays: timeInDaylightDays,
            activeEnergyDays: activeEnergyDays,
            basalEnergyDays: basalEnergyDays,
            appleStandTimeDays: appleStandTimeDays,
            stepLengthSamples: stepLength,
            stairAscentSpeedSamples: stairAscentSpeed,
            stairDescentSpeedSamples: stairDescentSpeed,
            environmentalAudioExposureSamples: environmentalAudioExposure,
            dietaryCaffeineSamples: dietaryCaffeine
        )
    }

    // MARK: - Helpers

    private func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func sleepStageName(for value: Int) -> String {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return "unknown(\(value))"
        }

        switch stage {
        case .inBed: return "inBed"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake: return "awake"
        case .asleepCore: return "asleepCore"
        case .asleepDeep: return "asleepDeep"
        case .asleepREM: return "asleepREM"
        @unknown default: return "unknown(\(value))"
        }
    }

    private func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .hiking: return "徒步"
        case .yoga: return "瑜伽"
        case .functionalStrengthTraining: return "功能性力量训练"
        case .traditionalStrengthTraining: return "传统力量训练"
        case .highIntensityIntervalTraining: return "高强度间歇训练"
        case .elliptical: return "椭圆机"
        case .stairClimbing: return "爬楼梯"
        case .rowing: return "划船"
        case .coreTraining: return "核心训练"
        case .mixedCardio: return "混合有氧"
        case .dance: return "舞蹈"
        case .pilates: return "普拉提"
        case .crossTraining: return "交叉训练"
        case .flexibility: return "柔韧训练"
        case .cooldown: return "放松整理"
        case .wheelchairWalkPace: return "轮椅步行"
        case .wheelchairRunPace: return "轮椅跑步"
        case .handCycling: return "手摇车"
        case .tennis: return "网球"
        case .basketball: return "篮球"
        case .soccer: return "足球"
        case .golf: return "高尔夫"
        case .badminton: return "羽毛球"
        case .tableTennis: return "乒乓球"
        case .jumpRope: return "跳绳"
        case .stairs: return "楼梯"
        case .stepTraining: return "踏步训练"
        case .barre: return "芭蕾把杆"
        case .mindAndBody: return "身心训练"
        case .preparationAndRecovery: return "准备与恢复"
        case .other: return "其他"
        default: return "其他(\(type.rawValue))"
        }
    }
}

enum HealthExportError: LocalizedError {
    case unsupportedType(String)
    case documentsDirectoryUnavailable
    case fileNotWritten(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            return "不支持的数据类型: \(name)"
        case .documentsDirectoryUnavailable:
            return "无法访问 Documents 目录"
        case .fileNotWritten(let name):
            return "文件写入后未找到: \(name)"
        }
    }
}
