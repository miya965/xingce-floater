import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class FloatingWindowManager: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: FloatingPanel
    private let container: FloatingContainer
    private var chromeCancellable: AnyCancellable?
    private var hotkey = HotkeyCenter()
    private var keyMonitor: Any?
    private var ignoreMiniClickUntil = Date.distantPast
    private var appliedChrome: WindowChrome = .mini

    init(model: AppModel) {
        self.model = model
        let initial = WindowFrameStore.initialMiniFrame()
        panel = FloatingPanel(contentRect: initial, styleMask: [.borderless], backing: .buffered, defer: false)
        container = FloatingContainer(model: model)
        super.init()
        panel.contentView = container
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.onEscape = { [weak self] in
            self?.collapseToMini()
        }
        panel.lockSize = true
        panel.isRestorable = false
        panel.delegate = self
        panel.isMini = { [weak self] in self?.model.chrome == .mini }
        panel.trackMini = { [weak self] event in
            self?.trackMiniDrag(event)
        }
        container.onMiniClick = { [weak self] in
            self?.model.chrome = .card
        }
        container.onDragEnd = { [weak self] in
            self?.persistPosition()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(persistPosition), name: .floatingWindowDragEnded, object: nil)
        chromeCancellable = model.$chrome.sink { [weak self] chrome in
            self?.apply(chrome)
        }
        installKeyMonitor()
        hotkey.onPress = { [weak self] in
            self?.toggleVisibility()
        }
        if !hotkey.register() {
            model.statusMessage = "Control+Option+Q 注册失败，可能与其他软件冲突。窗口仍可从程序坞打开。"
        }
        apply(model.chrome)
    }

    func show() {
        apply(model.chrome)
        panel.orderFrontRegardless()
        if model.chrome == .card {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
    }

    func toggleVisibility() {
        if panel.isVisible {
            persistPosition()
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    @objc func persistPosition() {
        WindowFrameStore.save(panel.frame.origin)
    }

    private func collapseToMini() {
        guard model.chrome == .card else { return }
        ignoreMiniClickUntil = Date().addingTimeInterval(0.4)
        model.chrome = .mini
    }

    private func apply(_ chrome: WindowChrome) {
        if chrome == .mini, appliedChrome == .card {
            ignoreMiniClickUntil = Date().addingTimeInterval(0.4)
        }
        appliedChrome = chrome
        panel.preferMini = chrome == .mini
        let size = chrome == .mini
            ? NSSize(width: FloaterMetrics.miniSide, height: FloaterMetrics.miniSide)
            : NSSize(width: FloaterMetrics.cardWidth, height: FloaterMetrics.cardHeight)
        var frame = panel.frame
        frame.origin.x = frame.maxX - size.width
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        frame = WindowFrameStore.clamp(frame)
        panel.contentMinSize = NSSize(width: 1, height: 1)
        panel.contentMaxSize = NSSize(width: 2000, height: 2000)
        if chrome == .mini {
            panel.isOpaque = false
            panel.backgroundColor = .clear
        } else {
            panel.isOpaque = true
            panel.backgroundColor = NSColor(calibratedRed: 0.969, green: 0.953, blue: 0.918, alpha: 1)
        }
        container.displayChrome = chrome
        if chrome == .card { container.layer?.contents = nil }
        panel.setFrame(frame, display: true, animate: false)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.invalidateShadow()
        container.noteChromeChanged()
        if chrome == .card {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(container)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard self.model.chrome == .card, self.panel.isVisible, NSApp.isActive else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return event
            }
            switch event.keyCode {
            case 0: self.model.select("A"); return nil
            case 11: self.model.select("B"); return nil
            case 8: self.model.select("C"); return nil
            case 2: self.model.select("D"); return nil
            case 36, 76: self.model.submit(); return nil
            case 53:
                self.collapseToMini()
                return nil
            default:
                return event
            }
        }
    }

    private func trackMiniDrag(_ event: NSEvent) {
        if Date() < ignoreMiniClickUntil {
            while true {
                guard let next = panel.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp],
                    until: Date.distantFuture,
                    inMode: .eventTracking,
                    dequeue: true
                ) else { continue }
                if next.type == .leftMouseUp { break }
            }
            return
        }
        let start = NSEvent.mouseLocation
        let origin = panel.frame.origin
        var dragged = false
        while true {
            guard let next = panel.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date.distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { continue }
            if next.type == .leftMouseUp { break }
            let location = NSEvent.mouseLocation
            let dx = location.x - start.x
            let dy = location.y - start.y
            if abs(dx) > 2 || abs(dy) > 2 { dragged = true }
            panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
        if dragged {
            persistPosition()
        } else {
            model.chrome = .card
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        collapseToMini()
        return false
    }
}

final class FloatingPanel: NSPanel {
    var isMini: () -> Bool = { false }
    var trackMini: ((NSEvent) -> Void)?
    var onEscape: () -> Void = {}
    var lockSize = false
    var preferMini = true

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(lockedFrame(frameRect), display: displayFlag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(lockedFrame(frameRect), display: displayFlag, animate: animateFlag)
    }

    override func setContentSize(_ size: NSSize) {
        let frame = lockedFrame(NSRect(origin: frame.origin, size: size))
        super.setContentSize(frame.size)
    }

    private func lockedFrame(_ frameRect: NSRect) -> NSRect {
        guard lockSize else { return frameRect }
        let size = preferMini
            ? NSSize(width: FloaterMetrics.miniSide, height: FloaterMetrics.miniSide)
            : NSSize(width: FloaterMetrics.cardWidth, height: FloaterMetrics.cardHeight)
        return NSRect(
            x: frameRect.maxX - size.width,
            y: frameRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, !isMini() {
            onEscape()
            return
        }
        if event.type == .leftMouseDown, isMini() {
            trackMini?(event)
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !isMini() {
            onEscape()
            return
        }
        super.keyDown(with: event)
    }
}

enum FloaterMetrics {
    static let miniSide: CGFloat = 48
    static let cardWidth: CGFloat = 260
    static let cardHeight: CGFloat = 320
}

final class FloatingContainer: NSView {
    let hosting: NSHostingView<RootView>
    var onMiniClick: () -> Void = {}
    var onDragEnd: () -> Void = {}
    private let model: AppModel
    private let sheepView = NSImageView()
    var displayChrome: WindowChrome = .mini

    init(model: AppModel) {
        self.model = model
        hosting = NSHostingView(rootView: RootView(model: model))
        super.init(frame: .zero)
        sheepView.imageScaling = .scaleProportionallyDown
        sheepView.image = FloatingContainer.sheepImage(side: 48)
        addSubview(hosting)
        addSubview(sheepView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func noteChromeChanged() {
        layer?.contents = nil
        installChromeViews()
        if displayChrome == .card {
            hosting.needsLayout = true
            hosting.needsDisplay = true
            layoutSubtreeIfNeeded()
        } else {
            sheepView.needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        if displayChrome == .mini {
            if hosting.superview != nil { hosting.removeFromSuperview() }
            sheepView.frame = bounds
        } else {
            hosting.frame = bounds
        }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if displayChrome == .mini, subview === hosting {
            subview.removeFromSuperview()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contents = nil
        installChromeViews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if displayChrome == .mini { return self }
        return super.hitTest(point)
    }

    private func installChromeViews() {
        wantsLayer = true
        if displayChrome == .mini {
            if hosting.superview != nil { hosting.removeFromSuperview() }
            hosting.isHidden = true
            if sheepView.superview == nil { addSubview(sheepView) }
            sheepView.isHidden = false
            sheepView.frame = bounds
            layer?.contentsGravity = .center
            layer?.contents = sheepView.image
        } else {
            layer?.contents = nil
            sheepView.isHidden = true
            if sheepView.superview != nil { sheepView.removeFromSuperview() }
            if hosting.superview == nil { addSubview(hosting) }
            hosting.isHidden = false
            hosting.alphaValue = 1
            hosting.frame = bounds
        }
        needsLayout = true
        needsDisplay = true
    }

    private static func sheepImage(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedRed: 0.55, green: 0.16, blue: 0.16, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            FloatingContainer.drawLamb(in: rect.insetBy(dx: 7, dy: 7))
            return true
        }
    }

    private static func drawLamb(in rect: NSRect) {
        let wool = NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        let face = NSColor(calibratedRed: 0.98, green: 0.91, blue: 0.82, alpha: 1)
        let ink = NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.13, alpha: 1)

        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y,
                width: rect.width * w,
                height: rect.height * h
            )).fill()
        }

        oval(0.34, 0.02, 0.12, 0.22, wool)
        oval(0.54, 0.02, 0.12, 0.22, wool)
        oval(0.08, 0.16, 0.84, 0.52, wool)
        oval(0.02, 0.30, 0.28, 0.30, wool)
        oval(0.70, 0.30, 0.28, 0.30, wool)
        oval(0.22, 0.34, 0.56, 0.36, wool)
        oval(0.30, 0.58, 0.40, 0.36, face)
        oval(0.18, 0.70, 0.18, 0.16, face)
        oval(0.64, 0.70, 0.18, 0.16, face)
        oval(0.40, 0.70, 0.07, 0.08, ink)
        oval(0.53, 0.70, 0.07, 0.08, ink)
    }
}

enum WindowFrameStore {
    private static let xKey = "floatingOriginX"
    private static let yKey = "floatingOriginY"

    static func initialMiniFrame() -> NSRect {
        if UserDefaults.standard.object(forKey: xKey) != nil {
            let origin = NSPoint(x: UserDefaults.standard.double(forKey: xKey), y: UserDefaults.standard.double(forKey: yKey))
            return clamp(NSRect(origin: origin, size: NSSize(width: 48, height: 48)))
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(x: visible.maxX - 48 - 24, y: visible.midY)
        return clamp(NSRect(origin: origin, size: NSSize(width: 48, height: 48)))
    }

    static func save(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: xKey)
        UserDefaults.standard.set(origin.y, forKey: yKey)
    }

    static func clamp(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        if result.width > visible.width { result.size.width = visible.width }
        if result.height > visible.height { result.size.height = visible.height }
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        return result
    }
}

final class HotkeyCenter {
    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue().onPress()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else {
            fputs("快捷键事件安装失败：\(installed)\n", stderr)
            return false
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x58434651), id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        var status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &hotKey
        )
        if status != noErr {
            status = RegisterEventHotKey(UInt32(kVK_ANSI_Q), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
            fputs("Control+Option+Q 已被其他程序占用，改为非独占注册，状态 \(status)\n", stderr)
            fflush(stderr)
        }
        return status == noErr
    }

    deinit {
        if let hotKey = hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler = handler {
            RemoveEventHandler(handler)
        }
    }
}
