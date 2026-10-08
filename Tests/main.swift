import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
var failures: [String] = []

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failures.append(message)
        fputs("FAIL \(message)\n", stderr)
    } else {
        print("ok \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        failures.append("\(message)：实际 \(actual)，期望 \(expected)")
        fputs("FAIL \(message)：实际 \(actual)，期望 \(expected)\n", stderr)
    } else {
        print("ok \(message)")
    }
}

func temporaryRepository() throws -> (SQLiteQuestionRepository, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xingce-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let database = directory.appendingPathComponent("bank.sqlite").path
    let assets = directory.appendingPathComponent("assets", isDirectory: true)
    let repository = try SQLiteQuestionRepository(databasePath: database, assetsRoot: assets)
    return (repository, directory)
}

let fixture = root.appendingPathComponent("Fixtures/sample-bank.json")
let schemaFile = root.appendingPathComponent("Database/schema.sql")
let fixtureRoot = root.appendingPathComponent("Fixtures")

do {
    let schema = try String(contentsOf: schemaFile, encoding: .utf8)
    expectEqual(SchemaSQL.text, schema, "内嵌结构与 schema.sql 一致")
    expect(StemNormalizer.hash("我国第一大岛是哪一个？") == StemNormalizer.hash("我国第一大岛是哪一个？  \n"), "题干空白规范化后哈希相同")
    expect(AnswerParser.keys(from: "正确") == ["正确"], "判断题答案字符串可解析")
    expect(AnswerParser.keys(from: "ABD") == ["A", "B", "D"], "多选答案字符串可拆开")

    let session = PracticeSession(questions: [
        Question(
            id: "local",
            sourceQuestionID: nil,
            source: "test",
            subject: "常识判断",
            typeName: "多选",
            kind: .multiple,
            stem: "测试",
            options: [
                QuestionOption(key: "A", text: "1"),
                QuestionOption(key: "B", text: "2"),
                QuestionOption(key: "C", text: "3"),
                QuestionOption(key: "D", text: "4")
            ],
            answerKeys: ["A", "B", "D"],
            explanation: "测试解析足够长。",
            year: nil,
            province: "",
            paperName: "",
            licenseNote: "test",
            material: nil,
            images: []
        )
    ])
    session.select("A")
    session.select("C")
    session.select("C")
    session.select("B")
    session.select("D")
    let graded = session.submit()
    expect(graded?.correct == true, "多选题集合相同即判对")

    let (repository, directory) = try temporaryRepository()
    defer { try? FileManager.default.removeItem(at: directory) }
    let report = try repository.importJSON(at: fixture, sourceAssetRoot: fixtureRoot)
    expectEqual(report.inserted, 15, "首次导入新增条数")
    expectEqual(report.updated, 1, "同来源 ID 更新次数")
    expectEqual(report.duplicateSource, 1, "来源 ID 重复次数")
    expectEqual(report.duplicateStem, 1, "题干哈希重复次数")
    expectEqual(report.needsReview, 5, "待复核条数")
    expectEqual(report.ready, 10, "可刷题目数")
    expect(report.rolledBack == false, "正常导入不回滚")

    let practice = try repository.fetchPracticeQuestions(subject: nil, mode: .sequential)
    expectEqual(practice.count, 10, "刷题队列只含可刷题")
    expect(practice.allSatisfy { question in
        Set(question.answerKeys).isSubset(of: Set(question.options.map(\.key))) && !question.answerKeys.isEmpty
    }, "可刷题的答案都能对应到选项")
    expect(practice.contains { $0.sourceQuestionID == "sample-missing-image" } == false, "缺图题不进刷题队列")
    expect(practice.contains { $0.sourceQuestionID == "sample-bad-answer" } == false, "错误答案不进刷题队列")
    expect(practice.contains { $0.sourceQuestionID == "sample-no-answer" } == false, "缺答案题不进刷题队列")
    expect(practice.contains { $0.sourceQuestionID == "sample-bad-explain" } == false, "异常解析不进刷题队列")
    expect(practice.contains { $0.sourceQuestionID == "sample-missing-material" } == false, "缺材料题不进刷题队列")
    expect(try repository.questionID(source: "original-sample", sourceQuestionID: "sample-island-stemcopy") == nil, "题干重复项没有另建题目")

    let islandID = try repository.questionID(source: "original-sample", sourceQuestionID: "sample-island")
    expect(islandID != nil, "稳定 question_id 已生成")
    let island = practice.first { $0.sourceQuestionID == "sample-island" }
    expectEqual(island?.answerKeys, ["C"], "重复导入没有改掉原题答案")
    expectEqual(island?.paperName, "原创示例·省考卷", "保留原始卷名")
    expectEqual(island?.province, "示例省", "保留省份")
    expectEqual(island?.year, 2026, "保留年份")
    expect(island?.licenseNote.contains("原创示例") == true, "保留授权说明")

    expectEqual(try repository.reviewReasons(sourceQuestionID: "sample-missing-image"), ["missing_image"], "缺图原因")
    expectEqual(try repository.reviewReasons(sourceQuestionID: "sample-bad-answer"), ["answer_format"], "答案格式原因")
    expectEqual(try repository.reviewReasons(sourceQuestionID: "sample-no-answer"), ["missing_answer"], "缺答案原因")
    expectEqual(try repository.reviewReasons(sourceQuestionID: "sample-bad-explain"), ["explanation_abnormal"], "解析异常原因")
    expect(try repository.reviewReasons(sourceQuestionID: "sample-missing-material").contains("missing_material"), "缺材料原因")

    let imageQuestion = practice.first { $0.sourceQuestionID == "sample-image" }
    expectEqual(imageQuestion?.images.count, 1, "含图题保存了一张图")
    if let relative = imageQuestion?.images.first?.relativePath, let imageQuestion {
        let file = repository.assetsRoot.appendingPathComponent(relative)
        expect(FileManager.default.fileExists(atPath: file.path), "含图题图片已复制到本地资源目录")
        expect(relative.hasPrefix("imported/"), "图片使用导入后的相对路径")
        let paths = try repository.imagePaths(questionID: imageQuestion.id)
        expectEqual(paths, [relative], "图片表与题目关联")
    } else {
        expect(false, "没有找到含图题")
    }

    let materialQuestions = practice.filter { $0.material?.id == "mat-shop" }
    expectEqual(materialQuestions.count, 2, "两道资料分析题共享同一材料")
    expect(materialQuestions.allSatisfy { $0.material?.body.contains("200") == true && $0.material?.body.contains("300") == true }, "材料正文完整")
    expectEqual(materialQuestions.first?.material?.images.count, 1, "材料图已入库")
    if let materialImage = materialQuestions.first?.material?.images.first?.relativePath {
        let file = repository.assetsRoot.appendingPathComponent(materialImage)
        expect(FileManager.default.fileExists(atPath: file.path), "材料图片文件存在")
        expectEqual(try repository.materialImagePaths(materialID: "mat-shop"), [materialImage], "材料图片表关联完整")
    }

    let quantitative = try repository.fetchPracticeQuestions(subject: "数量关系", mode: .sequential)
    expectEqual(quantitative.map(\.sourceQuestionID), ["sample-math"], "按科目筛选")
    let national = practice.filter { $0.paperName == "原创示例·国考卷" }.compactMap(\.sourceQuestionID).sorted()
    expectEqual(national, ["sample-politics", "sample-tf"], "国考卷题目可按卷名区分")

    let math = practice.first { $0.sourceQuestionID == "sample-math" }!
    let sessionID = try repository.startSession(mode: .wrongOnly, subject: "数量关系")
    try repository.recordAttempt(questionID: math.id, sessionID: sessionID, selectedKeys: ["A"], isCorrect: false)
    let wrong = try repository.fetchPracticeQuestions(subject: nil, mode: .wrongOnly)
    expectEqual(wrong.map(\.id), [math.id], "错题重练只返回最近一次做错的题")
    let unseen = try repository.fetchPracticeQuestions(subject: nil, mode: .unseenFirst)
    expect(unseen.first?.id != math.id, "未做题排在已做题前面")
    expect(unseen.last?.id == math.id, "已做题排到末尾")
    try repository.recordAttempt(questionID: math.id, sessionID: sessionID, selectedKeys: ["B"], isCorrect: true)
    let wrongAfter = try repository.fetchPracticeQuestions(subject: nil, mode: .wrongOnly)
    expect(wrongAfter.isEmpty, "最近一次答对后退出错题队列")
    let stats = try repository.stats(subject: nil)
    expectEqual(stats.answeredCount, 1, "按题目统计已做数")
    expectEqual(stats.correctCount, 1, "最近一次答对计入正确")
    expectEqual(stats.attemptCount, 2, "历史作答次数保留")
    let sessions = try repository.recentSessions(limit: 5)
    expectEqual(sessions.first?.submittedCount, 2, "场次成绩累计提交数")
    expectEqual(sessions.first?.correctCount, 1, "场次成绩累计正确数")

    let random = try repository.fetchPracticeQuestions(subject: nil, mode: .random)
    expectEqual(Set(random.map(\.id)), Set(practice.map(\.id)), "随机抽题不超出可刷题")

    let preservedID = math.id
    let preservedAttempts = try repository.attemptCount(questionID: preservedID)
    let second = try repository.importJSON(at: fixture, sourceAssetRoot: fixtureRoot)
    expectEqual(second.inserted, 0, "再次导入不新增")
    expectEqual(second.updated, 16, "再次导入按来源 ID 更新")
    expectEqual(second.duplicateStem, 1, "再次导入仍识别题干重复")
    expectEqual(try repository.questionID(source: "original-sample", sourceQuestionID: "sample-math"), preservedID, "重新导入后 question_id 不变")
    expectEqual(try repository.attemptCount(questionID: preservedID), preservedAttempts, "重新导入不丢失作答记录")
    expectEqual(try repository.fetchPracticeQuestions(subject: nil, mode: .sequential).count, 10, "重新导入后可刷题数量不变")

    let (rollbackRepo, rollbackDir) = try temporaryRepository()
    defer { try? FileManager.default.removeItem(at: rollbackDir) }
    do {
        _ = try rollbackRepo.importJSONForTesting(at: fixture, sourceAssetRoot: fixtureRoot, failAfterReadyInserts: 1)
        expect(false, "中断导入应该抛错")
    } catch let error as ImportFailure {
        expect(error == .injectedFailure, "中断导入返回注入失败")
    }
    expectEqual(try rollbackRepo.questionCount(), 0, "失败导入回滚后题目为空")
    expectEqual(try rollbackRepo.importBatchCount(), 0, "失败导入回滚后没有批次记录")

    let denied = rollbackDir.appendingPathComponent("denied.json")
    try """
    {"format":"xingce-bank-v1","license":{"source":"third-party","note":"未授权","allows_import":false},"papers":[],"materials":[],"questions":[]}
    """.write(to: denied, atomically: true, encoding: .utf8)
    do {
        _ = try rollbackRepo.importJSON(at: denied, sourceAssetRoot: fixtureRoot)
        expect(false, "未授权文件应该被拒绝")
    } catch let error as ImportFailure {
        expect(error == .permissionDenied("该文件没有明确允许导入。未写入题库。"), "未授权文件被拒绝")
    }
    expectEqual(try rollbackRepo.questionCount(), 0, "拒绝未授权文件后题库仍为空")

    let broken = rollbackDir.appendingPathComponent("broken.json")
    try "{".write(to: broken, atomically: true, encoding: .utf8)
    do {
        _ = try rollbackRepo.importJSON(at: broken, sourceAssetRoot: fixtureRoot)
        expect(false, "损坏 JSON 应该失败")
    } catch is ImportFailure {
        expect(true, "损坏 JSON 被拒绝")
    }
    expectEqual(try rollbackRepo.questionCount(), 0, "损坏 JSON 没有写入")
} catch {
    failures.append("测试中断：\(error)")
    fputs("FAIL 测试中断：\(error)\n", stderr)
}

