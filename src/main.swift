// main.swift — DeepSeek Harness 开关（常驻状态型应用）
// Dock 图标 = 开关+待关注发光提醒。点击图标=打开 dsh 网页/启用服务，绝不停服务。
import AppKit
import UserNotifications

let kWebURL = URL(string: "http://127.0.0.1:3080")!

enum DisplayState: Equatable {
    case off, running, busy, reminding
    var live: LiveState {
        switch self {
        case .off: return .off
        case .running: return .running
        case .busy: return .busy
        case .reminding: return .confirm
        }
    }
}

enum RemindKind { case complete, confirm }

/// Dock 提醒动画视图：作为 NSDockTile.contentView，胶囊按呼吸缩放 + 霓虹光晕
final class RemindView: NSView {
    var color: NSColor = NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.55, alpha: 1)
    var glow: CGFloat = 1.0
    var capScale: CGFloat = 1.0
    var phase: CGFloat = 0            // 驱动边缘白色流光的环绕位置

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPulseIcon(rect: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height),
                      glowC: color, glow: glow, capScale: capScale,
                      variant: currentIconVariant(), phase: phase)
    }
}

/// Dock「任务进行中」动画视图：胶囊蓝↔绿渐变流动
final class BusyFlowView: NSView {
    var phase: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBusyFlowIcon(rect: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height),
                         phase: phase, variant: currentIconVariant())
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 状态
    private var displayState: DisplayState = .off
    private var remindKind: RemindKind? = nil
    private var serviceRunning = false
    private var turnActive = false
    private var cursors: [String: SessionCursor] = [:]
    private var monitorQueue = DispatchQueue(label: "dsh.monitor", qos: .background)

    // 提醒节奏（逻辑拍 0.5s）
    private var promptTimer: Timer?
    private var animTimer: Timer?               // 动画帧定时器（30fps，独立于逻辑拍）
    private var bigBouncesLeft = 0            // 剩几次“大跳”(critical)弹跳
    private var attentionRequestID: Int?      // 最近一次 Dock 弹跳请求 id（用于取消）

    /// 动画总开关（持久化到 UserDefaults，默认开启）
    private var animationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "animationsEnabled") }
    }

    // UI
    private var statusItem: NSStatusItem!

    // MARK: 生命周期
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        requestNotificationPermission()
        log("启动：DeepSeek Harness 开关")
        startPromptAnimator()
        DispatchQueue.global(qos: .userInitiated).async {
            let up = ServiceManager.isRunning()
            DispatchQueue.main.async {
                // 只如实反映服务状态，不再自动拉起 dsh：
                // 没运行（且没设开机自启）→ 图标默认显示“关闭”红色态，等用户点图标才启动。
                self.serviceRunning = up
                self.log("初始探测：服务\(up ? "运行中" : "未运行（图标=关闭）")")
                self.refreshUI()
            }
        }
        // 系统浅色/深色外观变化时刷新 Dock 图标（外观变体）
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main) { [weak self] _ in
                self?.refreshUI()
        }
        startMonitor()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log("点击程序坞图标")
        if serviceRunning {
            // 在提醒中就停止提醒并打开网页；空闲则直接回网页
            dismissReminding(reason: "点击图标回到网页")
            openBrowser()
        } else {
            startService(withBrowser: true)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 应用被激活（如点 Dock 图标/切回本 app）→ 取消 Dock 弹跳请求，立即安静
        if let id = attentionRequestID {
            NSApp.cancelUserAttentionRequest(id)
            attentionRequestID = nil
        }
        if remindKind != nil { dismissReminding(reason: "回到本 App 前台") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        promptTimer?.invalidate()
        animTimer?.invalidate()
        log("退出 DeepSeek Harness 开关")
    }

    // MARK: 菜单栏
    private func buildStatusItem() {
        serviceRunning = ServiceManager.isRunning()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuIconTemplate(.off)
        statusItem.button?.toolTip = "DeepSeek Harness 开关"
        statusItem.menu = buildMenu()
    }

    private let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let running = serviceRunning
        let line: String = {
            switch displayState {
            case .off: return "已停止"
            case .running: return "运行中 · 空闲"
            case .busy: return "运行中 · 处理中"
            case .reminding: return "运行中 · 待你看网页"
            }
        }()
        let s = NSMenuItem(title: "状态：\(line)", action: nil, keyEquivalent: "")
        s.isEnabled = false
        m.addItem(s)
        m.addItem(.separator())
        if running {
            let o = NSMenuItem(title: "打开 dsh 网页 (127.0.0.1:3080)", action: #selector(openWebAction), keyEquivalent: "")
            o.target = self; m.addItem(o)
            m.addItem(.separator())
            if displayState == .reminding {
                let a = NSMenuItem(title: "知道了，停止提醒", action: #selector(ackAction), keyEquivalent: "")
                a.target = self; m.addItem(a)
                m.addItem(.separator())
            }
            let r = NSMenuItem(title: "停止服务…", action: #selector(toggleMenu), keyEquivalent: "")
            r.target = self; m.addItem(r)
        } else {
            let r = NSMenuItem(title: "启动服务", action: #selector(toggleMenu), keyEquivalent: "")
            r.target = self; m.addItem(r)
        }
        let lg = NSMenuItem(title: "打开日志", action: #selector(openLogAction), keyEquivalent: "")
        lg.target = self; m.addItem(lg)
        m.addItem(.separator())
        let v = NSMenuItem(title: "版本 v\(appVersion)", action: nil, keyEquivalent: "")
        v.isEnabled = false; m.addItem(v)
        let q = NSMenuItem(title: "退出 DeepSeek Harness 开关", action: #selector(quitAction), keyEquivalent: "q")
        q.target = self; m.addItem(q)
        return m
    }

    @objc private func openWebAction() { if serviceRunning { dismissReminding(reason: "菜单：打开网页"); openBrowser() } }
    @objc private func ackAction() { if serviceRunning { dismissReminding(reason: "菜单：知道了") } }
    @objc private func toggleMenu() { serviceRunning ? confirmStop() : startService(withBrowser: true) }
    @objc private func toggleAnimations() {
        animationsEnabled = !animationsEnabled
        log("动画：\(animationsEnabled ? "开启" : "关闭")")
        if !animationsEnabled { teardownRemindView() }   // 立即停掉正在跑的动画视图
        refreshUI()
    }
    @objc private func openLogAction() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/dsh-launcher.log"))
    }
    @objc private func quitAction() { NSApp.terminate(nil) }

    // MARK: - Dock 右键菜单（左键=回到页面；右键=操作菜单：停止服务等）

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        let running = serviceRunning

        if running {
            let open = NSMenuItem(title: "打开 DeepSeek Harness 页面", action: #selector(openWebAction), keyEquivalent: "")
            open.target = self
            open.image = sfSymbol("globe")
            m.addItem(open)

            if displayState == .reminding {
                let ack = NSMenuItem(title: "知道了，停止提醒", action: #selector(ackAction), keyEquivalent: "")
                ack.target = self
                ack.image = sfSymbol("checkmark.circle")
                m.addItem(ack)
            }
            m.addItem(NSMenuItem.separator())

            let stop = NSMenuItem(title: "停止服务…", action: #selector(toggleMenu), keyEquivalent: "")
            stop.target = self
            stop.image = sfSymbol("stop.circle")
            m.addItem(stop)
        } else {
            let start = NSMenuItem(title: "启动服务", action: #selector(toggleMenu), keyEquivalent: "")
            start.target = self
            start.image = sfSymbol("play.circle")
            m.addItem(start)
        }

        m.addItem(NSMenuItem.separator())
        let anim = NSMenuItem(title: animationsEnabled ? "关闭动画" : "打开动画",
                              action: #selector(toggleAnimations), keyEquivalent: "")
        anim.target = self
        anim.image = sfSymbol("sparkles")
        m.addItem(anim)

        let log = NSMenuItem(title: "打开日志", action: #selector(openLogAction), keyEquivalent: "")
        log.target = self
        log.image = sfSymbol("doc.text")
        m.addItem(log)

        let quit = NSMenuItem(title: "退出 DeepSeek Harness 开关", action: #selector(quitAction), keyEquivalent: "q")
        quit.image = sfSymbol("power")
        quit.target = self
        m.addItem(quit)
        return m
    }

    // MARK: 服务
    private func confirmStop() {
        let a = NSAlert()
        a.messageText = "停止 DeepSeek Harness 服务？"
        a.informativeText = "关闭后任务监测与提示将暂停。"
        a.alertStyle = .warning
        // 遵循 HIG：破坏性操作不设默认按钮，回车＝取消（安全），并把停止标为破坏性（红色）
        a.addButton(withTitle: "取消")
        a.addButton(withTitle: "停止服务")
        if a.buttons.count > 1 { a.buttons[1].hasDestructiveAction = true }
        if a.runModal() == .alertSecondButtonReturn { stopService() }
    }

    private func startService(withBrowser open: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            if ServiceManager.isRunning() {
                DispatchQueue.main.async { self.serviceRunning = true; self.refreshUI(); if open { self.openBrowser() } }
                return
            }
            self.log("后台启动 dsh web …")
            guard ServiceManager.start() else {
                DispatchQueue.main.async { self.noteError("dsh 启动失败，日志 ~/Library/Logs/dsh-launcher.log") }
                return
            }
            if ServiceManager.keyProvisioned { self.log("已注入 DEEPSEEK_API_KEY") } else { self.log("未找到 DEEPSEEK_API_KEY") }
            self.log("等待服务就绪…")
            if ServiceManager.waitUntilRunning(timeout: 120) {
                DispatchQueue.main.async {
                    self.serviceRunning = true
                        self.refreshUI()
                    self.playSound("Pop")
                    if open { self.openBrowser() }
                }
            } else {
                DispatchQueue.main.async { self.noteError("120s 后 127.0.0.1:3080 无响应，见 ~/Library/Logs/dsh-web.log") }
            }
        }
    }
    private func openBrowser() {
        let result = Frontmost.bringDSHToFront(url: kWebURL.absoluteString)
        switch result {
        case "focused": log("已回到原有 dsh 标签页")
        case "newtab": log("原 dsh 页面已关闭，已在浏览器当前窗口新开标签恢复页面")
        case "found": log("dsh 标签页存在但无法自动切到（浏览器限制），已把浏览器带到前台")
        case "activated": log("未获得浏览器自动化权限：已打开系统默认页面（可能新开标签）。可在 系统设置→隐私与安全性→自动化 授权本 App 控制浏览器")
        default: log("打开 dsh 网页失败")
        }
    }

    private func stopService() {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ServiceManager.stop()
            DispatchQueue.main.async {
                self.log(ok ? "服务已停止" : "未发现服务")
                if ok {
                    self.serviceRunning = false
                    self.remindKind = nil
                    self.turnActive = false
                    self.cursors.removeAll()
                        self.playSound("Funk")
                }
                self.refreshUI()
            }
        }
    }

    // MARK: 持续提醒
    /// 逻辑拍（0.5s）：负责探测回网页、发大跳；动画帧交给 30fps 的 animBeat
    private func startPromptAnimator() {
        guard promptTimer == nil else { return }
        promptTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.promptBeat()
        }
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.animBeat()
        }
    }

    private func promptBeat() {
        guard serviceRunning, displayState == .reminding else { return }
        // 提醒中：每 0.5s 探测一次是否已回到 dsh 网页
        if Frontmost.looksBackAtDSH() {
            dismissReminding(reason: "焦点回到 dsh 网页")
            return
        }
        // 大跳阶段：连续几次单次弹跳（informational，可取消、不会一直弹到激活）
        if bigBouncesLeft > 0 {
            attentionRequestID = NSApp.requestUserAttention(.informationalRequest)
            playSound("Purr")
            bigBouncesLeft -= 1
            log("大跳剩余 \(bigBouncesLeft)")
        }
    }

    /// 30fps 动画帧：busy 蓝绿流动 / reminding 呼吸发光（仅动画开启时运行）
    private func animBeat() {
        guard serviceRunning, animationsEnabled else { return }
        let t = Date().timeIntervalSinceReferenceDate
        if displayState == .busy {
            guard let v = ensureBusyView() else { return }
            v.phase = CGFloat(t)               // 秒；drawBusyFlowIcon 内部按秒换算速度
            v.needsDisplay = true
            NSApp.dockTile.display()
        } else if displayState == .reminding {
            guard let v = ensureRemindView() else { return }
            v.color = (remindKind == .confirm)
                ? NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.10, alpha: 1)
                : NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.55, alpha: 1)
            let k = CGFloat(t)
            // 双频呼吸：主呼吸(慢) + 微脉动(快)，让光晕有层次、不死板
            let breathe = 0.5 + 0.5 * sin(k * 2.2)
            let shimmer = 0.5 + 0.5 * sin(k * 6.8)
            v.glow = 0.30 + 0.45 * breathe + 0.25 * shimmer
            v.capScale = 1.0 + 0.04 * sin(k * 2.2)
            v.phase = CGFloat(t)          // 边缘白色流光沿边缘环绕
            v.needsDisplay = true
            NSApp.dockTile.display()
        }
    }

    private func beginRemind(kind: RemindKind, reason: String) {
        guard serviceRunning else { return }
        remindKind = kind
        bigBouncesLeft = 4            // 先来 4 次大跳
        displayState = .reminding
        if kind == .confirm { NSApp.dockTile.badgeLabel = "!" }
        else { NSApp.dockTile.badgeLabel = "✓" }
        switch kind {
        case .confirm: postNotification(title: "DeepSeek Harness 需要确认", body: "有任务需要你到 dsh 网页确认。")
        case .complete: postNotification(title: "DeepSeek Harness · 完成", body: "任务已完成，去 dsh 网页查看。")
        }
        log("进入提醒：\(reason)（先大跳，后安静持续发光，直到你回 dsh 网页）")
        refreshUI()   // 立即切到提醒态并起动画
    }

    private func dismissReminding(reason: String) {
        guard remindKind != nil else { return }   // 只看 remindKind，避免与 displayState 相互依赖造成循环
        log("停止提醒：\(reason)")
        remindKind = nil
        bigBouncesLeft = 0
        // 取消尚未播完的 Dock 弹跳，避免“回到页面后仍抽搐”
        if let id = attentionRequestID {
            NSApp.cancelUserAttentionRequest(id)
            attentionRequestID = nil
        }
        NSApp.dockTile.badgeLabel = nil
        teardownRemindView()
        refreshUI()
    }

    // MARK: - Dock 提醒动画（NSDockTile.contentView）

    private var remindView: RemindView?
    private var busyView: BusyFlowView?

    private func ensureRemindView() -> RemindView? {
        if remindView == nil {
            busyView = nil
            let v = RemindView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            NSApp.dockTile.contentView = v
            remindView = v
        }
        return remindView
    }

    private func ensureBusyView() -> BusyFlowView? {
        if busyView == nil {
            remindView = nil
            let v = BusyFlowView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            NSApp.dockTile.contentView = v
            busyView = v
        }
        return busyView
    }

    /// 结束提醒/动画：切回静态图标（撤销 contentView，避免 Dock 停留在动画帧）
    private func teardownRemindView() {
        if remindView != nil || busyView != nil {
            remindView = nil
            busyView = nil
            NSApp.dockTile.contentView = nil
            NSApp.applicationIconImage = dockIcon(.running, variant: currentIconVariant())   // 立即回到正常静态图标
            NSApp.dockTile.display()                          // 强制 Dock 刷新，杜绝残留动画帧
        }
    }

    private func userSeesDSH() -> Bool { Frontmost.looksBackAtDSH() }

    // MARK: 监测
    private var monitorTimer: DispatchSourceTimer?
    private func startMonitor() {
        let t = DispatchSource.makeTimerSource(queue: monitorQueue)
        t.schedule(deadline: .now() + 1, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        monitorTimer = t
    }

    private func tick() {     // monitorQueue
        let running = ServiceManager.isRunning()
        if !running {
            DispatchQueue.main.async { if self.displayState != .off { self.remindKind = nil; self.turnActive = false; self.cursors.removeAll(); self.refreshUI() } }
            return
        }
        // 扫描事件
        var confirmSeen = false, completeSeen = false, busySeen = false
        let files = TaskMonitor.candidates()
        for url in files {
            let k = url.path
            var c = cursors[k] ?? SessionCursor()
            let initialized = c.prevLineCount != nil
            if !initialized { _ = TaskMonitor.scan(url: url, cursor: &c); cursors[k] = c; continue }
            let r = TaskMonitor.scan(url: url, cursor: &c)
            cursors[k] = c
            if r.confirm { confirmSeen = true }
            if r.complete { completeSeen = true }
            if r.busy { busySeen = true }
        }
        let live = Set(files.map { $0.path })
        cursors = cursors.filter { live.contains($0.key) }

        DispatchQueue.main.async {
            guard self.serviceRunning else { return }
            // 新出现的完成/需确认信号：先判断用户此刻是否已在本 dsh 网页（只有有真实信号才阻塞探测，频率低）
            var userBack = false
            if confirmSeen || completeSeen { userBack = Frontmost.looksBackAtDSH() }
            // 若此前已提醒过且用户刚回来 → 直接消停
            if (self.remindKind != nil) && userBack { self.dismissReminding(reason: "检测到回网页") }
            if completeSeen { self.turnActive = false }   // 回合结束，退出“进行中”
            if busySeen { self.turnActive = true }        // 新回合开始 → 进入“进行中”
            if confirmSeen { self.beginRemind(kind: .confirm, reason: "需确认") }
            else if completeSeen && !userBack { self.beginRemind(kind: .complete, reason: "完成") }
            self.refreshUI()
        }
    }

    private func computedState() -> DisplayState {
        guard serviceRunning else { return .off }
        // 仅以 remindKind 作为提醒态依据；displayState 是“展示结果”，不能当输入，
        // 否则 dismiss 清空 remindKind 后、displayState 未更新的瞬间会误判仍“在提醒”而重新点亮。
        if remindKind != nil { return .reminding }
        return turnActive ? .busy : .running
    }

    private func refreshUI() {
        let s = computedState()
        if s != displayState { log("状态切换 → \(stateLabel(s))") }
        displayState = s
        statusItem.button?.image = menuIconTemplate(s.live, size: 17)
        statusItem.button?.toolTip = "DeepSeek Harness 开关 · \(stateLabel(s))"
        statusItem.button?.menu = buildMenu()
        if s == .reminding {
            if animationsEnabled {
                animBeat()                                // 立即渲染一帧提醒动画（后续由 30fps 定时器持续驱动）
            } else {
                teardownRemindView()
                NSApp.applicationIconImage = dockIcon(.confirm, variant: currentIconVariant())   // 动画关闭：静态橙色提醒
            }
        } else if s == .busy {
            if animationsEnabled {
                animBeat()                                // 立即渲染一帧蓝绿流动（后续由 30fps 定时器持续驱动）
            } else {
                teardownRemindView()
                NSApp.applicationIconImage = dockIcon(.busy, variant: currentIconVariant())       // 动画关闭：静态蓝色
            }
        } else {
            teardownRemindView()                     // 撤销动画视图，回到静态图标
            NSApp.applicationIconImage = dockIcon(s.live, variant: currentIconVariant())
        }
    }

    private func stateLabel(_ s: DisplayState) -> String {
        switch s { case .off: return "已停止"; case .running: return "空闲"; case .busy: return "处理中"; case .reminding: return "待回网页查看" }
    }

    /// 取 SF Symbols 图标（供菜单项使用；取不到则返回 nil）
    private func sfSymbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.size = NSSize(width: 16, height: 16)
        return img
    }

    // MARK: 通知/声音/错误/日志
    private func postNotification(title: String, body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func playSound(_ n: String) { NSSound(named: NSSound.Name(n))?.play() }
    private func noteError(_ m: String) {
        log("错误：\(m)")
        let a = NSAlert(); a.messageText = "DeepSeek Harness 开关"; a.informativeText = m; a.alertStyle = .critical; a.addButton(withTitle: "好"); a.runModal()
    }
    private func log(_ m: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let l = "[\(f.string(from: Date()))] \(m)\n"
        FileHandle.standardError.write(Data(l.utf8))
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/dsh-launcher.log")
        if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: u) { defer { try? h.close() }; h.seekToEndOfFile(); h.write(Data(l.utf8)) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
