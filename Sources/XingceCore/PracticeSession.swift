import Foundation
import Combine

final class PracticeSession: ObservableObject {
    @Published private(set) var questions: [Question]
    @Published private(set) var index: Int
    @Published private(set) var drafts: [String: [String]]
    @Published private(set) var locked: Set<String>

    init(questions: [Question]) {
        self.questions = questions
        self.index = 0
        self.drafts = [:]
        self.locked = []
    }

    var current: Question? {
        guard questions.indices.contains(index) else { return nil }
        return questions[index]
    }

    var progressText: String {
        guard !questions.isEmpty else { return "0/0" }
        return "\(index + 1)/\(questions.count)"
    }

    func replace(with questions: [Question]) {
        self.questions = questions
        index = 0
        drafts = [:]
        locked = []
    }

    func select(_ key: String) {
        guard let question = current, !locked.contains(question.id) else { return }
        guard question.options.contains(where: { $0.key == key }) else { return }
        var keys = drafts[question.id] ?? []
        switch question.kind {
        case .single, .trueFalse:
            keys = [key]
        case .multiple:
            if let existing = keys.firstIndex(of: key) {
                keys.remove(at: existing)
            } else {
                keys.append(key)
            }
        }
        var copy = drafts
        copy[question.id] = keys
        drafts = copy
    }

    func selectedKeys(for questionID: String) -> [String] {
        drafts[questionID] ?? []
    }

    func submit() -> (question: Question, keys: [String], correct: Bool)? {
        guard let question = current, !locked.contains(question.id) else { return nil }
        let keys = drafts[question.id] ?? []
        guard !keys.isEmpty else { return nil }
        var lockedCopy = locked
        lockedCopy.insert(question.id)
        locked = lockedCopy
        return (question, keys, question.isCorrect(selected: keys))
    }

    func goToPrevious() {
        guard index > 0 else { return }
        index -= 1
    }

    func goToNext() {
        guard index + 1 < questions.count else { return }
        index += 1
    }

    func append(_ more: [Question]) {
        let existing = Set(questions.map(\.id))
        let fresh = more.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        questions.append(contentsOf: fresh)
    }
}