let base = URL(string: "http://127.0.0.1:3927/")!
if let practiceURL = RemotePracticeCatalog.practiceURL(base: base, module: "政治理论", count: 8) {
    let query = practiceURL.query ?? ""
    expect(query.contains("mock=1"), "练习请求只取模拟题标记")
    expect(query.contains("group="), "练习请求带模块")
    expect(!query.contains("题干"), "练习请求里没有题干")
}
let sample = """
[{"id":7,"paperId":3,"chapter":"示例章节","type":1,"content":"下面哪一项是示例？","options":["甲","乙","丙","丁"],"answer":"1","answerIndex":1,"analysis":"示例解析，选乙。"}]
""".data(using: .utf8)!
let sampleCards = RemotePracticeMapper.cards(from: sample, module: "政治理论")
expectEqual(sampleCards.count, 1, "示例单选可以转成卡片")
if let card = sampleCards.first {
    expectEqual(card.question.answerKeys, ["B"], "答案下标 1 对应 B")
    expectEqual(card.question.subject, "政治理论", "卡片科目用当前模块")
    expect(card.question.stem.contains("示例"), "卡片保留示例题干")
    let body = RemotePracticeMapper.recordBody(card: card, selectedKeys: ["B"], correct: true)
    expectEqual(body["questionId"] as? Int ?? 0, 7, "记分只带题目编号")
    expectEqual(body["selected"] as? [Int] ?? [], [1], "选项 B 记成下标 1")
    expect(body["content"] == nil && body["analysis"] == nil, "记分请求不带题干和解析")
}

