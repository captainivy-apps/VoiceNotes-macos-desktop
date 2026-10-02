import Foundation

enum ExportFileNames {
    static let typeRecord = "record"
    static let typeFirst = "first"
    static let typeFinal = "final"

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func build(type: String, extension ext: String, timestamp: Date = Date()) -> String {
        let cleanExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        return "voicenotes-\(type)-\(timestampFormatter.string(from: timestamp)).\(cleanExt)"
    }

    static func audioExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "wav" : ext
    }
}
