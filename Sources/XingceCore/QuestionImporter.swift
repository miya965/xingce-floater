import Foundation
import CryptoKit

private struct BankFile: Decodable {
    var format: String
    var license: LicenseDTO
    var papers: [PaperDTO]
    var materials: [MaterialDTO]
    var questions: [QuestionDTO]
}

private struct LicenseDTO: Decodable {
    var source: String
    var note: String
    var allows_import: Bool
}

private struct PaperDTO: Decodable {
    var paper_id: String
    var source: String?
    var year: Int?
    var province: String?
    var exam_level: String?
    var paper_name: String
    var license_note: String?
}

private struct MaterialDTO: Decodable {
    var material_id: String
    var paper_id: String?
    var source_material_id: String?
    var title: String?
    var body: String
    var images: [ImageDTO]?
}

private struct ImageDTO: Decodable {
    var relative_path: String
    var media_type: String?
    var role: String?
}

private struct OptionDTO: Decodable {
    var key: String
    var text: String
}

private struct QuestionDTO: Decodable {
    var source_question_id: String?
    var paper_id: String?
    var material_id: String?
    var subject: String
    var type_name: String
    var question_type: String
    var stem: String
    var options: [OptionDTO]
    var answer: FlexibleAnswer?
    var explanation: String?
    var images: [ImageDTO]?
    var image_missing: Bool?
    var year: Int?
    var province: String?
    var paper_name: String?
    var license_note: String?
}

private struct FlexibleAnswer: Decodable {
    var keys: [String]
    var invalid: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            keys = []
            invalid = true
            return
        }
        if let values = try? container.decode([String].self) {
            keys = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            invalid = false
            return
        }
        if let text = try? container.decode(String.self) {
            keys = AnswerParser.keys(from: text)
            invalid = false
            return
        }
        keys = []
        invalid = true
    }
}

