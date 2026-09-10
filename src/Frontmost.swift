// Frontmost.swift — 检测「用户是否已回到 dsh 网页界面」
// 策略（无授权也能用，有授权更精确）：
//  1) 用 NSWorkspace.frontmostApplication 判断前台是否是浏览器（公开 API，无需权限）；
//  2) 若应用已获自动化授权（Apple Events），再读浏览器活动标签 URL 是否 127.0.0.1:3080（精确）；
//  3) 若读 URL 失败（未授权/浏览器不支持），则只要「浏览器在最前台」就视为已回界面（宽松降级）。
import AppKit
import Foundation

enum Frontmost {

    /// 常见浏览器的 bundle identifier 集合
    private static let browserBundleIDs: Set<String> = [
        "com.microsoft.edgemac",        // Edge
        "com.apple.Safari",             // Safari
        "com.google.Chrome",            // Chrome
        "org.mozilla.firefox",          // Firefox
        "company.thebrowser.Browser",   // Arc
        "com.brave.Browser",            // Brave
        "com.operasoftware.Opera",      // Opera
        "com.vivaldi.Vivaldi",          // Vivaldi
    ]

    /// 已确认能读到浏览器标签 URL？（避免每次失败反复触发授权弹窗/拖慢）
    private static var urlReadWorks: Bool? = nil

    /// 用户是否正回到 dsh 界面
    static func looksBackAtDSH() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        guard let bid = front.bundleIdentifier?.lowercased() else { return false }
        let appName = front.localizedName?.lowercased() ?? ""

        // 是否浏览器
        var isBrowser = browserBundleIDs.contains(bid)
        if !isBrowser {
            isBrowser = ["safari", "chrome", "edge", "firefox", "arc", "brave", "opera", "vivaldi"]
                .contains { appName.contains($0) }
        }
        guard isBrowser else { return false }          // 前台不是浏览器 → 没回界面

        // 浏览器在前台。能读 URL 就精确判断；不能读则降级为“浏览器前台即回”。
        if urlReadWorks == false { return true }
        guard let u = readActiveTabURL(bundleID: bid) else {
            // 读取失败：可能是未授权或该浏览器不支持 —— 记录并走宽松降级
            if urlReadWorks == nil { urlReadWorks = false }
            return true
        }
        if urlReadWorks == nil { urlReadWorks = true }
        return u.contains("127.0.0.1:3080") || u.contains("localhost:3080")
    }

    /// 按浏览器 bundle id 生成读活动标签 URL 的 AppleScript
    private static func readActiveTabURL(bundleID: String) -> String? {
        guard let app = appName(brid: bundleID) else { return nil }
        let tabExpr = (bundleID == "com.apple.Safari")
            ? "URL of current tab of front window"
            : "URL of active tab of front window"
        return runOSA(#"tell application "\#(app)" to get \#(tabExpr)"#)
    }

    /// 常用浏览器的 AppleScript 应用名
    private static func appName(brid: String) -> String? {
        switch brid {
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "com.google.Chrome": return "Google Chrome"
        case "com.apple.Safari": return "Safari"
        case "company.thebrowser.Browser": return "Arc"
        case "com.brave.Browser": return "Brave Browser"
        default: return nil     // Firefox/其余无法精确控制 → nil
        }
    }

    /// 让浏览器聚焦到 dsh 网页：优先切到已打开的 3080 标签/窗口；没有则在前台窗口新增标签。
    /// 依次尝试运行中的受支持浏览器（前台优先）。
    /// 返回结果说明：
    ///   "focused" — 已切到原有 3080 标签；
    ///   "newtab"  — 无该标签，在已有窗口新增了标签；
    ///   "activated" — AppleScript 失败(未授权等)，仅激活了浏览器（不新开窗口）；
    ///   "none"    — 无运行中浏览器且系统打开也失败。
    static func bringDSHToFront(url dshURL: String) -> String {
        let target = "127.0.0.1:3080"
        let running = NSWorkspace.shared.runningApplications
        let frontBid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased()

        // 排序：前台浏览器 → 其它运行中的受支持浏览器（保持顺序）
        var ordered: [String] = []
        if let fb = frontBid { ordered.append(fb) }
        for app in running {
            guard let bid = app.bundleIdentifier?.lowercased(), appName(brid: bid) != nil else { continue }
            if !ordered.contains(bid) { ordered.append(bid) }
        }
        guard !ordered.isEmpty else {
            // 无受控浏览器在跑 → 系统默认浏览器打开（此时必然没有可用页面，需要恢复）
            _ = NSWorkspace.shared.open(URL(string: dshURL)!)
            return "newtab"
        }

        for bid in ordered {
            guard let app = appName(brid: bid) else { continue }
            let isSafari = (bid == "com.apple.Safari")
            let script: String
            if isSafari {
                script = #"""
                tell application "\#(app)"
                  activate
                  set targetURL to "\#(dshURL)"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if (URL of t) contains "\#(target)" then
                        set current tab of w to t
                        return "focused"
                      end if
                    end repeat
                  end repeat
                  make new tab at end of tabs of front window with properties {URL:targetURL}
                  return "newtab"
                end tell
                """#
            } else {
                // Chromium 系（Edge/Chrome/Brave/Arc）：活动标签即目标 → focused；
                // 有目标标签但切不过去(只读) → found；完全没有 → 新增标签恢复 → newtab
                script = #"""
                tell application "\#(app)"
                  activate
                  set targetURL to "\#(dshURL)"
                  if (URL of active tab of front window) contains "\#(target)" then return "focused"
                  set hasIt to false
                  repeat with w in windows
                    repeat with t in tabs of w
                      if (URL of t) contains "\#(target)" then
                        set hasIt to true
                        try
                          set active tab of w to t
                          return "focused"
                        end try
                      end if
                    end repeat
                  end repeat
                  if hasIt then return "found"
                  make new tab at end of tabs of front window with properties {URL:targetURL}
                  return "newtab"
                end tell
                """#
            }
            if let out = runOSA(script) {
                let s = out.lowercased()
                if s.contains("focused") { return "focused" }
                if s.contains("newtab") { return "newtab" }
                if s.contains("found") { return "found" }
            }
            // AppleScript 失败（很可能未授权）→ 仅激活浏览器；因无法确认页面是否还在，
            // 再走系统默认打开兜底一次（可确保「找回页面」，代价可能是新开一个标签）
            if activateBrowser(bundleID: bid) {
                _ = NSWorkspace.shared.open(URL(string: dshURL)!)
                return "activated"
            }
        }
        // 都失败：最后尝试激活任一受支持浏览器并系统打开兜底
        for bid in ordered where activateBrowser(bundleID: bid) {
            _ = NSWorkspace.shared.open(URL(string: dshURL)!)
            return "activated"
        }
        return "none"
    }

    /// 仅把浏览器带到前台（不新开窗口、不新开标签，无需自动化授权）
    private static func activateBrowser(bundleID: String) -> Bool {
        guard let target = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased() == bundleID
        }) else { return false }
        return target.activate(options: [.activateAllWindows])
    }

    /// 执行 osascript 并返回输出（超时约 2s；失败/未授权返回 nil）
    private static func runOSA(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let deadline = Date().addingTimeInterval(2.0)
            var data = Data()
            while Date() < deadline, p.isRunning {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { Thread.sleep(forTimeInterval: 0.015) } else { data.append(chunk) }
            }
            if p.isRunning { p.terminate() }
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        } catch {
            return nil
        }
    }
}
