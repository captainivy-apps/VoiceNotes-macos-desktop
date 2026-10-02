import Foundation

/// Persists diary entries in SQLite, mirroring the Android Room DAO semantics.
actor DiaryStore {
    private let db: SQLiteDatabase

    init(databaseURL: URL = Paths.databaseURL) throws {
        db = try SQLiteDatabase(path: databaseURL.path)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS diary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            audio_path TEXT,
            transcript_text TEXT,
            diary_text TEXT,
            duration_ms INTEGER NOT NULL DEFAULT 0
        );
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_diary_created_at ON diary_entries(created_at DESC);")
    }

    func allOrdered() throws -> [DiaryEntry] {
        try db.query("SELECT * FROM diary_entries ORDER BY created_at DESC") { mapRow($0) }
    }

    func get(_ id: Int64) throws -> DiaryEntry? {
        try db.query("SELECT * FROM diary_entries WHERE id = ? LIMIT 1", [.integer(id)]) { mapRow($0) }.first
    }

    @discardableResult
    func createDraft(audioPath: String, durationMs: Int64) throws -> DiaryEntry {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try db.run(
            "INSERT INTO diary_entries (created_at, updated_at, audio_path, transcript_text, diary_text, duration_ms) VALUES (?, ?, ?, NULL, NULL, ?)",
            [.integer(now), .integer(now), .text(audioPath), .integer(durationMs)]
        )
        let id = db.lastInsertRowID
        return try get(id) ?? DiaryEntry(id: id, createdAt: now, updatedAt: now, audioPath: audioPath, transcriptText: nil, diaryText: nil, durationMs: durationMs)
    }

    func update(_ entry: DiaryEntry) throws {
        try db.run(
            "UPDATE diary_entries SET created_at = ?, updated_at = ?, audio_path = ?, transcript_text = ?, diary_text = ?, duration_ms = ? WHERE id = ?",
            [
                .integer(entry.createdAt),
                .integer(Int64(Date().timeIntervalSince1970 * 1000)),
                .optionalText(entry.audioPath),
                .optionalText(entry.transcriptText),
                .optionalText(entry.diaryText),
                .integer(entry.durationMs),
                .integer(entry.id)
            ]
        )
    }

    func saveTranscript(id: Int64, transcript: String) throws {
        guard let entry = try get(id) else { return }
        var copy = entry
        copy.transcriptText = transcript
        try update(copy)
    }

    func saveDiaryText(id: Int64, diaryText: String) throws {
        guard let entry = try get(id) else { return }
        var copy = entry
        copy.diaryText = diaryText
        try update(copy)
    }

    func deleteAudio(id: Int64) throws {
        guard let entry = try get(id) else { return }
        if let path = entry.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        var copy = entry
        copy.audioPath = nil
        try update(copy)
    }

    func deleteTranscript(id: Int64) throws {
        guard let entry = try get(id) else { return }
        var copy = entry
        copy.transcriptText = nil
        try update(copy)
    }

    func deleteDiaryText(id: Int64) throws {
        guard let entry = try get(id) else { return }
        var copy = entry
        copy.diaryText = nil
        try update(copy)
    }

    func deleteEntry(id: Int64) throws {
        if let entry = try get(id), let path = entry.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try db.run("DELETE FROM diary_entries WHERE id = ?", [.integer(id)])
    }

    func deleteEntries(ids: [Int64]) throws {
        for id in ids {
            if let entry = try get(id), let path = entry.audioPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        try db.run("DELETE FROM diary_entries WHERE id IN (\(placeholders))", ids.map { .integer($0) })
    }

    /// Previous/next neighbor following the Android convention:
    /// `prev` is the older entry (index + 1 in descending order), `next` is newer (index - 1).
    func neighborIds(currentId: Int64) throws -> (prev: Int64?, next: Int64?) {
        let all = try allOrdered()
        guard let index = all.firstIndex(where: { $0.id == currentId }) else { return (nil, nil) }
        let prev = index + 1 < all.count ? all[index + 1].id : nil
        let next = index - 1 >= 0 ? all[index - 1].id : nil
        return (prev, next)
    }

    private func mapRow(_ row: SQLiteRow) -> DiaryEntry {
        DiaryEntry(
            id: row.int64(0),
            createdAt: row.int64(1),
            updatedAt: row.int64(2),
            audioPath: row.string(3),
            transcriptText: row.string(4),
            diaryText: row.string(5),
            durationMs: row.int64(6)
        )
    }
}
