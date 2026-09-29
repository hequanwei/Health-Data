//
//  ContentView.swift
//  Health Data
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject var healthManager = HealthManager()
    @State private var showSettings = false
    @State private var copiedPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "waveform.path.ecg")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.blue)

                    Text("本地生化数据枢纽")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let insight = healthManager.healthInsight, insight.analyzedDayCount > 0 {
                        RecoveryStatusCard(insight: insight)
                        if !insight.weeklyFlags.isEmpty {
                            WeeklyFlagsSection(flags: insight.weeklyFlags)
                        }
                        HealthAlertsSection(alerts: insight.alerts)

                        if let prompt = insight.suggestedAnalysisPrompt {
                            CopyPromptButton(prompt: prompt, copied: $copiedPrompt)
                        }
                    }

                    Text(healthManager.statusMessage)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .frame(minHeight: 80)

                    Button(action: {
                        Task { await healthManager.checkHealthAlerts() }
                    }) {
                        HStack {
                            if healthManager.isCheckingAlerts {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(healthManager.isCheckingAlerts ? "扫描中…" : "扫描健康提醒")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(healthManager.isCheckingAlerts ? Color.gray : Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(healthManager.isCheckingAlerts || healthManager.isExporting)
                    .padding(.horizontal, 40)

                    Button(action: {
                        Task {
                            await healthManager.requestAuthorization()
                            await healthManager.exportHealthData()
                        }
                    }) {
                        Text(healthManager.isExporting ? "导出中…" : "导出近 7 日健康数据")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(healthManager.isExporting ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(healthManager.isExporting || healthManager.isCheckingAlerts)
                    .padding(.horizontal, 40)

                    if let fileURL = healthManager.lastExportedFileURL {
                        ShareLink(item: fileURL) {
                            Label("分享最新 JSON 文件", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }

                    NavigationLink {
                        ExportHistoryView(healthManager: healthManager)
                    } label: {
                        Label("导出历史管理", systemImage: "folder")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 24)

                    Text("非医疗诊断，仅供参考。提醒基于本地规则引擎，不能替代医生诊断。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("提醒设置")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .onAppear {
            healthManager.refreshExportedFilesList()
            BackgroundScanScheduler.scheduleNextScan()
            Task { await healthManager.checkHealthAlerts() }
        }
    }
}

private struct WeeklyFlagsSection: View {
    let flags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("周级标记")
                .font(.headline)
                .padding(.horizontal, 24)

            FlowLayout(spacing: 8) {
                ForEach(flags, id: \.self) { flag in
                    Text(flagLabel(flag))
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func flagLabel(_ flag: String) -> String {
        switch flag {
        case "hrv_cliff": return "HRV 断崖"
        case "hrv_low": return "HRV 偏低"
        case "hrv_sustained_low": return "HRV 持续低"
        case "rhr_elevated": return "静息心率偏高"
        case "rhr_sustained_high": return "静息心率持续高"
        case "sleep_low": return "睡眠不足"
        case "sleep_critical": return "睡眠严重不足"
        case "training_while_suppressed": return "低恢复日训练"
        default: return flag
        }
    }
}

private struct CopyPromptButton: View {
    let prompt: String
    @Binding var copied: Bool

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = prompt
            #endif
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        } label: {
            Label(copied ? "已复制 AI 分析 Prompt" : "复制 AI 分析 Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
        .padding(.horizontal, 24)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

private struct RecoveryStatusCard: View {
    let insight: HealthInsightResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.recoveryStatus.iconName)
                    .foregroundColor(insight.recoveryStatus.color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.recoveryStatus.label)
                        .font(.headline)
                    Text("恢复分 \(insight.recoveryScore) / 100")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if let latest = insight.latestHrvMs, let baseline = insight.baselineHrvMs {
                HStack {
                    Label(String(format: "最新 HRV %.0f ms", latest), systemImage: "waveform.path.ecg")
                    Spacer()
                    Text(String(format: "基线 %.0f ms", baseline))
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            Text("已分析近 \(insight.analyzedDayCount) 天数据")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insight.recoveryStatus.color.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
}

private struct HealthAlertsSection: View {
    let alerts: [HealthAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("健康提醒")
                .font(.headline)
                .padding(.horizontal, 24)

            ForEach(alerts) { alert in
                HealthAlertRow(alert: alert)
            }
        }
    }
}

private struct HealthAlertRow: View {
    let alert: HealthAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity.iconName)
                .foregroundColor(alert.severity.color)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(alert.severity.title)
                        .font(.caption2)
                        .foregroundColor(alert.severity.color)
                }
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = alert.relatedDate {
                    Text(date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 24)
    }
}
