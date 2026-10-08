import Foundation

/// 查找用户本机自行准备的刷题服务目录和 Node。不内置任何题库路径。
enum PracticeLocator {
    static func practiceRoot(
        environment: [String: String],
        currentDirectory: URL,
        supportDirectory: URL,
        fileExists: (String) -> Bool
    ) -> URL? {
        if let configured = serverRoot(environment["XINGCE_PRACTICE_ROOT"], fileExists: fileExists) {
            return configured
        }
        var directory = currentDirectory.standardizedFileURL
        for _ in 0..<8 {
            if let configured = rootFile(directory.appendingPathComponent("practice-root.local"), fileExists: fileExists) {
                return configured
            }
            let sibling = directory.appendingPathComponent("kaogong-shuati", isDirectory: true)
            if fileExists(sibling.appendingPathComponent("server.mjs").path) {
                return sibling
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return rootFile(supportDirectory.appendingPathComponent("practice-root.txt"), fileExists: fileExists)
    }

    static func nodeExecutable(
        environment: [String: String],
        supportDirectory: URL,
        fileExists: (String) -> Bool,
        pathLookup: () -> String?
    ) -> URL? {
        if let configured = executable(environment["XINGCE_NODE"], fileExists: fileExists) {
            return configured
        }
        if let configured = executable(pathLookup(), fileExists: fileExists) {
            return configured
        }
        return executable(
            supportDirectory.appendingPathComponent("node-runtime/bin/node").path,
            fileExists: fileExists
        )
    }

    private static func serverRoot(_ raw: String?, fileExists: (String) -> Bool) -> URL? {
        guard let path = firstPath(raw) else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard fileExists(root.appendingPathComponent("server.mjs").path) else { return nil }
        return root
    }

    private static func rootFile(_ url: URL, fileExists: (String) -> Bool) -> URL? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return serverRoot(text, fileExists: fileExists)
    }

    private static func executable(_ raw: String?, fileExists: (String) -> Bool) -> URL? {
        guard let path = firstPath(raw), fileExists(path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func firstPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            return text
        }
        return nil
    }
}
