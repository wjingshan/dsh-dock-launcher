// TaskMonitor.swift — 检测 DSH「任务需要确认 / 任务完成」信号
// 数据源：~/.dsh/sessions/<workspace>/<session>/session.jsonl.zstd
// 事件行含 { seq, type, time, data }，按 seq 单调递增；不同会话文件各自独立编号。
// 支持多会话并行监测：每个文件一个游标（SessionCursor），按行数增量读取，避免重复解析历史。
import Foundation

struct MonitoredEvent {
    let seq: Int
    let type: String
    // goal/change 事件的附加信息（用于识别真正的 goal 完成 / 活跃状态）
    var goalOp: String?
    var goalPhase: String?
    // tool/call 事件的工具名（用于识别「停下来等你选」的交互式工具）
    var toolName: String?
    // tool/call 与 tool/result 的 callId（用于判断某个交互式提问是否已被处理）
    var callId: String?
}

/// 单个会话文件的监测游标
struct SessionCursor {
    var prevLineCount: Int? = nil   // 上次处理到的行数；nil = 尚未建立基线
    var goalActive = false          // 该会话当前是否存在未完成（活跃）的 goal
    var pendingQuestionCallId: String?  // 正在等待用户处理的交互式提问（其 tool/result 到达＝已处理）
}

/// 一次扫描的结果
struct ScanResult {
    var confirm = false   // 需要确认（审批 / 权限）
    var question = false  // 停下来等你选择（交互式提问 / 计划审批）
    var resumed = false   // 你已作出选择、dsh 继续运算（审批已决 或 新一轮开始）
    var complete = false  // 任务完成
    var busy = false      // 任务进行中
}

enum TaskMonitor {

