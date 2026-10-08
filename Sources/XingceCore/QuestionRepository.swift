import Foundation

protocol QuestionRepository {
    func fetchPracticeQuestions(subject: String?, mode: PracticeMode) throws -> [Question]
    func subjects() throws -> [String]
    func stats(subject: String?) throws -> StudyStats
    func recentSessions(limit: Int) throws -> [PracticeSessionSummary]
    func startSession(mode: PracticeMode, subject: String?) throws -> String
    func recordAttempt(
        questionID: String,
        sessionID: String,
        selectedKeys: [String],
        isCorrect: Bool
    ) throws
    func importJSON(at url: URL, sourceAssetRoot: URL) throws -> ImportReport
}

final class SQLiteQuestionRepository: QuestionRepository {
    let assetsRoot: URL
    private let connection: SQLiteConnection
    private let importer = QuestionImporter()

    init(databasePath: String, assetsRoot: URL) throws {
        try FileManager.default.createDirectory(at: assetsRoot, withIntermediateDirectories: true)
        let directory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.assetsRoot = assetsRoot
        connection = try QuestionDatabase.open(at: databasePath)
    }

    func importJSON(at url: URL, sourceAssetRoot: URL) throws -> ImportReport {
        try importer.importFile(
            jsonURL: url,
            sourceAssetRoot: sourceAssetRoot,
            destinationAssets: assetsRoot,
            connection: connection
        )
    }

    func importJSONForTesting(
        at url: URL,
        sourceAssetRoot: URL,
        failAfterReadyInserts: Int?
    ) throws -> ImportReport {
        var testing = QuestionImporter()
        testing.failAfterReadyInserts = failAfterReadyInserts
        return try testing.importFile(
            jsonURL: url,
            sourceAssetRoot: sourceAssetRoot,
            destinationAssets: assetsRoot,
            connection: connection
        )
    }

    func subjects() throws -> [String] {
        let rows = try connection.query(
            """
            SELECT DISTINCT subject FROM questions
            WHERE review_status = 'ready'
            ORDER BY subject;
            """
        )
        let present = rows.map { $0.text("subject") }
        let preferred = ["政治理论", "常识判断", "言语理解", "数量关系", "判断推理", "资料分析"]
        var ordered = preferred.filter { present.contains($0) }
        for subject in present where !ordered.contains(subject) {
            ordered.append(subject)
        }
        return ordered
    }

    func fetchPracticeQuestions(subject: String?, mode: PracticeMode) throws -> [Question] {
        var sql = """
        SELECT q.question_id, q.source_question_id, q.source, q.subject, q.type_name, q.question_type,
               q.stem, q.explanation, q.year, q.province, q.paper_name, q.license_note, q.material_id
        FROM questions q
        WHERE q.review_status = 'ready'
        """
        var bindings: [SQLBinding] = []
        if let subject, subject != "全部", !subject.isEmpty {
            sql += " AND q.subject = ?"
            bindings.append(.text(subject))
        }
        switch mode {
        case .sequential:
            sql += " ORDER BY q.sort_order, q.question_id"
        case .random:
            sql += " ORDER BY RANDOM()"
        case .unseenFirst:
            sql += """
             ORDER BY CASE WHEN EXISTS (
               SELECT 1 FROM attempts a WHERE a.question_id = q.question_id
             ) THEN 1 ELSE 0 END, q.sort_order, q.question_id
            """
        case .wrongOnly:
            sql += """
             AND q.question_id IN (
               SELECT a.question_id FROM attempts a
               JOIN (
                 SELECT question_id, MAX(rowid) AS rowid FROM attempts GROUP BY question_id
               ) latest ON latest.rowid = a.rowid
               WHERE a.is_correct = 0
             )
             ORDER BY q.sort_order, q.question_id
            """
        }
        let rows = try connection.query(sql, bindings)
        return try rows.map { try hydrate($0) }
    }

