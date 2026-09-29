//
//  RecoveryScoreWidget.swift
//  Health Data Widget
//

import SwiftUI
import WidgetKit

struct RecoveryScoreEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetRecoverySnapshot
}

struct RecoveryScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryScoreEntry {
        RecoveryScoreEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryScoreEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .placeholder
        completion(RecoveryScoreEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryScoreEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .placeholder
        let entry = RecoveryScoreEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(60 * 60 * 6)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct RecoveryScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryScoreEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("恢复分", systemImage: "waveform.path.ecg")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(entry.snapshot.recoveryScore)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)

            Text(entry.snapshot.recoveryStatusLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let hrv = entry.snapshot.latestHrvMs {
                Text(String(format: "HRV %.0f ms", hrv))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            statusColor.opacity(0.12)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("恢复分", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(entry.snapshot.recoveryScore)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)

                Text(entry.snapshot.recoveryStatusLabel)
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if let hrv = entry.snapshot.latestHrvMs, let baseline = entry.snapshot.baselineHrvMs {
                    metricRow(title: "HRV", value: String(format: "%.0f ms", hrv))
                    metricRow(title: "基线", value: String(format: "%.0f ms", baseline))
                }
                metricRow(title: "分析天数", value: "\(entry.snapshot.analyzedDayCount)")
                if entry.snapshot.alertCount > 0 {
                    metricRow(title: "提醒", value: "\(entry.snapshot.alertCount) 条")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            statusColor.opacity(0.12)
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var statusColor: Color {
        switch entry.snapshot.recoveryStatus {
        case "good": return .green
        case "moderate": return .yellow
        case "caution": return .orange
        case "alert": return .red
        default: return .blue
        }
    }
}

struct RecoveryScoreWidget: Widget {
    let kind = "RecoveryScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryScoreProvider()) { entry in
            RecoveryScoreWidgetView(entry: entry)
        }
        .configurationDisplayName("恢复分")
        .description("显示最近一次健康扫描的恢复分与 HRV。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    RecoveryScoreWidget()
} timeline: {
    RecoveryScoreEntry(date: .now, snapshot: WidgetRecoverySnapshot(
        recoveryScore: 78,
        recoveryStatus: "good",
        recoveryStatusLabel: "恢复良好",
        latestHrvMs: 52,
        baselineHrvMs: 48,
        analyzedDayCount: 7,
        weeklyFlags: [],
        alertCount: 0,
        updatedAt: .now
    ))
}
