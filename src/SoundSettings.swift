// SoundSettings.swift — 提示音设置：分类、可选音效、重复次数、试听与播放
//
// 设计要点：
//  · 每个「用途」一个槽位（slot），各自记住自己的音效与重复次数（UserDefaults 持久化）
//  · 重复次数支持 1 / 2 / 3 / 5 次，以及 0 = 一直重复到鼠标移到程序坞（或菜单栏）上
//  · 「直到鼠标移过来」的判定：用 NSScreen.frame 与 visibleFrame 的差值算出程序坞/菜单栏所在区域，
//    轮询鼠标位置判断进入。程序坞图标本身由 Dock 进程绘制、拿不到 hover 事件，这是可靠且无需
//    辅助功能权限的做法。
import AppKit
import Foundation

/// 提示音用途
enum SoundSlot: String, CaseIterable {
    case confirm        // 需确认（审批）
    case question       // 等你选择
    case complete       // 任务完成
    case serviceStart   // 服务启动就绪
    case serviceStop    // 服务停止

    /// 默认为 0 表示「一直重复直到鼠标移过来」
    static let untilHover = 0

    var defaultSound: String {
        switch self {
        case .confirm: return "Purr"
        case .question: return "Ping"
        case .complete: return "Glass"
        case .serviceStart: return "Pop"
        case .serviceStop: return "Funk"
        }
    }

    /// 提醒类可设置重复次数；服务类只响一次
    var supportsRepeat: Bool {
        switch self {
        case .confirm, .question, .complete: return true
        case .serviceStart, .serviceStop: return false
        }
    }

    var localizedName: String {
        switch self {
        case .confirm: return NSLocalizedString("sound.slot.confirm", comment: "")
        case .question: return NSLocalizedString("sound.slot.question", comment: "")
        case .complete: return NSLocalizedString("sound.slot.complete", comment: "")
        case .serviceStart: return NSLocalizedString("sound.slot.start", comment: "")
        case .serviceStop: return NSLocalizedString("sound.slot.stop", comment: "")
        }
    }

    private var soundKey: String { "sound.name.\(rawValue)" }
    private var repeatKey: String { "sound.repeat.\(rawValue)" }

    var soundName: String {
        UserDefaults.standard.string(forKey: soundKey) ?? defaultSound
    }

    /// 便于在 `let` 常量上调用（枚举是值类型，属性 setter 无法在 let 上赋值）
    func setSound(_ name: String) {
        UserDefaults.standard.set(name, forKey: soundKey)
    }

    /// 重复次数；1 = 只响一次，0 = 直到鼠标移到程序坞
    var repeatCount: Int {
        guard supportsRepeat else { return 1 }
        guard let v = UserDefaults.standard.object(forKey: repeatKey) as? Int else { return 1 }
        return v
    }

    func setRepeat(_ count: Int) {
        UserDefaults.standard.set(count, forKey: repeatKey)
    }

    /// 菜单里显示的一行摘要：`需确认 · Purr（×2）`
    var menuSummary: String {
        supportsRepeat
            ? "\(localizedName) · \(soundName)（\(Sounds.repeatLabel(repeatCount))）"
            : "\(localizedName) · \(soundName)"
    }
}

/// 可选音效来源与文案
enum Sounds {
    /// 系统音效目录（含用户自定义目录）
    static let searchPaths = [
        "/System/Library/Sounds",
        "/Library/Sounds",
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds"),
    ]

    /// 去重且排序后的可用音效名（不含扩展名）
    static func available() -> [String] {
        var names = Set<String>()
        for dir in searchPaths {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in items {
                let ext = (f as NSString).pathExtension.lowercased()
                guard ["aiff", "aif", "caf", "wav", "m4a"].contains(ext) else { continue }
                names.insert((f as NSString).deletingPathExtension)
            }
        }
        return names.sorted()
    }