    static func sessionsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/sessions")
    }

    /// 返回最近 period 秒内仍在更新的会话日志（按 mtime 降序）
    static func candidates(within period: TimeInterval = 900) -> [URL] {
        let fm = FileManager.default
        let root = sessionsRoot()
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let cutoff = Date().addingTimeInterval(-period)
        var found: [(Date, URL)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "session.jsonl.zstd" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let date = values?.contentModificationDate, date > cutoff else { continue }
            found.append((date, url))
        }
        found.sort { $0.0 > $1.0 }
        return found.map { $0.1 }
    }

    /// 定位可用的 zstd 可执行文件（供解压与“环境自检”共用）；找不到返回 nil
    static func zstdExecutablePath() -> String? {
        let candidates = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// 用 zstd 解压会话日志，返回全部文本行（缺 zstd 时返回 nil，调用方应优雅降级）
    static func decompressLines(url: URL) -> [String]? {
        guard let zstd = zstdExecutablePath() else {
            return nil
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: zstd)
        p.arguments = ["-d", "-c", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            // 先读尽输出再等待，避免管道缓冲塞满导致子进程阻塞
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(separator: "\n").map(String.init)
        } catch {
            return nil
        }
    }

    /// 解析一行事件 JSON
    static func parseLine(_ line: String) -> MonitoredEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = obj["type"] as? String,
              let seq = obj["seq"] as? Int else { return nil }
        var goalOp: String?
        var goalPhase: String?
        var toolName: String?
        var callId: String?
        if let data = obj["data"] as? [String: Any] {
            if type == "goal/change" {
                goalOp = data["operation"] as? String
                goalPhase = (data["goal"] as? [String: Any])?["phase"] as? String
            } else if type == "tool/call" {
                toolName = data["name"] as? String
                callId = data["callId"] as? String
            } else if type == "tool/result" {
                // 注意：提问的结果事件里 callId 嵌套在 data.message.source.callId
                // （tool/call 才把它放在顶层），两种位置都要读
                callId = data["callId"] as? String
                    ?? ((data["message"] as? [String: Any])?["source"] as? [String: Any])?["callId"] as? String
            }
        }
        return MonitoredEvent(seq: seq, type: type, goalOp: goalOp, goalPhase: goalPhase,
                              toolName: toolName, callId: callId)
    }

    // MARK: 信号判别

    /// 任务需要确认：审批/询问/权限事件
    static func isConfirmEvent(_ type: String) -> Bool {
        type == "approval/request" || type == "approval/asked" || type == "permission/ask"
    }

    /// 你已经作出选择、dsh 继续运算：审批被决定（approval/decided）或新一轮开始（turn/start）
    static func isResumeEvent(_ type: String) -> Bool {
        type == "approval/decided"
    }

    /// 停下来等你选择：这些工具会阻塞等你回答/批准，日志里**没有**专用事件
    /// （不像审批有 approval/asked），只以 `tool/call` 出现，因此按工具名识别。
    static func isQuestionTool(_ name: String?) -> Bool {
        name == "ask_user_question" || name == "exit_plan_mode"
    }

    /// 任务完成：真正的 goal 结束（goal/change 且操作为 complete / 阶段为 complete）
    static func isGoalCompleteEvent(_ e: MonitoredEvent) -> Bool {
        guard e.type == "goal/change" else { return false }
        return e.goalOp == "complete" || e.goalPhase == "complete"
    }

    /// goal 变为活跃的操作（create / resume）
    static func isGoalActivateOp(_ op: String?) -> Bool {
        op == "create" || op == "resume"
    }

    /// goal 变为关闭的操作（complete / block）
    static func isGoalCloseOp(_ op: String?) -> Bool {
        op == "complete" || op == "block"
    }

    // MARK: 扫描

    /// 扫描一个会话文件：增量推进游标，返回本批新事件对应的信号。
    /// 首次扫描（无基线）只初始化游标与 goalActive，不产生任何信号（避免回放历史）。
    static func scan(url: URL, cursor: inout SessionCursor) -> ScanResult {
        guard let lines = decompressLines(url: url) else { return ScanResult() }
        let n = lines.count

        if cursor.prevLineCount == nil {
            // 首次基线：记录行数；从历史中确定当前是否已有活跃 goal。
            // 只需要最后一个 goal/change 事件的 operation，倒序找最后一条 goal/change 行。
            // 注意：JSONSerialization 会把 "/" 转义为 "\/" ，因此两种写法都要匹配。
            for line in lines.reversed() {
                let looksGoal = line.contains("\"goal/change\"") || line.contains("\"goal\\/change\"")
                guard looksGoal else { continue }
                guard let e = parseLine(line), e.type == "goal/change" else { continue }
                if isGoalActivateOp(e.goalOp) { cursor.goalActive = true }
                else if isGoalCloseOp(e.goalOp) { cursor.goalActive = false }
                break
            }
            cursor.prevLineCount = n
            return ScanResult()
        }

        guard n > cursor.prevLineCount! else { return ScanResult() } // 无新增行
        let start = cursor.prevLineCount!
        var result = ScanResult()
        for line in lines[start..<n] {
            guard let e = parseLine(line) else { continue }
            switch e.type {
            case "goal/change":
                if let op = e.goalOp {
                    if isGoalActivateOp(op) { cursor.goalActive = true }
                    else if isGoalCloseOp(op) { cursor.goalActive = false }
                }
                if isGoalCompleteEvent(e) { result.complete = true }
            case "turn/end":
                // 有活跃 goal 时回合结束不算完成（等 goal 真正结束）；
                // 无 goal 的普通对话，回合结束即「任务完成」。
                if !cursor.goalActive { result.complete = true }
            case "turn/start":
                result.busy = true
                result.resumed = true        // 新一轮开始 = 你已选择、dsh 继续
            case "approval/decided":
                result.resumed = true
            case "tool/call":
                // 交互式提问 / 计划审批：会话在这里停下来等你选，日志里没有专用事件
                if isQuestionTool(e.toolName) {
                    result.question = true
                    cursor.pendingQuestionCallId = e.callId
                }
            case "tool/result":
                // 该提问的 tool/result 到达 = 你已经在页面上处理完（选了某一项，或直接关掉）
                if let cid = e.callId, cid == cursor.pendingQuestionCallId {
                    result.resumed = true
                    cursor.pendingQuestionCallId = nil
                }
            default:
                if isConfirmEvent(e.type) { result.confirm = true }
            }
        }
        cursor.prevLineCount = n
        return result
    }
}