enum AnswerParser {
    static func keys(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed == "正确" || trimmed == "错误" || trimmed == "对" || trimmed == "错" {
            return [trimmed]
        }
        if trimmed.contains(",") || trimmed.contains("，") || trimmed.contains("、") || trimmed.contains(" ") {
            return trimmed
                .replacingOccurrences(of: "，", with: ",")
                .replacingOccurrences(of: "、", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let letters = trimmed.uppercased()
        if letters.unicodeScalars.allSatisfy({ ("A"..."H").contains(Character($0)) }) {
            return letters.map { String($0) }
        }
        return [trimmed]
    }
}

private struct PreparedImage {
    var imageID: String
    var relativePath: String
    var mediaType: String
    var missing: Bool
}

struct QuestionImporter {
    var failAfterReadyInserts: Int?

    func importFile(
        jsonURL: URL,
        sourceAssetRoot: URL,
        destinationAssets: URL,
        connection: SQLiteConnection
    ) throws -> ImportReport {
        let data: Data
        do {
            data = try Data(contentsOf: jsonURL)
        } catch {
            throw ImportFailure.unreadable("无法读取 \(jsonURL.lastPathComponent)")
        }
        let bank: BankFile
        do {
            bank = try JSONDecoder().decode(BankFile.self, from: data)
        } catch {
            throw ImportFailure.invalidJSON(error.localizedDescription)
        }
        if bank.format != "xingce-bank-v1" {
            throw ImportFailure.unsupportedFormat("不支持的题库格式：\(bank.format)")
        }
        let licenseNote = bank.license.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bank.license.allows_import || licenseNote.isEmpty || bank.license.source.isEmpty {
            throw ImportFailure.permissionDenied("该文件没有明确允许导入。未写入题库。")
        }

        var report = ImportReport(
            inserted: 0,
            updated: 0,
            duplicateSource: 0,
            duplicateStem: 0,
            needsReview: 0,
            ready: 0,
            rolledBack: false,
            issues: []
        )
        var readyIDs = Set<String>()
        var readyInserts = 0

        do {
            try connection.transaction {
                let now = ISO8601.now()
                let batchID = "batch." + UUID().uuidString.lowercased()
                var papers = try upsertPapers(bank, license: bank.license, now: now, connection: connection)
                let materialState = try upsertMaterials(
                    bank.materials,
                    papers: papers,
                    sourceAssetRoot: sourceAssetRoot,
                    destinationAssets: destinationAssets,
                    connection: connection
                )
                papers = try loadPapers(connection)

                for (index, dto) in bank.questions.enumerated() {
                    let outcome = try importQuestion(
                        dto,
                        index: index,
                        license: bank.license,
                        papers: papers,
                        materialState: materialState,
                        sourceAssetRoot: sourceAssetRoot,
                        destinationAssets: destinationAssets,
                        now: now,
                        connection: connection
                    )
                    switch outcome.kind {
                    case .inserted:
                        report.inserted += 1
                    case .updated:
                        report.updated += 1
                        report.duplicateSource += 1
                    case .skippedStem:
                        report.duplicateStem += 1
                        report.issues.append(outcome.issue)
                    }
                    if outcome.kind != .skippedStem {
                        if outcome.reviewStatus == .needsReview {
                            report.needsReview += 1
                            report.issues.append(outcome.issue)
                            if let questionID = outcome.questionID {
                                readyIDs.remove(questionID)
                            }
                        } else if let questionID = outcome.questionID {
                            readyIDs.insert(questionID)
                            if outcome.kind == .inserted {
                                readyInserts += 1
                                if let limit = failAfterReadyInserts, readyInserts >= limit {
                                    throw ImportFailure.injectedFailure
                                }
                            }
                        }
                    }
                }
                report.ready = readyIDs.count

                let encoded = try JSONEncoder().encode(report)
                let reportText = String(decoding: encoded, as: UTF8.self)
                try connection.run(
                    """
                    INSERT INTO import_batches(
                      batch_id, source_file, started_at, finished_at, status,
                      inserted_count, updated_count, duplicate_source_count, duplicate_stem_count,
                      needs_review_count, ready_count, report_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    [
                        .text(batchID),
                        .text(jsonURL.path),
                        .text(now),
                        .text(ISO8601.now()),
                        .text("committed"),
                        .int(Int64(report.inserted)),
                        .int(Int64(report.updated)),
                        .int(Int64(report.duplicateSource)),
                        .int(Int64(report.duplicateStem)),
                        .int(Int64(report.needsReview)),
                        .int(Int64(report.ready)),
                        .text(reportText)
                    ]
                )
            }
            return report
        } catch {
            report.rolledBack = true
            report.inserted = 0
            report.updated = 0
            report.duplicateSource = 0
            report.duplicateStem = 0
            report.needsReview = 0
            report.ready = 0
            if let failure = error as? ImportFailure {
                throw failure
            }
            throw ImportFailure.sqlite(error.localizedDescription)
        }
    }
}

private enum QuestionWriteKind {
    case inserted
    case updated
    case skippedStem
}

private struct QuestionOutcome {
    var questionID: String?
    var kind: QuestionWriteKind
    var reviewStatus: ReviewStatus
    var issue: ImportIssue
}

private struct PaperRecord {
    var id: String
    var source: String
    var year: Int?
    var province: String
    var paperName: String
    var licenseNote: String
}

private struct MaterialState {
    var ids: Set<String>
    var missingImageIDs: Set<String>
    var emptyBodyIDs: Set<String>
}

private func upsertPapers(
    _ bank: BankFile,
    license: LicenseDTO,
    now: String,
    connection: SQLiteConnection
) throws -> [String: PaperRecord] {
    for paper in bank.papers {
        let source = (paper.source?.isEmpty == false ? paper.source! : license.source)
        let note = (paper.license_note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? paper.license_note!
            : license.note
        try connection.run(
            """
            INSERT INTO papers(paper_id, source, year, province, exam_level, paper_name, license_note, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(paper_id) DO UPDATE SET
              source = excluded.source,
              year = excluded.year,
              province = excluded.province,
              exam_level = excluded.exam_level,
              paper_name = excluded.paper_name,
              license_note = excluded.license_note;
            """,
            [
                .text(paper.paper_id),
                .text(source),
                paper.year.map { .int(Int64($0)) } ?? .null,
                .text(paper.province ?? ""),
                .text(paper.exam_level ?? ""),
                .text(paper.paper_name),
                .text(note),
                .text(now)
            ]
        )
    }
    return try loadPapers(connection)
}

private func loadPapers(_ connection: SQLiteConnection) throws -> [String: PaperRecord] {
    let rows = try connection.query(
        "SELECT paper_id, source, year, province, paper_name, license_note FROM papers;"
    )
    var papers: [String: PaperRecord] = [:]
    for row in rows {
        let id = row.text("paper_id")
        papers[id] = PaperRecord(
            id: id,
            source: row.text("source"),
            year: row.optionalInt("year"),
            province: row.text("province"),
            paperName: row.text("paper_name"),
            licenseNote: row.text("license_note")
        )
    }
    return papers
}

private func upsertMaterials(
    _ materials: [MaterialDTO],
    papers: [String: PaperRecord],
    sourceAssetRoot: URL,
    destinationAssets: URL,
    connection: SQLiteConnection
) throws -> MaterialState {
    var ids = Set<String>()
    var missingImages = Set<String>()
    var emptyBodies = Set<String>()
    for (index, material) in materials.enumerated() {
        ids.insert(material.material_id)
        let body = material.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { emptyBodies.insert(material.material_id) }
        let paperID = material.paper_id.flatMap { papers[$0] == nil ? nil : $0 }
        try connection.run(
            """
            INSERT INTO materials(material_id, paper_id, source_material_id, title, body, sort_order)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(material_id) DO UPDATE SET
              paper_id = excluded.paper_id,
              source_material_id = excluded.source_material_id,
              title = excluded.title,
              body = excluded.body,
              sort_order = excluded.sort_order;
            """,
            [
                .text(material.material_id),
                paperID.map { .text($0) } ?? .null,
                material.source_material_id.map { .text($0) } ?? .null,
                .text(material.title ?? ""),
                .text(material.body),
                .int(Int64(index))
            ]
        )
        try connection.run(
            "DELETE FROM material_images WHERE material_id = ?;",
            [.text(material.material_id)]
        )
        let prepared = try prepareImages(
            material.images ?? [],
            owner: material.material_id,
            sourceAssetRoot: sourceAssetRoot,
            destinationAssets: destinationAssets
        )
        if prepared.contains(where: { $0.missing }) {
            missingImages.insert(material.material_id)
        }
        for (imageIndex, image) in prepared.enumerated() where !image.missing {
            try connection.run(
                """
                INSERT INTO material_images(image_id, material_id, relative_path, media_type, sort_order)
                VALUES (?, ?, ?, ?, ?);
                """,
                [
                    .text(image.imageID),
                    .text(material.material_id),
                    .text(image.relativePath),
                    .text(image.mediaType),
                    .int(Int64(imageIndex))
                ]
            )
        }
    }
    let existing = try connection.query("SELECT material_id FROM materials;")
    for row in existing {
        ids.insert(row.text("material_id"))
    }
    return MaterialState(ids: ids, missingImageIDs: missingImages, emptyBodyIDs: emptyBodies)
}

private func importQuestion(
    _ dto: QuestionDTO,
    index: Int,
    license: LicenseDTO,
    papers: [String: PaperRecord],
    materialState: MaterialState,
    sourceAssetRoot: URL,
    destinationAssets: URL,
    now: String,
    connection: SQLiteConnection
) throws -> QuestionOutcome {
    let stemHash = StemNormalizer.hash(dto.stem)
    let sourceQuestionID = dto.source_question_id?.trimmingCharacters(in: .whitespacesAndNewlines)
    let paper = dto.paper_id.flatMap { papers[$0] }
    let source = paper?.source ?? license.source
    var reasons: [String] = []

    if paper == nil, let paperID = dto.paper_id, !paperID.isEmpty {
        reasons.append("missing_paper")
    }
    let kind = QuestionKind(rawValue: dto.question_type)
    if kind == nil {
        reasons.append("unknown_question_type")
    }
    let optionKeys = dto.options.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
    if Set(optionKeys).count != optionKeys.count || optionKeys.contains("") {
        reasons.append("options_invalid")
    }
    if let kind {
        switch kind {
        case .single, .trueFalse:
            if dto.options.count < 2 { reasons.append("options_invalid") }
        case .multiple:
            if dto.options.count < 2 { reasons.append("options_invalid") }
        }
    }

    var answerKeys = dto.answer?.keys ?? []
    if dto.answer == nil || dto.answer?.invalid == true || answerKeys.isEmpty {
        reasons.append("missing_answer")
        answerKeys = []
    } else {
        answerKeys = answerKeys.map { mapAnswerKey($0, options: dto.options) }
        let known = Set(optionKeys)
        if answerKeys.contains(where: { !known.contains($0) }) || Set(answerKeys).count != answerKeys.count {
            reasons.append("answer_format")
        } else if let kind {
            switch kind {
            case .single, .trueFalse:
                if answerKeys.count != 1 { reasons.append("answer_format") }
            case .multiple:
                if answerKeys.count < 2 { reasons.append("answer_format") }
            }
        }
    }

    let explanation = dto.explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if isAbnormalExplanation(explanation) {
        reasons.append("explanation_abnormal")
    }

    var materialID = dto.material_id?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let materialID, !materialID.isEmpty {
        if !materialState.ids.contains(materialID) || materialState.emptyBodyIDs.contains(materialID) {
            reasons.append("missing_material")
        }
        if materialState.missingImageIDs.contains(materialID) {
            reasons.append("missing_image")
        }
    } else {
        materialID = nil
    }

    let preparedImages = try prepareImages(
        dto.images ?? [],
        owner: sourceQuestionID ?? stemHash,
        sourceAssetRoot: sourceAssetRoot,
        destinationAssets: destinationAssets
    )
    if dto.image_missing == true || preparedImages.contains(where: { $0.missing }) {
        reasons.append("missing_image")
    }

    var uniqueReasons: [String] = []
    for reason in reasons where !uniqueReasons.contains(reason) {
        uniqueReasons.append(reason)
    }
    let status: ReviewStatus = uniqueReasons.isEmpty ? .ready : .needsReview
    let reasonJSON = try jsonArray(uniqueReasons)
    let preview = String(dto.stem.prefix(24))
    let issue = ImportIssue(sourceQuestionID: sourceQuestionID, stemPreview: preview, reasons: uniqueReasons)

    if let sourceQuestionID, !sourceQuestionID.isEmpty {
        let existing = try connection.query(
            "SELECT question_id FROM questions WHERE source = ? AND source_question_id = ?;",
            [.text(source), .text(sourceQuestionID)]
        )
        if let questionID = existing.first?.text("question_id"), !questionID.isEmpty {
            try writeQuestion(
                questionID: questionID,
                isNew: false,
                sourceQuestionID: sourceQuestionID,
                source: source,
                paper: paper,
                materialID: materialState.ids.contains(materialID ?? "") ? materialID : nil,
                dto: dto,
                stemHash: stemHash,
                answerKeys: status == .ready || !answerKeys.isEmpty ? answerKeys : [],
                explanation: explanation,
                status: status,
                reasons: reasonJSON,
                licenseNote: dto.license_note ?? paper?.licenseNote ?? license.note,
                images: preparedImages,
                index: index,
                now: now,
                connection: connection
            )
            return QuestionOutcome(questionID: questionID, kind: .updated, reviewStatus: status, issue: issue)
        }
    }

    let stemMatches = try connection.query(
        "SELECT question_id FROM questions WHERE stem_hash = ? LIMIT 1;",
        [.text(stemHash)]
    )
    if stemMatches.first != nil {
        var stemIssue = issue
        stemIssue.reasons = ["duplicate_stem"]
        return QuestionOutcome(questionID: nil, kind: .skippedStem, reviewStatus: .needsReview, issue: stemIssue)
    }

    let questionID = StemNormalizer.internalQuestionID(
        source: source,
        sourceQuestionID: sourceQuestionID,
        stemHash: stemHash
    )
    try writeQuestion(
        questionID: questionID,
        isNew: true,
        sourceQuestionID: sourceQuestionID,
        source: source,
        paper: paper,
        materialID: materialState.ids.contains(materialID ?? "") ? materialID : nil,
        dto: dto,
        stemHash: stemHash,
        answerKeys: answerKeys,
        explanation: explanation,
        status: status,
        reasons: reasonJSON,
        licenseNote: dto.license_note ?? paper?.licenseNote ?? license.note,
        images: preparedImages,
        index: index,
        now: now,
        connection: connection
    )
    return QuestionOutcome(questionID: questionID, kind: .inserted, reviewStatus: status, issue: issue)
}

private func writeQuestion(
    questionID: String,
    isNew: Bool,
    sourceQuestionID: String?,
    source: String,
    paper: PaperRecord?,
    materialID: String?,
    dto: QuestionDTO,
    stemHash: String,
    answerKeys: [String],
    explanation: String,
    status: ReviewStatus,
    reasons: String,
    licenseNote: String,
    images: [PreparedImage],
    index: Int,
    now: String,
    connection: SQLiteConnection
) throws {
    let year = dto.year ?? paper?.year
    let province = dto.province ?? paper?.province ?? ""
    let paperName = dto.paper_name ?? paper?.paperName ?? ""
    if isNew {
        try connection.run(
            """
            INSERT INTO questions(
              question_id, source_question_id, source, paper_id, material_id, subject, type_name,
              question_type, stem, stem_hash, explanation, year, province, paper_name, license_note,
              review_status, review_reasons, sort_order, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            questionBindings(
                questionID: questionID,
                sourceQuestionID: sourceQuestionID,
                source: source,
                paper: paper,
                materialID: materialID,
                dto: dto,
                stemHash: stemHash,
                explanation: explanation,
                year: year,
                province: province,
                paperName: paperName,
                licenseNote: licenseNote,
                status: status,
                reasons: reasons,
                index: index,
                createdAt: now,
                updatedAt: now
            )
        )
    } else {
        try connection.run(
            """
            UPDATE questions SET
              source_question_id = ?, source = ?, paper_id = ?, material_id = ?, subject = ?,
              type_name = ?, question_type = ?, stem = ?, stem_hash = ?, explanation = ?,
              year = ?, province = ?, paper_name = ?, license_note = ?, review_status = ?,
              review_reasons = ?, sort_order = ?, updated_at = ?
            WHERE question_id = ?;
            """,
            [
                sourceQuestionID.map { .text($0) } ?? .null,
                .text(source),
                paper.map { .text($0.id) } ?? .null,
                materialID.map { .text($0) } ?? .null,
                .text(dto.subject),
                .text(dto.type_name),
                .text(dto.question_type),
                .text(dto.stem),
                .text(stemHash),
                .text(explanation),
                year.map { .int(Int64($0)) } ?? .null,
                .text(province),
                .text(paperName),
                .text(licenseNote),
                .text(status.rawValue),
                .text(reasons),
                .int(Int64(index)),
                .text(now),
                .text(questionID)
            ]
        )
        try connection.run("DELETE FROM options WHERE question_id = ?;", [.text(questionID)])
        try connection.run("DELETE FROM answer_keys WHERE question_id = ?;", [.text(questionID)])
        try connection.run("DELETE FROM question_images WHERE question_id = ?;", [.text(questionID)])
    }

    for (optionIndex, option) in dto.options.enumerated() {
        try connection.run(
            "INSERT INTO options(question_id, option_key, option_text, sort_order) VALUES (?, ?, ?, ?);",
            [.text(questionID), .text(option.key), .text(option.text), .int(Int64(optionIndex))]
        )
    }
    let validOptionKeys = Set(dto.options.map(\.key))
    for (answerIndex, key) in answerKeys.enumerated() where validOptionKeys.contains(key) {
        try connection.run(
            "INSERT OR IGNORE INTO answer_keys(question_id, option_key, sort_order) VALUES (?, ?, ?);",
            [.text(questionID), .text(key), .int(Int64(answerIndex))]
        )
    }
    for (imageIndex, image) in images.enumerated() where !image.missing {
        try connection.run(
            """
            INSERT INTO question_images(image_id, question_id, role, relative_path, media_type, sort_order)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(image.imageID),
                .text(questionID),
                .text("stem"),
                .text(image.relativePath),
                .text(image.mediaType),
                .int(Int64(imageIndex))
            ]
        )
    }
}

private func questionBindings(
    questionID: String,
    sourceQuestionID: String?,
    source: String,
    paper: PaperRecord?,
    materialID: String?,
    dto: QuestionDTO,
    stemHash: String,
    explanation: String,
    year: Int?,
    province: String,
    paperName: String,
    licenseNote: String,
    status: ReviewStatus,
    reasons: String,
    index: Int,
    createdAt: String,
    updatedAt: String
) -> [SQLBinding] {
    [
        .text(questionID),
        sourceQuestionID.map { .text($0) } ?? .null,
        .text(source),
        paper.map { .text($0.id) } ?? .null,
        materialID.map { .text($0) } ?? .null,
        .text(dto.subject),
        .text(dto.type_name),
        .text(dto.question_type),
        .text(dto.stem),
        .text(stemHash),
        .text(explanation),
        year.map { .int(Int64($0)) } ?? .null,
        .text(province),
        .text(paperName),
        .text(licenseNote),
        .text(status.rawValue),
        .text(reasons),
        .int(Int64(index)),
        .text(createdAt),
        .text(updatedAt)
    ]
}

private func mapAnswerKey(_ raw: String, options: [OptionDTO]) -> String {
    if options.contains(where: { $0.key == raw }) { return raw }
    let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if folded == "正确" || folded == "对" {
        if let match = options.first(where: { $0.text == "正确" || $0.key == "T" || $0.key == "A" && $0.text.contains("正确") }) {
            return match.key
        }
    }
    if folded == "错误" || folded == "错" {
        if let match = options.first(where: { $0.text == "错误" || $0.key == "F" || $0.text.contains("错误") }) {
            return match.key
        }
    }
    let upper = folded.uppercased()
    if options.contains(where: { $0.key == upper }) { return upper }
    return folded
}

private func isAbnormalExplanation(_ explanation: String) -> Bool {
    let folded = explanation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let placeholders: Set<String> = ["", "暂无", "略", "无", "无解析", "todo", "n/a", "null", "待补充", "解析异常"]
    if placeholders.contains(folded) { return true }
    return folded.count < 8
}

private func prepareImages(
    _ images: [ImageDTO],
    owner: String,
    sourceAssetRoot: URL,
    destinationAssets: URL
) throws -> [PreparedImage] {
    var prepared: [PreparedImage] = []
    for (index, image) in images.enumerated() {
        let relative = image.relative_path
        let sourceURL = sourceAssetRoot.appendingPathComponent(relative)
        let exists = FileManager.default.fileExists(atPath: sourceURL.path)
        if !exists {
            prepared.append(PreparedImage(
                imageID: "missing.\(StemNormalizer.stableToken(owner)).\(index)",
                relativePath: "unresolved/" + relative,
                mediaType: image.media_type ?? "",
                missing: true
            ))
            continue
        }
        let data = try Data(contentsOf: sourceURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let storedRelative = "imported/\(digest).\(ext)"
        let destination = destinationAssets.appendingPathComponent(storedRelative)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination)
        prepared.append(PreparedImage(
            imageID: "img.\(StemNormalizer.stableToken(owner)).\(index)",
            relativePath: storedRelative,
            mediaType: image.media_type ?? mime(for: ext),
            missing: false
        ))
    }
    return prepared
}

private func mime(for ext: String) -> String {
    switch ext.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    default: return ""
    }
}

private func jsonArray(_ values: [String]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: values, options: [])
    return String(decoding: data, as: UTF8.self)
}
