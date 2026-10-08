import AppKit
import Foundation

@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.contains("--import") {
            CLIImport.run()
        }
        let app = NSApplication.shared
        app.delegate = AppDelegate.shared
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    private var windowManager: FloatingWindowManager?
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        do {
            let paths = AppPaths.standard()
            let repository = try SQLiteQuestionRepository(databasePath: paths.database.path, assetsRoot: paths.assets)
            if try repository.questionCount() == 0, let bundled = Bundle.main.resourceURL {
                let sample = bundled.appendingPathComponent("sample-bank.json")
                if FileManager.default.fileExists(atPath: sample.path) {
                    _ = try repository.importJSON(at: sample, sourceAssetRoot: bundled)
                }
            }
            let model = AppModel(repository: repository)
            self.model = model
            let manager = FloatingWindowManager(model: model)
            windowManager = manager
            LocalPracticeService.shared.prepare { _ in }
            manager.show()
        } catch {
            let alert = NSAlert()
            alert.messageText = "行测刷题器无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.persistPosition()
        LocalPracticeService.shared.stopIfWeStarted()
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出行测刷题器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

struct AppPaths {
    var database: URL
    var assets: URL

    static func standard() -> AppPaths {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XingceFloater", isDirectory: true)
        return AppPaths(
            database: root.appendingPathComponent("bank.sqlite"),
            assets: root.appendingPathComponent("assets", isDirectory: true)
        )
    }
}

enum CLIImport {
    static func run() -> Never {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let jsonPath = value(after: "--import") else {
            fputs("用法: XingceFloater --import 题库.json [--assets 资源目录] [--db 数据库路径]\n", stderr)
            exit(2)
        }
        let jsonURL = URL(fileURLWithPath: jsonPath)
        let assetsSource = URL(fileURLWithPath: value(after: "--assets") ?? jsonURL.deletingLastPathComponent().path)
        let paths = AppPaths.standard()
        let database = URL(fileURLWithPath: value(after: "--db") ?? paths.database.path)
        let destination = database.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        do {
            let repository = try SQLiteQuestionRepository(databasePath: database.path, assetsRoot: destination)
            let report = try repository.importJSON(at: jsonURL, sourceAssetRoot: assetsSource)
            print(report.summaryText)
            for issue in report.issues {
                let name = issue.sourceQuestionID ?? "无来源ID"
                print("\(name)：\(issue.reasons.joined(separator: ","))")
            }
            exit(EXIT_SUCCESS)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
