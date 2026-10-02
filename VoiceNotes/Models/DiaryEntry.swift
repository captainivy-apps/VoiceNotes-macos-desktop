import Foundation

struct DiaryEntry: Identifiable, Equatable {
    var id: Int64 = 0
    var createdAt: Int64
    var updatedAt: Int64
    var audioPath: String?
    var transcriptText: String?
    var diaryText: String?
    var durationMs: Int64 = 0

    var createdAtDate: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000.0) }
    var updatedAtDate: Date { Date(timeIntervalSince1970: Double(updatedAt) / 1000.0) }
}
