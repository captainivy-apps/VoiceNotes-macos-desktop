import AppKit
import Foundation

func formatDuration(_ milliseconds: Int64) -> String {
    let totalSeconds = max(0, milliseconds) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
}()

func formatDateTime(_ milliseconds: Int64) -> String {
    dateTimeFormatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000.0))
}

func formatFileSize(_ bytes: Int64) -> String {
    switch bytes {
    case ..<1024:
        return "\(bytes) B"
    case ..<(1024 * 1024):
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    default:
        return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

func audioFileSize(_ path: String?) -> Int64 {
    guard let path, let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber else { return 0 }
    return size.int64Value
}

func textByteSize(_ text: String?) -> Int64 {
    guard let text, !text.isEmpty else { return 0 }
    return Int64(text.utf8.count)
}

func diaryTotalSize(audioPath: String?, transcript: String?, diaryText: String?) -> Int64 {
    audioFileSize(audioPath) + textByteSize(transcript) + textByteSize(diaryText)
}

func diaryTotalSize(_ entry: DiaryEntry) -> Int64 {
    diaryTotalSize(audioPath: entry.audioPath, transcript: entry.transcriptText, diaryText: entry.diaryText)
}

func diaryPreview(_ entry: DiaryEntry) -> String {
    let polished = entry.diaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let transcript = entry.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let text = polished.isEmpty ? transcript : polished
    guard !text.isEmpty else { return "新录音" }
    let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
    return String(firstLine.prefix(40))
}

func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
