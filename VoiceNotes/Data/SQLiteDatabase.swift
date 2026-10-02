import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let m): return "数据库打开失败：\(m)"
        case .prepare(let m): return "数据库语句错误：\(m)"
        case .step(let m): return "数据库执行失败：\(m)"
        }
    }
}

/// Minimal SQLite wrapper. Not thread-safe on its own; used from a single actor.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError.open(message)
        }
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw SQLiteError.step(message)
        }
    }

    /// Runs a statement that returns no rows, binding the given values.
    @discardableResult
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(lastErrorMessage)
        }
        return Int(sqlite3_changes(handle))
    }

    /// Runs a query, mapping every row with the given closure.
    func query<T>(_ sql: String, _ bindings: [SQLiteValue] = [], _ map: (SQLiteRow) -> T) throws -> [T] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                results.append(map(SQLiteRow(statement: statement)))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step(lastErrorMessage)
            }
        }
        return results
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(lastErrorMessage)
        }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null:
                sqlite3_bind_null(statement, position)
            case .integer(let v):
                sqlite3_bind_int64(statement, position, v)
            case .real(let v):
                sqlite3_bind_double(statement, position, v)
            case .text(let v):
                sqlite3_bind_text(statement, position, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                v.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(statement, position, raw.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
                }
            }
        }
        return statement
    }
}

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    static func optionalText(_ value: String?) -> SQLiteValue {
        value.map { .text($0) } ?? .null
    }
}

struct SQLiteRow {
    let statement: OpaquePointer?

    func int64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }

    func string(_ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
}
