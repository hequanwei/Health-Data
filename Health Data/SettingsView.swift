//
//  SettingsView.swift
//  Health Data
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = HealthAlertSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("扫描后推送本地通知", isOn: $settings.notificationsEnabled)
                    Toggle("每日后台自动扫描", isOn: $settings.backgroundScanEnabled)
                } footer: {
                    Text("后台扫描由系统调度，通常在设备充电且连接网络时执行。Widget 与通知依赖扫描结果更新。")
                }

                if let lastScan = BackgroundScanStore.lastCompletedAt() {
                    Section("后台扫描") {
                        LabeledContent("上次后台扫描") {
                            Text(lastScan, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("HRV 阈值") {
                    thresholdRow(
                        title: "警告线（相对基线）",
                        value: $settings.thresholds.hrvWarningRatio,
                        range: 0.50...0.95,
                        format: "%.0f%%",
                        multiplier: 100
                    )
                    thresholdRow(
                        title: "严重线（相对基线）",
                        value: $settings.thresholds.hrvCriticalRatio,
                        range: 0.40...0.85,
                        format: "%.0f%%",
                        multiplier: 100
                    )
                }

                Section("静息心率") {
                    thresholdRow(
                        title: "警告增量 (bpm)",
                        value: $settings.thresholds.restingHRWarningDelta,
                        range: 2...12,
                        format: "%.0f",
                        multiplier: 1
                    )
                    thresholdRow(
                        title: "严重增量 (bpm)",
                        value: $settings.thresholds.restingHRCriticalDelta,
                        range: 4...15,
                        format: "%.0f",
                        multiplier: 1
                    )
                }

                Section("睡眠") {
                    thresholdRow(
                        title: "不足警告 (小时)",
                        value: $settings.thresholds.minSleepWarningHours,
                        range: 4...8,
                        format: "%.1f",
                        multiplier: 1
                    )
                    thresholdRow(
                        title: "严重不足 (小时)",
                        value: $settings.thresholds.minSleepCriticalHours,
                        range: 3...7,
                        format: "%.1f",
                        multiplier: 1
                    )
                }

                Section("训练负荷") {
                    thresholdRow(
                        title: "低 HRV 日训练时长 (分钟)",
                        value: $settings.thresholds.minWorkoutMinutesForLoadAlert,
                        range: 10...60,
                        format: "%.0f",
                        multiplier: 1
                    )
                }

                Section {
                    Button("恢复默认阈值") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("提醒设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func thresholdRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        multiplier: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: multiplier == 100 ? 0.05 : (multiplier == 1 && range.upperBound <= 8 ? 0.5 : 1))
        }
    }
}
