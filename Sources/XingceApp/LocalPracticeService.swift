import Foundation

/// 按原仓库的方式在本机启动刷题服务。不读取、不复制题库内容。
final class LocalPracticeService {
    static let shared = LocalPracticeService()
    static let port = 3927

    var pageURL: URL { URL(string: "http://127.0.0.1:\(Self.port)/")! }

    private var process: Process?
    private var weStarted = false
    private let queue = DispatchQueue(label: "local-practice-service")

    func prepare(_ done: @escaping (URL?) -> Void) {
        queue.async {
            self.startIfNeeded()
            let ready = self.waitUntilReady()
            DispatchQueue.main.async {
                done(ready ? self.pageURL : nil)
            }
        }
    }

    func stopIfWeStarted() {
        queue.sync {
            guard weStarted, let process, process.isRunning else { return }
            process.terminate()
            weStarted = false
        }
    }

    private func startIfNeeded() {
        if probe() { return }
        let support = supportDirectory()
        guard let repoRoot = PracticeLocator.practiceRoot(
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            supportDirectory: support,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        ), let node = nodeExecutable(support: support) else {
            fputs("本地刷题服务未启动：请设置 XINGCE_PRACTICE_ROOT，或先在本机启动该服务。\n", stderr)
            return
        }
        let server = repoRoot.appendingPathComponent("server.mjs")
        let process = Process()
        process.executableURL = node
        process.arguments = [server.path, String(Self.port)]
        process.currentDirectoryURL = repoRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
            weStarted = true
        } catch {
            fputs("本地刷题服务启动失败：\(error.localizedDescription)\n", stderr)
        }
    }

    private func waitUntilReady() -> Bool {
        for _ in 0..<40 {
            if probe() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func probe() -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.6
        let session = URLSession(configuration: config)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = session.dataTask(with: pageURL) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                ok = true
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 1)
        return ok
    }

    private func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XingceFloater", isDirectory: true)
    }

    private func nodeExecutable(support: URL) -> URL? {
        PracticeLocator.nodeExecutable(
            environment: ProcessInfo.processInfo.environment,
            supportDirectory: support,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            pathLookup: { Self.nodeOnPath() }
        )
    }

    private static func nodeOnPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
