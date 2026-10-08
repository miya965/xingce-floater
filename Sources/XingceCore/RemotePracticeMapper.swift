import Foundation

/// 把本地刷题服务返回的题目转成小卡片能显示的结构。只在内存里使用，不写题库。
enum RemotePracticeCatalog {
    static let examSubject = "公务员·行测"
    static let modules = ["政治理论", "常识判断", "言语理解与表达", "数量关系", "判断推理", "资料分析"]
    static let batchSize = 8

    static func practiceURL(base: URL, module: String, count: Int) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("api/practice"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "subject", value: examSubject),
            URLQueryItem(name: "mock", value: "1"),
            URLQueryItem(name: "n", value: String(count)),
            URLQueryItem(name: "year", value: "all"),
            URLQueryItem(name: "custom", value: "1"),
        ]
        if module != "全部" {
            items.append(URLQueryItem(name: "group", value: module))
            items.append(URLQueryItem(name: "sub", value: "全部"))
        }
        parts?.queryItems = items
        return parts?.url
    }

    static func chaptersURL(base: URL) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("api/chapters"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "subject", value: examSubject),
            URLQueryItem(name: "mock", value: "1"),
        ]
        return parts?.url
    }

    static func statsURL(base: URL) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("api/records/stats"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "subject", value: examSubject)]
        return parts?.url
    }

    static func wrongURL(base: URL, count: Int) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("api/records/wrong"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "group", value: examSubject),
            URLQueryItem(name: "limit", value: String(count)),
        ]
        return parts?.url
    }

    static func questionURL(base: URL, id: String) -> URL? {
        var parts = URLComponents(url: base.appendingPathComponent("api/question"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "id", value: id)]
        return parts?.url
    }
}

struct RemotePracticeCard: Equatable {
    var question: Question
    var questionId: Int
    var paperId: Int?
    var chapter: String
    var typeCode: Int
    var examSubject: String
}

enum RemotePracticeMapper {
    private static let letters = Array("ABCDEFGH")