    /// 按名字加载音效（先按系统音效名，再按完整路径兜底）
    static func sound(named name: String) -> NSSound? {
        if let s = NSSound(named: NSSound.Name(name)) { return s }
        for dir in searchPaths {
            for ext in ["aiff", "aif", "caf", "wav", "m4a"] {
                let p = (dir as NSString).appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: p),
                   let s = NSSound(contentsOfFile: p, byReference: true) { return s }
            }
        }
        return nil
    }

    static func repeatLabel(_ count: Int) -> String {
        count == SoundSlot.untilHover
            ? NSLocalizedString("menu.sound.repeat.untilHover", comment: "")
            : String(format: NSLocalizedString("menu.sound.repeat.times", comment: ""), count)
    }
}

/// 播放中心：负责按策略播放、试听、以及在鼠标移到程序坞时停止
final class SoundCenter: NSObject, NSSoundDelegate {

    static let shared = SoundCenter()
    private override init() { super.init() }

    private var current: NSSound?
    private var remaining = 0
    private var hoverTimer: Timer?
    private var looping = false

    /// 选择音效时是否自动试听（可在右键菜单里关掉）
    var auditionOnSelect: Bool {
        get { UserDefaults.standard.object(forKey: "sound.auditionOnSelect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound.auditionOnSelect") }
    }

    /// 按该槽位配置的音效与重复次数播放
    func play(_ slot: SoundSlot) {
        stop()
        let name = slot.soundName
        guard let s = Sounds.sound(named: name) else { return }
        current = s
        s.delegate = self
        let count = slot.supportsRepeat ? slot.repeatCount : 1
        if count == SoundSlot.untilHover {
            looping = true
            s.loops = true
            s.play()
            startHoverWatch()
        } else {
            looping = false
            remaining = max(1, count) - 1
            s.play()
        }
    }

    /// 试听：只响一次，不受重复策略影响（切歌前先停掉正在播的）
    func preview(_ slot: SoundSlot, sound name: String? = nil) {
        stop()
        guard let s = Sounds.sound(named: name ?? slot.soundName) else { return }
        current = s
        s.loops = false
        s.delegate = self
        remaining = 0
        looping = false
        s.play()
    }

    /// 停止当前播放（含「一直重复」模式）
    func stop() {
        stopHoverWatch()
        if let s = current {
            s.loops = false
            if s.isPlaying { s.stop() }
            s.delegate = nil
        }
        current = nil
        remaining = 0
        looping = false
    }

    // MARK: NSSoundDelegate

    func soundDidFinishPlaying(_ notification: Notification) {
        guard let s = notification.object as? NSSound, s === current else { return }
        if looping { return }                 // loops 模式下由 hover 监听负责停
        if remaining > 0 {
            remaining -= 1
            s.play()
        } else {
            stop()
        }
    }

    // MARK: 鼠标移到程序坞/菜单栏即停

    /// 程序坞或菜单栏占据的屏幕区域（由 visibleFrame 与 frame 的差值推出）
    static func dockOrMenuBarContains(_ p: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let f = screen.frame
            let v = screen.visibleFrame
            var bands: [NSRect] = []
            if v.minY > f.minY {   // 程序坞在底部
                bands.append(NSRect(x: f.minX, y: f.minY, width: f.width, height: v.minY - f.minY))
            }
            if v.minX > f.minX {   // 程序坞在左侧
                bands.append(NSRect(x: f.minX, y: f.minY, width: v.minX - f.minX, height: f.height))
            }
            if v.maxX < f.maxX {   // 程序坞在右侧
                bands.append(NSRect(x: v.maxX, y: f.minY, width: f.maxX - v.maxX, height: f.height))
            }
            if v.maxY < f.maxY {   // 菜单栏
                bands.append(NSRect(x: f.minX, y: v.maxY, width: f.width, height: f.maxY - v.maxY))
            }
            if bands.contains(where: { $0.contains(p) }) { return true }
        }
        return false
    }

    private func startHoverWatch() {
        stopHoverWatch()
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if SoundCenter.dockOrMenuBarContains(NSEvent.mouseLocation) {
                self.stop()
                NotificationCenter.default.post(name: .soundStoppedByHover, object: nil)
            } else if self.current == nil {
                self.stopHoverWatch()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func stopHoverWatch() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    var isPlaying: Bool { current?.isPlaying ?? false }
}

extension Notification.Name {
    /// 「一直重复」的提示音因鼠标移到程序坞而停止
    static let soundStoppedByHover = Notification.Name("dshLauncher.soundStoppedByHover")
}
