import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    let repository: SQLiteQuestionRepository
    let session: PracticeSession
    @Published var chrome: WindowChrome = .mini
    @Published var subject: String = "政治理论"
    @Published var mode: PracticeMode = .unseenFirst
    @Published var subjects: [String] = RemotePracticeCatalog.modules
    @Published var stats: StudyStats
    @Published var statusMessage: String = ""
    @Published var isLoading = false
    @Published private(set) var sessionID: String = ""
    private var sessionCancellable: AnyCancellable?
    private var practice: RemotePracticeClient?
    private var cards: [String: RemotePracticeCard] = [:]
    private var loadToken = 0

    init(repository: SQLiteQuestionRepository) {
        self.repository = repository
        session = PracticeSession(questions: [])
        stats = StudyStats(readyCount: 0, needsReviewCount: 0, answeredCount: 0, correctCount: 0, wrongCount: 0, attemptCount: 0)
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if let stored = UserDefaults.standard.string(forKey: "practice.subject"),
           stored == "全部" || RemotePracticeCatalog.modules.contains(stored) {
            subject = stored
        }
        if let raw = UserDefaults.standard.string(forKey: "practice.mode"), let stored = PracticeMode(rawValue: raw) {
            mode = stored
        }
        reload()
    }

    func reload() {
        UserDefaults.standard.set(subject, forKey: "practice.subject")
        UserDefaults.standard.set(mode.rawValue, forKey: "practice.mode")
        loadToken += 1
        let token = loadToken
        let module = subject
        let mode = self.mode
        isLoading = true
        statusMessage = ""
        session.replace(with: [])
        cards = [:]
        LocalPracticeService.shared.prepare { [weak self] url in
            guard let self, token == self.loadToken else { return }
            guard let url else {
                self.isLoading = false
                self.statusMessage = "本地刷题服务没有启动。"
                return
            }
            let client = RemotePracticeClient(base: url)
            self.practice = client
            client.load(module: module, mode: mode, excluding: []) { [weak self] result in
                guard let self, token == self.loadToken else { return }
                self.apply(result, token: token, appending: false)
            }
        }
    }

    func loadMore() {
        guard !isLoading, let practice else { return }
        let token = loadToken
        let module = subject
        let mode = self.mode
        let excluding = Set(session.questions.map(\.id))
        isLoading = true
        practice.load(module: module, mode: mode, excluding: excluding) { [weak self] result in
            guard let self, token == self.loadToken else { return }
            let before = self.session.questions.count
            self.apply(result, token: token, appending: true)
            if self.session.questions.count > before {
                self.session.goToNext()
                self.statusMessage = ""
            } else if self.statusMessage.isEmpty {
                self.statusMessage = "没有更多题目了。"
            }
        }
    }

    func select(_ key: String) {
        session.select(key)
    }

    func submit() {
        guard let result = session.submit() else { return }
        guard let card = cards[result.question.id], let practice else {
            statusMessage = "这题的对错没能记到本地服务。"
            return
        }
        practice.record(card: card, selectedKeys: result.keys, correct: result.correct) { [weak self] ok in
            guard let self else { return }
            if ok {
                practice.refreshStats(module: self.subject) { stats in
                    self.stats = stats
                }
            } else {
                self.statusMessage = "这题的对错没能记到本地服务。"
            }
        }
    }

    func importJSON(at url: URL) {
        do {
            let report = try repository.importJSON(at: url, sourceAssetRoot: url.deletingLastPathComponent())
            statusMessage = report.summaryText
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func chooseJSONAndImport() {
        let panel = NSOpenPanel()
        panel.prompt = "导入"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importJSON(at: url)
    }

    private func apply(_ result: Result<RemoteLoad, Error>, token: Int, appending: Bool) {
        guard token == loadToken else { return }
        isLoading = false
        switch result {
        case .failure:
            if !appending {
                session.replace(with: [])
            }
            statusMessage = "本地服务暂时没有返回题目。"
        case .success(let load):
            stats = load.stats
            for card in load.cards {
                cards[card.question.id] = card
            }
            if appending {
                session.append(load.cards.map(\.question))
            } else {
                session.replace(with: load.cards.map(\.question))
                if load.cards.isEmpty {
                    statusMessage = mode == .wrongOnly ? "错题本是空的。" : "这一筛选下没有可刷题目。"
                }
            }
        }
    }
}

enum WindowChrome {
    case mini
    case card
}