let multi = """
[{"id":8,"type":2,"content":"示例多选，请选择两项。","options":["甲","乙","丙"],"answer":"[0,2]","answerIndex":-1,"analysis":""}]
""".data(using: .utf8)!
let multiCards = RemotePracticeMapper.cards(from: multi, module: "全部")
expectEqual(multiCards.first?.question.kind, .multiple, "数组答案识别为多选")
expectEqual(multiCards.first?.question.answerKeys ?? [], ["A", "C"], "多选答案是 A 和 C")
expectEqual(multiCards.first?.question.explanation ?? "", "这道题没有文字解析。", "没有解析时给出一句说明")

let judge = """
[{"id":9,"type":3,"content":"示例判断：1 加 1 等于 2。","options":[],"answer":"0","answerIndex":0,"analysis":"正确。"}]
""".data(using: .utf8)!
let judgeCards = RemotePracticeMapper.cards(from: judge, module: "政治理论")
expectEqual(judgeCards.first?.question.kind, .trueFalse, "判断题补上对错选项")
expectEqual(judgeCards.first?.question.options.map(\.text) ?? [], ["正确", "错误"], "判断题选项是正确和错误")

let picture = """
[{"id":10,"type":1,"content":"<img src=\\"x\\">","contentHtml":"<img src=\\"y\\">","options":["<img src=\\"a\\">"],"answer":"0","answerIndex":0}]
""".data(using: .utf8)!
expect(RemotePracticeMapper.cards(from: picture, module: "政治理论").isEmpty, "纯图片题不进小卡片")

