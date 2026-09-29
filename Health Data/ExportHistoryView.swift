//
//  ExportHistoryView.swift
//  Health Data
//

import SwiftUI

struct ExportHistoryView: View {
    @ObservedObject var healthManager: HealthManager
    @State private var showDeleteAllConfirm = false
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if healthManager.exportFileItems.isEmpty {
                ContentUnavailableView(
                    "暂无导出记录",
                    systemImage: "doc.text",
                    description: Text("执行「导出近 7 日健康数据」后，JSON 文件会出现在这里。")
                )
            } else {
                List {
                    ForEach(healthManager.exportFileItems) { item in
                        ExportFileRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteItem(item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("导出历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !healthManager.exportFileItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        showDeleteAllConfirm = true
                    }
                }
            }
        }
        .confirmationDialog("确定删除全部导出文件？", isPresented: $showDeleteAllConfirm, titleVisibility: .visible) {
            Button("删除全部", role: .destructive) {
                deleteAll()
            }
            Button("取消", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            healthManager.refreshExportedFilesList()
        }
    }

    private func deleteItem(_ item: ExportFileItem) {
        do {
            try healthManager.deleteExport(at: item.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAll() {
        do {
            try healthManager.deleteAllExports()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExportFileRow: View {
    let item: ExportFileItem

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(item.formattedSize) · \(Self.dateFormatter.string(from: item.modifiedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