    static func cards(from data: Data, module: String) -> [RemotePracticeCard] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return list.compactMap { item in
            guard let object = item as? [String: Any] else { return nil }
            return card(from: object, module: module)
        }
    }

    static func card(from object: [String: Any], module: String) -> RemotePracticeCard? {
        let typeCode = intValue(object["type"]) ?? 0
        if typeCode >= 20 { return nil }
        let questionId = intValue(object["id"]) ?? intValue(object["questionId"]) ?? 0
        guard questionId > 0 else { return nil }

        let stem = plain(stringValue(object["content"])).isEmpty
            ? plain(stringValue(object["contentHtml"]))
            : plain(stringValue(object["content"]))
        var optionTexts = optionTexts(from: object["options"])
        if optionTexts.isEmpty, typeCode == 3 || typeCode == 5 {
            optionTexts = ["正确", "错误"]
        }
        let usableOptions = optionTexts.contains { !$0.isEmpty && $0 != "（图片）" }
        let stemText: String
        if stem.count >= 2 {
            stemText = stem
        } else if usableOptions {
            stemText = "这道题主要是图片，这里只显示能转成文字的部分。"
        } else {
            return nil
        }

        let answer = stringValue(object["answer"])
        let keys = answerKeys(answer: answer, answerIndex: intValue(object["answerIndex"]) ?? -1, optionCount: optionTexts.count)
        guard !keys.isEmpty else { return nil }

        let kind: QuestionKind
        if typeCode == 3 || typeCode == 5 {
            kind = .trueFalse
        } else if typeCode == 2 || isMultiple(answer) {
            kind = .multiple
        } else {
            kind = .single
        }
        let typeName: String
        switch kind {
        case .single: typeName = "单选"
        case .multiple: typeName = "多选"
        case .trueFalse: typeName = "判断"
        }
        let chapter = plain(stringValue(object["chapter"]))
        let shownSubject = module == "全部" ? (chapter.isEmpty ? "行测" : chapter) : module
        let explanation = plain(stringValue(object["analysis"]))
        let materialText = plain(stringValue(object["material"]))
        let material: SharedMaterial? = materialText.count >= 2
            ? SharedMaterial(id: "m-\(questionId)", title: "材料", body: materialText, images: [])
            : nil
        let options = optionTexts.prefix(letters.count).enumerated().map { index, text in
            QuestionOption(key: String(letters[index]), text: text.isEmpty ? "（图片）" : text)
        }
        let question = Question(
            id: "remote-\(questionId)",
            sourceQuestionID: String(questionId),
            source: "local-practice-service",
            subject: shownSubject,
            typeName: typeName,
            kind: kind,
            stem: stemText,
            options: options,
            answerKeys: keys,
            explanation: explanation.isEmpty ? "这道题没有文字解析。" : explanation,
            year: nil,
            province: "",
            paperName: "",
            licenseNote: "题目由本地刷题服务临时显示，不写入本程序题库。仅供个人学习。",
            material: material,
            images: []
        )
        return RemotePracticeCard(
            question: question,
            questionId: questionId,
            paperId: intValue(object["paperId"]),
            chapter: chapter,
            typeCode: typeCode,
            examSubject: RemotePracticeCatalog.examSubject
        )
    }

    static func indices(for keys: [String]) -> [Int] {
        keys.compactMap { key in
            guard let scalar = key.uppercased().unicodeScalars.first else { return nil }
            let index = Int(scalar.value) - Int(UnicodeScalar("A").value)
            guard letters.indices.contains(index) else { return nil }
            return index
        }
    }

    static func recordBody(card: RemotePracticeCard, selectedKeys: [String], correct: Bool) -> [String: Any] {
        [
            "questionId": card.questionId,
            "paperId": card.paperId ?? NSNull(),
            "subject": card.examSubject,
            "chapter": card.chapter,
            "type": card.typeCode,
            "selected": indices(for: selectedKeys),
            "correct": correct,
            "costMs": 0,
        ]
    }

    static func readyCount(from chaptersData: Data, module: String) -> Int {
        guard let groups = (try? JSONSerialization.jsonObject(with: chaptersData)) as? [Any] else { return 0 }
        let rows: [(name: String, total: Int)] = groups.compactMap { item in
            guard let object = item as? [String: Any] else { return nil }
            return (stringValue(object["group"]), intValue(object["total"]) ?? 0)
        }
        if module == "全部" {
            return rows.reduce(0) { $0 + $1.total }
        }
        return rows.first { $0.name == module }?.total ?? 0
    }

    static func studyStats(from data: Data, readyCount: Int) -> StudyStats {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let answered = intValue(object["total"]) ?? 0
        let correct = intValue(object["correct"]) ?? 0
        let wrong = intValue(object["wrong"]) ?? 0
        return StudyStats(
            readyCount: readyCount,
            needsReviewCount: 0,
            answeredCount: answered,
            correctCount: correct,
            wrongCount: wrong,
            attemptCount: answered
        )
    }

    static func wrongIDs(from data: Data) -> [String] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object["list"] as? [Any] else { return [] }
        var seen = Set<String>()
        var ids: [String] = []
        for item in list {
            guard let row = item as? [String: Any] else { continue }
            let id = stringValue(row["questionId"])
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return ids
    }

    private static func answerKeys(answer: String, answerIndex: Int, optionCount: Int) -> [String] {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let indexes: [Int]
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            indexes = values.compactMap { intValue($0) }
        } else if trimmed.contains(",") {
            indexes = trimmed.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        } else if trimmed.count == 1, let letter = trimmed.uppercased().first, letters.contains(letter) {
            return [String(letter)]
        } else if let index = Int(trimmed) {
            indexes = [index]
        } else if answerIndex >= 0 {
            indexes = [answerIndex]
        } else {
            indexes = []
        }
        return indexes.compactMap { index in
            guard optionCount > 0, index >= 0, index < optionCount, letters.indices.contains(index) else { return nil }
            return String(letters[index])
        }
    }

    private static func isMultiple(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") { return true }
        return trimmed.contains(",") && trimmed.allSatisfy { $0.isNumber || $0 == "," || $0.isWhitespace }
    }

    private static func optionTexts(from value: Any?) -> [String] {
        let list: [Any]
        if let array = value as? [Any] {
            list = array
        } else if let text = value as? String,
                  let data = text.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            list = array
        } else {
            return []
        }
        return list.map { item in
            if let text = item as? String { return plain(text) }
            if let object = item as? [String: Any] {
                let text = stringValue(object["text"])
                if !text.isEmpty { return plain(text) }
                return plain(stringValue(object["content"]))
            }
            return ""
        }
    }

    static func plain(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "(?is)<script.*?>.*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style.*?>.*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private static func stringValue(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
