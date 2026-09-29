//
//  HealthExportModels.swift
//  Health Data
//

import Foundation

struct HealthExportPayload: Codable {
    let schemaVersion: Int
    let exportedAt: String
    let periodStart: String
    let periodEnd: String
    let notes: String?
    let errors: [String: String]?
    let exportSummary: ExportSummary?
    let dataByDate: [String: DailyHealthData]
    let dailySummaries: [String: DailySummary]?
    let weeklyInsight: WeeklyInsightExport?
}

struct DailySummary: Codable {
    let hrvAvgMs: Double?
    let restingHeartRateAvg: Double?
    let sleepMinutes: Double?
    let workoutCount: Int
    let workoutMinutes: Double
    let stepCount: Int?
    let activeEnergyKcal: Double?
    let flags: [String]
}

struct WeeklyInsightExport: Codable {
    let recoveryScore: Int
    let recoveryStatus: String
    let baselineHrvMs: Double?
    let latestHrvMs: Double?
    let weeklyFlags: [String]
    let alertCount: Int
    let criticalAlertCount: Int
    let alerts: [HealthAlert]
    let suggestedAnalysisPrompt: String
}

struct ExportSummary: Codable {
    let dayCount: Int
    let heartRateSamples: Int
    let restingHeartRateSamples: Int
    let respiratoryRateSamples: Int
    let sleepSamples: Int
    let workoutSamples: Int
    let stepDays: Int
    let hrvSamples: Int
    let vo2MaxSamples: Int
    let heartRateRecoverySamples: Int
    let walkingHeartRateSamples: Int
    let walkingAsymmetrySamples: Int
    let walkingDoubleSupportSamples: Int
    let wristTemperatureSamples: Int
    let oxygenSaturationSamples: Int
    let timeInDaylightDays: Int
    let activeEnergyDays: Int
    let basalEnergyDays: Int
    let appleStandTimeDays: Int
    let stepLengthSamples: Int
    let stairAscentSpeedSamples: Int
    let stairDescentSpeedSamples: Int
    let environmentalAudioExposureSamples: Int
    let dietaryCaffeineSamples: Int
}

struct DailyHealthData: Codable {
    var heartRate: [QuantityRecord]?
    var restingHeartRate: [QuantityRecord]?
    var hrv: [QuantityRecord]?
    var respiratoryRate: [QuantityRecord]?
    var sleep: [SleepRecord]?
    var workouts: [WorkoutRecord]?
    var stepCount: StepDaySummary?
    var vo2Max: [QuantityRecord]?
    var heartRateRecoveryOneMinute: [QuantityRecord]?
    var walkingHeartRateAverage: [QuantityRecord]?
    var walkingAsymmetryPercentage: [QuantityRecord]?
    var walkingDoubleSupportPercentage: [QuantityRecord]?
    var appleSleepingWristTemperature: [QuantityRecord]?
    var oxygenSaturation: [QuantityRecord]?
    var timeInDaylight: DailyQuantitySummary?
    var activeEnergyBurned: DailyQuantitySummary?
    var basalEnergyBurned: DailyQuantitySummary?
    var appleStandTime: DailyQuantitySummary?
    var stepLength: [QuantityRecord]?
    var stairAscentSpeed: [QuantityRecord]?
    var stairDescentSpeed: [QuantityRecord]?
    var environmentalAudioExposure: [QuantityRecord]?
    var dietaryCaffeine: [QuantityRecord]?
}

struct QuantityRecord: Codable {
    let start: String
    let end: String
    let value: Double
    let unit: String
}

struct DailyQuantitySummary: Codable {
    let total: Double
    let unit: String
    let source: String
}

struct SleepRecord: Codable {
    let start: String
    let end: String
    let stage: String
}

struct WorkoutRecord: Codable {
    let activityType: String
    let start: String
    let end: String
    let durationMinutes: Double
    let totalEnergyKcal: Double?
}

struct StepDaySummary: Codable {
    let total: Int
    let unit: String
}
