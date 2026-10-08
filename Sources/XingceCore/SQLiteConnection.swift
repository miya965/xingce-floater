import Foundation
import SQLite3

enum SQLBinding {
    case null
    case int(Int64)
    case text(String)
}

struct SQLRow {
    var values: [String: SQLBinding]

    func text(_ key: String) -> String {
        guard case .text(let value) = values[key] else { return "" }
        return value
    }

    func optionalText(_ key: String) -> String? {
        guard case .text(let value) = values[key] else { return nil }
        return value
    }

    func int(_ key: String) -> Int {
        guard case .int(let value) = values[key] else { return 0 }
        return Int(value)
    }

    func optionalInt(_ key: String) -> Int? {
        guard case .int(let value) = values[key] else { return nil }
        return Int(value)
    }
}

enum SQLiteError: LocalizedError {
    case open(String)
    case statement(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let message), .statement(let message), .step(let message):
            return message
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteConnection {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.open(message)
        }
        db = handle
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if rc != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite 执行失败"
            sqlite3_free(errorPointer)
            throw SQLiteError.statement(message)
        }
    }

    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try work()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func run(_ sql: String, _ bindings: [SQLBinding] = []) throws {
        try withStatement(sql, bindings) { statement in
            let rc = sqlite3_step(statement)
            guard rc == SQLITE_DONE else {
                throw SQLiteError.step(currentError())
            }
        }
    }

    func query(_ sql: String, _ bindings: [SQLBinding] = []) throws -> [SQLRow] {
        try withStatement(sql, bindings) { statement in
            var rows: [SQLRow] = []
            while true {
                let rc = sqlite3_step(statement)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw SQLiteError.step(currentError()) }
                let columnCount = sqlite3_column_count(statement)
                var values: [String: SQLBinding] = [:]
                for index in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_NULL:
                        values[name] = .null
                    case SQLITE_INTEGER:
                        values[name] = .int(sqlite3_column_int64(statement, index))
                    case SQLITE_TEXT:
                        if let pointer = sqlite3_column_text(statement, index) {
                            values[name] = .text(String(cString: pointer))
                        } else {
                            values[name] = .null
                        }
                    default:
                        if let pointer = sqlite3_column_text(statement, index) {
                            values[name] = .text(String(cString: pointer))
                        } else {
                            values[name] = .null
                        }
                    }
                }
                rows.append(SQLRow(values: values))
            }
            return rows
        }
    }

    func intValue(_ sql: String, column: String, _ bindings: [SQLBinding] = []) throws -> Int {
        let rows = try query(sql, bindings)
        guard let row = rows.first else { return 0 }
        return row.int(column)
    }

    private func withStatement<T>(
        _ sql: String,
        _ bindings: [SQLBinding],
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw SQLiteError.statement(currentError())
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, bindings)
        return try body(statement)
    }

    private func bind(_ statement: OpaquePointer, _ bindings: [SQLBinding]) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch binding {
            case .null:
                rc = sqlite3_bind_null(statement, index)
            case .int(let value):
                rc = sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                rc = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            }
            if rc != SQLITE_OK {
                throw SQLiteError.statement(currentError())
            }
        }
    }

    private func currentError() -> String {
        guard let db else { return "SQLite 未打开" }
        return String(cString: sqlite3_errmsg(db))
    }
}
