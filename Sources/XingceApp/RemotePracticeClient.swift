import Foundation

enum RemotePracticeError: Error {
    case unavailable
    case http(Int)
    case timeout
    case unreadable
}

/// 向本机刷题服务取题、记成绩。题目只留在内存里。
final class RemotePracticeClient {
    let base: URL
    private let queue = DispatchQueue(label: "remote-practice", qos: .userInitiated)

    init(base: URL) {
        self.base = base
    }

    func load(module: String, mode: PracticeMode, excluding: Set<String>, completion: @escaping (Result<RemoteLoad, Error>) -> Void) {
        queue.async {
            let result = Result { try self.loadSync(module: module, mode: mode, excluding: excluding) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func record(card: RemotePracticeCard, selectedKeys: [String], correct: Bool, completion: @escaping (Bool) -> Void) {
        queue.async {
            let ok = (try? self.postRecord(card: card, selectedKeys: selectedKeys, correct: correct)) != nil
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func refreshStats(module: String, completion: @escaping (StudyStats) -> Void) {
        queue.async {
            let ready = (try? self.readyCount(module: module)) ?? 0
            let stats = (try? self.stats(readyCount: ready)) ?? StudyStats(
                readyCount: ready, needsReviewCount: 0, answeredCount: 0, correctCount: 0, wrongCount: 0, attemptCount: 0
            )
            DispatchQueue.main.async { completion(stats) }
        }
    }

    private func loadSync(module: String, mode: PracticeMode, excluding: Set<String>) throws -> RemoteLoad {
        let ready = (try? readyCount(module: module)) ?? 0
        let stats = (try? self.stats(readyCount: ready)) ?? StudyStats(
            readyCount: ready, needsReviewCount: 0, answeredCount: 0, correctCount: 0, wrongCount: 0, attemptCount: 0
        )
        let cards: [RemotePracticeCard]
        if mode == .wrongOnly {
            cards = try wrongCards(module: module, excluding: excluding)
        } else {
            cards = try practiceCards(module: module, excluding: excluding)
        }
        return RemoteLoad(cards: cards, stats: stats)
    }

    private func practiceCards(module: String, excluding: Set<String>) throws -> [RemotePracticeCard] {
        guard let url = RemotePracticeCatalog.practiceURL(base: base, module: module, count: RemotePracticeCatalog.batchSize) else {
            throw RemotePracticeError.unavailable
        }
        let data = try fetch(url)
        return RemotePracticeMapper.cards(from: data, module: module).filter { !excluding.contains($0.question.id) }
    }

    private func wrongCards(module: String, excluding: Set<String>) throws -> [RemotePracticeCard] {
        guard let url = RemotePracticeCatalog.wrongURL(base: base, count: RemotePracticeCatalog.batchSize) else {
            throw RemotePracticeError.unavailable
        }
        let ids = RemotePracticeMapper.wrongIDs(from: try fetch(url))
        var cards: [RemotePracticeCard] = []
        for id in ids where !excluding.contains("remote-\(id)") {
            guard let url = RemotePracticeCatalog.questionURL(base: base, id: id) else { continue }
            let data = try fetch(url)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let card = RemotePracticeMapper.card(from: object, module: module) else { continue }
            cards.append(card)
        }
        return cards
    }

    private func readyCount(module: String) throws -> Int {
        guard let url = RemotePracticeCatalog.chaptersURL(base: base) else { throw RemotePracticeError.unavailable }
        return RemotePracticeMapper.readyCount(from: try fetch(url), module: module)
    }

    private func stats(readyCount: Int) throws -> StudyStats {
        guard let url = RemotePracticeCatalog.statsURL(base: base) else { throw RemotePracticeError.unavailable }
        return RemotePracticeMapper.studyStats(from: try fetch(url), readyCount: readyCount)
    }

    private func postRecord(card: RemotePracticeCard, selectedKeys: [String], correct: Bool) throws {
        guard let url = URL(string: "api/records", relativeTo: base)?.absoluteURL else {
            throw RemotePracticeError.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: RemotePracticeMapper.recordBody(
            card: card, selectedKeys: selectedKeys, correct: correct
        ))
        _ = try fetch(request)
    }

    private func fetch(_ url: URL) throws -> Data {
        try fetch(URLRequest(url: url))
    }

    private func fetch(_ request: URLRequest) throws -> Data {
        var request = request
        request.timeoutInterval = 20
        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        var failure: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                failure = error
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failure = RemotePracticeError.http(http.statusCode)
            } else {
                payload = data
            }
            semaphore.signal()
        }.resume()
        if semaphore.wait(timeout: .now() + 25) == .timedOut {
            throw RemotePracticeError.timeout
        }
        if let failure { throw failure }
        guard let payload else { throw RemotePracticeError.unreadable }
        return payload
    }
}

struct RemoteLoad {
    var cards: [RemotePracticeCard]
    var stats: StudyStats
}
