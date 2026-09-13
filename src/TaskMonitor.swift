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
    // 该提问是否为「多选」（arguments 里 questions[].multi_select == true）
    var multiSelect = false
}

/// 单个会话文件的监测游标
struct SessionCursor {
    /// 上次处理到的**字节位置**（不是行数）。nil = 尚未建立基线。
    /// 用字节偏移而非行数，是为了增量扫描时能直接跳过已处理的字节 ——
    /// 否则每次都要把整份日志按行拆分，实测那是扫描开销的大头。
    var byteOffset: Int? = nil
    var goalActive = false          // 该会话当前是否存在未完成（活跃）的 goal
    var pendingQuestionCallId: String?  // 正在等待用户处理的交互式提问（其 tool/result 到达＝已处理）
    var lastSize: Int?                  // 上次扫描时的文件大小（用于「未变化则跳过解压」）
    var lastMTime: Date?                // 上次扫描时的修改时间
}

/// 一次扫描的结果
struct ScanResult {
    var confirm = false   // 需要确认（审批 / 权限）
    var question = false  // 停下来等你选择（交互式提问 / 计划审批）
    var questionMulti = false  // 停下来等你选的是「多选」问题（末态用对勾动画）
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
        // 会话日志文件名随 dsh 格式版本演进：`session.jsonl.zstd`（旧）→ `session.v3.jsonl.zstd`（新）。
        // 曾经硬编码单一文件名，dsh 一换格式所有监测就静默失效（动画/提醒全不出来，
        // 见 docs/postmortem-2026-09-13-dsh-session-hang.md）。改为匹配 `session*.jsonl.zstd`，
        // 并对每个会话目录只保留最新一份，避免同一会话的多个格式文件被重复扫描。
        var latestByDir: [String: (Date, URL)] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("session"), name.hasSuffix(".jsonl.zstd") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let date = values?.contentModificationDate, date > cutoff else { continue }
            let dir = url.deletingLastPathComponent().path
            if let current = latestByDir[dir], current.0 >= date { continue }
            latestByDir[dir] = (date, url)
        }
        var found = Array(latestByDir.values)
        found.sort { $0.0 > $1.0 }
        return found.prefix(3).map { $0.1 }      // 只跟最近 3 个会话，控制单次扫描开销
    }

    /// 定位可用的 zstd 可执行文件（供解压与“环境自检”共用）；找不到返回 nil
    static func zstdExecutablePath() -> String? {
        let candidates = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// 用 zstd 解压会话日志，返回**原始字节**（不再按行拆分成 `[String]`）。
    ///
    /// 为什么不在这里拆行：对 14MB / 3.7 万行的日志做 `String.split` 会创建 3.7 万个 String，
    /// `sample` 采样显示它占单次扫描 CPU 的约 75%（热点在 `Collection.split` 与
    /// `String.subscript` / `_allASCII`）。改为字节级扫描后，只会为**真正新增的**少数几行
    /// 创建 String。缺 zstd 时返回 nil，调用方应优雅降级。
    static func decompressData(url: URL) -> Data? {
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
            return data
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
        var multiSelect = false
        if let data = obj["data"] as? [String: Any] {
            if type == "goal/change" {
                goalOp = data["operation"] as? String
                goalPhase = (data["goal"] as? [String: Any])?["phase"] as? String
            } else if type == "tool/call" {
                toolName = data["name"] as? String
                callId = data["callId"] as? String
                if let args = data["arguments"] as? String { multiSelect = isMultiSelectArguments(args) }
            } else if type == "tool/result" {
                // 注意：提问的结果事件里 callId 嵌套在 data.message.source.callId
                // （tool/call 才把它放在顶层），两种位置都要读
                callId = data["callId"] as? String
                    ?? ((data["message"] as? [String: Any])?["source"] as? [String: Any])?["callId"] as? String
            }
        }
        return MonitoredEvent(seq: seq, type: type, goalOp: goalOp, goalPhase: goalPhase,
                              toolName: toolName, callId: callId, multiSelect: multiSelect)
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

    /// 提问是否为多选：arguments 是 JSON 字符串，里面 questions[].multi_select / multiSelect 为 true
    static func isMultiSelectArguments(_ args: String) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(args.utf8)) as? [String: Any],
              let questions = obj["questions"] as? [[String: Any]] else { return false }
        return questions.contains {
            ($0["multi_select"] as? Bool) == true || ($0["multiSelect"] as? Bool) == true
        }
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
    ///
    /// 实现要点（性能）：解压后只在**字节层面**按 `\n` 切行，并且只处理
    /// `cursor.byteOffset` 之后的新增字节 —— 不再每次把整份日志拆成 [String]。
    static func scan(url: URL, cursor: inout SessionCursor) -> ScanResult {
        // 文件没变化就直接返回：避免白跑一次全量解压（14MB 日志约 0.26s），
        // 这样轮询间隔可以压到 0.4s 而几乎不占 CPU
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
        let mtime = attrs?[.modificationDate] as? Date
        if cursor.byteOffset != nil, cursor.lastSize == size, cursor.lastMTime == mtime {
            return ScanResult()
        }
        cursor.lastSize = size
        cursor.lastMTime = mtime
        guard let data = decompressData(url: url) else { return ScanResult() }
        let total = data.count

        if cursor.byteOffset == nil {
            return establishBaseline(data, total: total, cursor: &cursor)
        }

        let start = min(cursor.byteOffset!, total)
        guard total > start else { return ScanResult() }   // 无新增字节

        var result = ScanResult()
        var lineStart = start
        var i = start
        while i < total {
            if data[i] == 0x0A {                            // '\n'
                if i > lineStart {
                    applyLine(String(decoding: data[lineStart..<i], as: UTF8.self),
                              cursor: &cursor, result: &result)
                }
                lineStart = i + 1
            }
            i += 1
        }
        // 未以换行结尾的尾行留给下次（日志可能正写到一半，避免处理残缺的行）
        cursor.byteOffset = lineStart
        return result
    }

    /// 首次基线：字节级倒序扫描，确定当前是否已有活跃 goal / 活跃 turn。
    ///
    /// 判定 turn 是必需的：App（或 dsh）重启时若已有回合正在跑，它的 turn/start 落在
    /// 基线之前，不判定就会一直停在「空闲」直到下一个回合 —— 表现为「动画消失」。
    private static func establishBaseline(_ data: Data, total: Int, cursor: inout SessionCursor) -> ScanResult {
        var goalResolved = false
        var turnResolved = false
        var turnActive = false
        var lineEnd = total
        var i = total - 1
        while i >= 0 {
            if data[i] == 0x0A {                            // '\n'
                let from = i + 1
                if from < lineEnd {
                    let line = String(decoding: data[from..<lineEnd], as: UTF8.self)
                    // 注意：JSONSerialization 会把 "/" 转义为 "\/"，因此两种写法都要匹配
                    if !goalResolved, line.contains("goal/change") || line.contains("goal\\/change") {
                        if let e = parseLine(line), e.type == "goal/change" {
                            if isGoalActivateOp(e.goalOp) { cursor.goalActive = true }
                            else if isGoalCloseOp(e.goalOp) { cursor.goalActive = false }
                            goalResolved = true
                        }
                    }
                    if !turnResolved, line.contains("turn/start") || line.contains("turn/end") {
                        if let e = parseLine(line) {
                            if e.type == "turn/start" { turnActive = true; turnResolved = true }
                            else if e.type == "turn/end" { turnActive = false; turnResolved = true }
                        }
                    }
                }
                lineEnd = i
            }
            if goalResolved, turnResolved { break }
            i -= 1
        }
        cursor.byteOffset = total
        var baseline = ScanResult()
        baseline.busy = turnActive          // 让 tick() 立即进入「处理中」，动画随即恢复
        return baseline
    }

    /// 把一行事件套用到游标与扫描结果上（原 scan 内的 switch，原样抽出）
    private static func applyLine(_ line: String, cursor: inout SessionCursor, result: inout ScanResult) {
        guard let e = parseLine(line) else { return }
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
                if e.multiSelect { result.questionMulti = true }
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
}