    func stats(subject: String?) throws -> StudyStats {
        let subjectSQL = (subject == nil || subject == "全部") ? "" : " AND q.subject = ?"
        let binding: [SQLBinding] = (subject == nil || subject == "全部") ? [] : [.text(subject!)]
        let ready = try connection.intValue(
            "SELECT COUNT(*) AS n FROM questions q WHERE q.review_status = 'ready'\(subjectSQL);",
            column: "n",
            binding
        )
        let reviewSQL = subjectSQL.replacingOccurrences(of: "q.subject", with: "subject")
        let needsReview = try connection.intValue(
            "SELECT COUNT(*) AS n FROM questions WHERE review_status = 'needs_review'\(reviewSQL);",
            column: "n",
            binding
        )
        let latest = """
        SELECT a.question_id, a.is_correct
        FROM attempts a
        JOIN (
          SELECT question_id, MAX(rowid) AS rowid FROM attempts GROUP BY question_id
        ) latest ON latest.rowid = a.rowid
        JOIN questions q ON q.question_id = a.question_id
        WHERE q.review_status = 'ready'\(subjectSQL)
        """
        let latestRows = try connection.query(latest, binding)
        let answered = latestRows.count
        let correct = latestRows.filter { $0.int("is_correct") == 1 }.count
        let attemptCount = try connection.intValue(
            """
            SELECT COUNT(*) AS n FROM attempts a
            JOIN questions q ON q.question_id = a.question_id
            WHERE q.review_status = 'ready'\(subjectSQL);
            """,
            column: "n",
            binding
        )
        return StudyStats(
            readyCount: ready,
            needsReviewCount: needsReview,
            answeredCount: answered,
            correctCount: correct,
            wrongCount: answered - correct,
            attemptCount: attemptCount
        )
    }

    func recentSessions(limit: Int) throws -> [PracticeSessionSummary] {
        let rows = try connection.query(
            """
            SELECT session_id, mode, subject, started_at, submitted_count, correct_count
            FROM practice_sessions
            ORDER BY started_at DESC
            LIMIT ?;
            """,
            [.int(Int64(limit))]
        )
        return rows.map {
            PracticeSessionSummary(
                id: $0.text("session_id"),
                mode: $0.text("mode"),
                subject: $0.text("subject"),
                startedAt: $0.text("started_at"),
                submittedCount: $0.int("submitted_count"),
                correctCount: $0.int("correct_count")
            )
        }
    }

    func startSession(mode: PracticeMode, subject: String?) throws -> String {
        let sessionID = "session." + UUID().uuidString.lowercased()
        try connection.run(
            """
            INSERT INTO practice_sessions(session_id, mode, subject, started_at, submitted_count, correct_count)
            VALUES (?, ?, ?, ?, 0, 0);
            """,
            [.text(sessionID), .text(mode.rawValue), .text(subject ?? ""), .text(ISO8601.now())]
        )
        return sessionID
    }

    func recordAttempt(
        questionID: String,
        sessionID: String,
        selectedKeys: [String],
        isCorrect: Bool
    ) throws {
        let attemptID = "attempt." + UUID().uuidString.lowercased()
        try connection.transaction {
            try connection.run(
                """
                INSERT INTO attempts(attempt_id, question_id, session_id, is_correct, answered_at)
                VALUES (?, ?, ?, ?, ?);
                """,
                [
                    .text(attemptID),
                    .text(questionID),
                    sessionID.isEmpty ? .null : .text(sessionID),
                    .int(isCorrect ? 1 : 0),
                    .text(ISO8601.now())
                ]
            )
            for key in selectedKeys {
                try connection.run(
                    "INSERT INTO attempt_choices(attempt_id, option_key) VALUES (?, ?);",
                    [.text(attemptID), .text(key)]
                )
            }
            if !sessionID.isEmpty {
                try connection.run(
                    """
                    UPDATE practice_sessions
                    SET submitted_count = submitted_count + 1,
                        correct_count = correct_count + ?
                    WHERE session_id = ?;
                    """,
                    [.int(isCorrect ? 1 : 0), .text(sessionID)]
                )
            }
        }
    }

