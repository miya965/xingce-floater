import Foundation

enum QuestionKind: String, Codable, Equatable {
    case single
    case multiple
    case trueFalse = "true_false"
}

enum ReviewStatus: String, Equatable {
    case ready
    case needsReview = "needs_review"
}

enum PracticeMode: String, Codable, CaseIterable, Equatable {
    case sequential
    case random
    case unseenFirst
    case wrongOnly

    var title: String {
        switch self {
        case .sequential: return "顺序"
        case .random: return "随机"
        case .unseenFirst: return "未做优先"
        case .wrongOnly: return "错题重练"
        }
    }
}

struct QuestionOption: Equatable, Identifiable {
    var key: String
    var text: String
    var id: String { key }
}

struct StoredImage: Equatable, Identifiable {
    var id: String
    var relativePath: String
    var mediaType: String
}

struct SharedMaterial: Equatable, Identifiable {
    var id: String
    var title: String
    var body: String
    var images: [StoredImage]
}

struct Question: Equatable, Identifiable {
    var id: String
    var sourceQuestionID: String?
    var source: String
    var subject: String
    var typeName: String
    var kind: QuestionKind
    var stem: String
    var options: [QuestionOption]
    var answerKeys: [String]
    var explanation: String
    var year: Int?
    var province: String
    var paperName: String
    var licenseNote: String
    var material: SharedMaterial?
    var images: [StoredImage]

    var kindTitle: String {
        switch kind {
        case .single: return "单选题"
        case .multiple: return "多选题"
        case .trueFalse: return "判断题"
        }
    }

    func isCorrect(selected keys: [String]) -> Bool {
        Set(keys) == Set(answerKeys) && !answerKeys.isEmpty
    }
}

struct StudyStats: Equatable {
    var readyCount: Int
    var needsReviewCount: Int
    var answeredCount: Int
    var correctCount: Int
    var wrongCount: Int
    var attemptCount: Int

    var accuracyText: String {
        guard answeredCount > 0 else { return "尚无成绩" }
        let percent = Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        return "\(correctCount)/\(answeredCount) · \(percent)%"
    }
}

struct PracticeSessionSummary: Equatable, Identifiable {
    var id: String
    var mode: String
    var subject: String
    var startedAt: String
    var submittedCount: Int
    var correctCount: Int
}

struct ImportIssue: Equatable, Codable {
    var sourceQuestionID: String?
    var stemPreview: String
    var reasons: [String]
}

struct ImportReport: Equatable, Codable {
    var inserted: Int
    var updated: Int
    var duplicateSource: Int
    var duplicateStem: Int
    var needsReview: Int
    var ready: Int
    var rolledBack: Bool
    var issues: [ImportIssue]

    var summaryText: String {
        if rolledBack {
            return "导入已回滚，题库未改动"
        }
        return "新增 \(inserted)，更新 \(updated)，来源重复 \(duplicateSource)，题干重复 \(duplicateStem)，待复核 \(needsReview)，可刷 \(ready)"
    }
}

enum ImportFailure: LocalizedError, Equatable {
    case unreadable(String)
    case invalidJSON(String)
    case permissionDenied(String)
    case unsupportedFormat(String)
    case injectedFailure
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let message): return message
        case .invalidJSON(let message): return "JSON 无法解析：\(message)"
        case .permissionDenied(let message): return message
        case .unsupportedFormat(let message): return message
        case .injectedFailure: return "导入在写入后被中断"
        case .sqlite(let message): return message
        }
    }
}
