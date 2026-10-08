import Foundation

enum QuestionDatabase {
    static func open(at path: String) throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try connection.execute(SchemaSQL.text)
        try connection.run(
            "INSERT OR IGNORE INTO schema_meta(key, value) VALUES (?, ?);",
            [.text("schema_version"), .text("1")]
        )
        return connection
    }
}

enum ISO8601 {
    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