    func questionCount() throws -> Int {
        try connection.intValue("SELECT COUNT(*) AS n FROM questions;", column: "n")
    }

    func attemptCount(questionID: String) throws -> Int {
        try connection.intValue(
            "SELECT COUNT(*) AS n FROM attempts WHERE question_id = ?;",
            column: "n",
            [.text(questionID)]
        )
    }

    func questionID(source: String, sourceQuestionID: String) throws -> String? {
        try connection.query(
            "SELECT question_id FROM questions WHERE source = ? AND source_question_id = ?;",
            [.text(source), .text(sourceQuestionID)]
        ).first?.text("question_id")
    }

    func reviewReasons(sourceQuestionID: String) throws -> [String] {
        let rows = try connection.query(
            "SELECT review_reasons FROM questions WHERE source_question_id = ?;",
            [.text(sourceQuestionID)]
        )
        guard let text = rows.first?.text("review_reasons"),
              let data = text.data(using: .utf8),
              let values = try JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return values
    }

    func imagePaths(questionID: String) throws -> [String] {
        try connection.query(
            "SELECT relative_path FROM question_images WHERE question_id = ? ORDER BY sort_order;",
            [.text(questionID)]
        ).map { $0.text("relative_path") }
    }

    func materialImagePaths(materialID: String) throws -> [String] {
        try connection.query(
            "SELECT relative_path FROM material_images WHERE material_id = ? ORDER BY sort_order;",
            [.text(materialID)]
        ).map { $0.text("relative_path") }
    }

    func importBatchCount() throws -> Int {
        try connection.intValue("SELECT COUNT(*) AS n FROM import_batches;", column: "n")
    }

    private func hydrate(_ row: SQLRow) throws -> Question {
        let questionID = row.text("question_id")
        let optionRows = try connection.query(
            "SELECT option_key, option_text FROM options WHERE question_id = ? ORDER BY sort_order;",
            [.text(questionID)]
        )
        let answerRows = try connection.query(
            "SELECT option_key FROM answer_keys WHERE question_id = ? ORDER BY sort_order;",
            [.text(questionID)]
        )
        let imageRows = try connection.query(
            "SELECT image_id, relative_path, media_type FROM question_images WHERE question_id = ? ORDER BY sort_order;",
            [.text(questionID)]
        )
        var material: SharedMaterial?
        if let materialID = row.optionalText("material_id"), !materialID.isEmpty {
            let materialRows = try connection.query(
                "SELECT material_id, title, body FROM materials WHERE material_id = ?;",
                [.text(materialID)]
            )
            if let materialRow = materialRows.first {
                let images = try connection.query(
                    "SELECT image_id, relative_path, media_type FROM material_images WHERE material_id = ? ORDER BY sort_order;",
                    [.text(materialID)]
                ).map {
                    StoredImage(id: $0.text("image_id"), relativePath: $0.text("relative_path"), mediaType: $0.text("media_type"))
                }
                material = SharedMaterial(
                    id: materialRow.text("material_id"),
                    title: materialRow.text("title"),
                    body: materialRow.text("body"),
                    images: images
                )
            }
        }
        let kind = QuestionKind(rawValue: row.text("question_type")) ?? .single
        return Question(
            id: questionID,
            sourceQuestionID: row.optionalText("source_question_id"),
            source: row.text("source"),
            subject: row.text("subject"),
            typeName: row.text("type_name"),
            kind: kind,
            stem: row.text("stem"),
            options: optionRows.map { QuestionOption(key: $0.text("option_key"), text: $0.text("option_text")) },
            answerKeys: answerRows.map { $0.text("option_key") },
            explanation: row.text("explanation"),
            year: row.optionalInt("year"),
            province: row.text("province"),
            paperName: row.text("paper_name"),
            licenseNote: row.text("license_note"),
            material: material,
            images: imageRows.map {
                StoredImage(id: $0.text("image_id"), relativePath: $0.text("relative_path"), mediaType: $0.text("media_type"))
            }
        )
    }
}