let chapters = """
[{"group":"政治理论","total":12},{"group":"常识判断","total":3}]
""".data(using: .utf8)!
expectEqual(RemotePracticeMapper.readyCount(from: chapters, module: "政治理论"), 12, "可刷数量按模块读取")
expectEqual(RemotePracticeMapper.readyCount(from: chapters, module: "全部"), 15, "全部科目把模块题量相加")
let statsData = """
{"total":4,"correct":3,"wrong":1,"rate":75}
""".data(using: .utf8)!
let stats = RemotePracticeMapper.studyStats(from: statsData, readyCount: 12)
expectEqual(stats.answeredCount, 4, "已做数量来自本地服务统计")
expectEqual(stats.correctCount, 3, "做对数量来自本地服务统计")
let wrongData = """
{"list":[{"questionId":9,"content":"这段预览不进入卡片"},{"questionId":9,"content":"重复"}]}
""".data(using: .utf8)!
expectEqual(RemotePracticeMapper.wrongIDs(from: wrongData), ["9"], "错题只取编号并去重")
expectEqual(RemotePracticeMapper.plain("甲&amp;乙<br>丙"), "甲&乙 丙", "题干去掉标签并还原符号")

let locatorRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xingce-locator-\(UUID().uuidString)", isDirectory: true)
do {
try FileManager.default.createDirectory(at: locatorRoot, withIntermediateDirectories: true)
let fakeServer = locatorRoot.appendingPathComponent("svc", isDirectory: true)
try FileManager.default.createDirectory(at: fakeServer, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: fakeServer.appendingPathComponent("server.mjs").path, contents: Data("".utf8))
let exists = { (path: String) in FileManager.default.fileExists(atPath: path) }
let fromEnv = PracticeLocator.practiceRoot(
    environment: ["XINGCE_PRACTICE_ROOT": fakeServer.path],
    currentDirectory: locatorRoot,
    supportDirectory: locatorRoot.appendingPathComponent("empty-support"),
    fileExists: exists
)
expectEqual(fromEnv?.standardizedFileURL.path, fakeServer.standardizedFileURL.path, "环境变量可定位刷题服务")
let localFile = locatorRoot.appendingPathComponent("practice-root.local")
try "# 注释\n\(fakeServer.path)\n".write(to: localFile, atomically: true, encoding: .utf8)
let fromFile = PracticeLocator.practiceRoot(
    environment: [:],
    currentDirectory: locatorRoot,
    supportDirectory: locatorRoot.appendingPathComponent("empty-support"),
    fileExists: exists
)
expectEqual(fromFile?.standardizedFileURL.path, fakeServer.standardizedFileURL.path, "practice-root.local 可定位刷题服务")
let fakeNode = locatorRoot.appendingPathComponent("node")
FileManager.default.createFile(atPath: fakeNode.path, contents: Data("".utf8))
let node = PracticeLocator.nodeExecutable(
    environment: ["XINGCE_NODE": fakeNode.path],
    supportDirectory: locatorRoot,
    fileExists: exists,
    pathLookup: { "/missing/node" }
)
expectEqual(node?.path, fakeNode.path, "XINGCE_NODE 优先于系统路径")
var leakedPath = false
if let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil) {
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if text.contains("/Users/") { leakedPath = true }
    }
}
expect(!leakedPath, "源码不含本机用户目录绝对路径")
} catch {
    failures.append("路径查找测试中断：\(error)")
    fputs("FAIL 路径查找测试中断：\(error)\n", stderr)
}

if failures.isEmpty {
    print("ALL TESTS PASSED")
    exit(EXIT_SUCCESS)
} else {
    fputs("\(failures.count) TESTS FAILED\n", stderr)
    exit(EXIT_FAILURE)
}
