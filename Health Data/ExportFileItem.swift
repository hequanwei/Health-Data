//
//  ExportFileItem.swift
//  Health Data
//

import Foundation

struct ExportFileItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let fileName: String
    let fileSize: Int64
    let modifiedAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    static func from(url: URL) -> ExportFileItem? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return ExportFileItem(
            id: url.path,
            url: url,
            fileName: url.lastPathComponent,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
    }
}
