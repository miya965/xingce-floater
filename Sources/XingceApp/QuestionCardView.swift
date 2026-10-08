import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        QuestionCardView(model: model)
    }
}

struct QuestionCardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let question = model.session.current {
                        if let material = question.material {
                            materialBlock(material)
                        }
                        imageBlock(question.images)
                        Text(question.stem)
                            .font(.system(size: 12))
                            .foregroundColor(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(question.options) { option in
                            optionButton(option, question: question)
                        }
                        if model.session.locked.contains(question.id) {
                            explanationBlock(question)
                        }
                    } else if model.isLoading {
                        Text("正在取题…")
                            .font(.system(size: 12))
                            .foregroundColor(ink)
                            .padding(.top, 16)
                    } else {
                        Text(model.statusMessage.isEmpty ? "这一筛选下没有可刷题目。" : model.statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(ink)
                            .padding(.top, 16)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: FloaterMetrics.cardWidth, height: FloaterMetrics.cardHeight)
        .background(paper)
        .controlSize(.small)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .trailing) {
                DragArea()
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                HStack(spacing: 8) {
                    Text("行测刷题")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(seal)
                    Spacer(minLength: 8)
                    Button("收起") { model.chrome = .mini }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(seal)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
            }
            HStack(spacing: 4) {
                Text("科目")
                    .font(.system(size: 11))
                    .foregroundColor(Color.black.opacity(0.55))
                Picker("科目", selection: $model.subject) {
                    Text("全部").tag("全部")
                    ForEach(model.subjects, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: model.subject) { _ in model.reload() }
                Text("方式")
                    .font(.system(size: 11))
                    .foregroundColor(Color.black.opacity(0.55))
                Picker("方式", selection: $model.mode) {
                    ForEach(PracticeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .labelsHidden()
                .frame(width: 92)
                .onChange(of: model.mode) { _ in model.reload() }
            }
            if let question = model.session.current {
                Text("\(question.subject) · \(question.typeName) · \(question.kindTitle) · \(model.session.progressText)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.black.opacity(0.62))
            }
            Text("可刷 \(model.stats.readyCount) · 已做 \(model.stats.accuracyText) · 错题 \(model.stats.wrongCount)")
                .font(.system(size: 10))
                .foregroundColor(Color.black.opacity(0.55))
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(seal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("上一题") { model.session.goToPrevious() }
                    .disabled((model.session.index == 0) || model.session.questions.isEmpty)
                Button(submitTitle) { model.submit() }
                    .disabled(!canSubmit)
                Button("下一题") {
                    if model.session.index + 1 >= model.session.questions.count {
                        model.loadMore()
                    } else {
                        model.session.goToNext()
                    }
                }
                    .disabled(model.session.questions.isEmpty || model.isLoading)
            }
            HStack {
                Button("导入 JSON") { model.chooseJSONAndImport() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(seal)
                Spacer()
                Text("A–D / Enter / Esc")
                    .font(.system(size: 10))
                    .foregroundColor(Color.black.opacity(0.45))
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(Color.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var submitTitle: String {
        guard let question = model.session.current else { return "提交" }
        return model.session.locked.contains(question.id) ? "已提交" : "提交"
    }

    private var canSubmit: Bool {
        guard let question = model.session.current else { return false }
        if model.session.locked.contains(question.id) { return false }
        return !(model.session.selectedKeys(for: question.id).isEmpty)
    }

    private func materialBlock(_ material: SharedMaterial) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(material.title.isEmpty ? "共用材料" : material.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(seal)
            Text(material.body)
                .font(.system(size: 12))
                .foregroundColor(ink)
                .fixedSize(horizontal: false, vertical: true)
            imageBlock(material.images)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private func imageBlock(_ images: [StoredImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(images) { image in
                if let nsImage = NSImage(contentsOf: model.repository.assetsRoot.appendingPathComponent(image.relativePath)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 72)
                }
            }
        }
    }

    private func optionButton(_ option: QuestionOption, question: Question) -> some View {
        let locked = model.session.locked.contains(question.id)
        let selected = model.session.selectedKeys(for: question.id).contains(option.key)
        let tone = optionTone(option: option, question: question, selected: selected, locked: locked)
        return Button(action: { model.select(option.key) }) {
            HStack(alignment: .top, spacing: 6) {
                Text(option.key)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(tone.badge)
                    .foregroundColor(tone.badgeText)
                    .cornerRadius(9)
                Text(option.text)
                    .font(.system(size: 12))
                    .foregroundColor(tone.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.fill)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tone.border, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(!locked)
    }

    private func explanationBlock(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("答案 \(question.answerKeys.joined(separator: "、"))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(correctGreen)
            Text(question.explanation)
                .font(.system(size: 12))
                .foregroundColor(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(question.licenseNote)
                .font(.system(size: 10))
                .foregroundColor(Color.black.opacity(0.45))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7))
        .cornerRadius(8)
    }

    private func optionTone(option: QuestionOption, question: Question, selected: Bool, locked: Bool) -> OptionTone {
        if locked {
            let isAnswer = question.answerKeys.contains(option.key)
            if isAnswer { return .correct }
            if selected { return .wrong }
            return .dimmed
        }
        return selected ? .selected : .idle
    }

    private var paper: Color { Color(red: 0.969, green: 0.953, blue: 0.918) }
    private var ink: Color { Color(red: 0.12, green: 0.11, blue: 0.09) }
    private var seal: Color { Color(red: 0.55, green: 0.16, blue: 0.16) }
    private var correctGreen: Color { Color(red: 0.12, green: 0.42, blue: 0.30) }
}

private struct OptionTone {
    var fill: Color
    var border: Color
    var text: Color
    var badge: Color
    var badgeText: Color

    static let idle = OptionTone(
        fill: Color.white.opacity(0.55),
        border: Color.black.opacity(0.08),
        text: Color(red: 0.12, green: 0.11, blue: 0.09),
        badge: Color.black.opacity(0.06),
        badgeText: Color(red: 0.12, green: 0.11, blue: 0.09)
    )
    static let selected = OptionTone(
        fill: Color(red: 0.55, green: 0.16, blue: 0.16).opacity(0.08),
        border: Color(red: 0.55, green: 0.16, blue: 0.16),
        text: Color(red: 0.12, green: 0.11, blue: 0.09),
        badge: Color(red: 0.55, green: 0.16, blue: 0.16),
        badgeText: .white
    )
    static let correct = OptionTone(
        fill: Color(red: 0.12, green: 0.42, blue: 0.30).opacity(0.12),
        border: Color(red: 0.12, green: 0.42, blue: 0.30),
        text: Color(red: 0.12, green: 0.11, blue: 0.09),
        badge: Color(red: 0.12, green: 0.42, blue: 0.30),
        badgeText: .white
    )
    static let wrong = OptionTone(
        fill: Color(red: 0.70, green: 0.16, blue: 0.14).opacity(0.12),
        border: Color(red: 0.70, green: 0.16, blue: 0.14),
        text: Color(red: 0.12, green: 0.11, blue: 0.09),
        badge: Color(red: 0.70, green: 0.16, blue: 0.14),
        badgeText: .white
    )
    static let dimmed = OptionTone(
        fill: Color.white.opacity(0.3),
        border: Color.black.opacity(0.05),
        text: Color.black.opacity(0.45),
        badge: Color.black.opacity(0.05),
        badgeText: Color.black.opacity(0.45)
    )
}

struct DragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowDragView: NSView {
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(
            x: startOrigin.x + location.x - startMouse.x,
            y: startOrigin.y + location.y - startMouse.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        NotificationCenter.default.post(name: .floatingWindowDragEnded, object: nil)
    }
}

extension Notification.Name {
    static let floatingWindowDragEnded = Notification.Name("floatingWindowDragEnded")
}
